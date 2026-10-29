// Profiles one rows operation in headless Chromium and prints the functions
// with the most self time:
//
//   node bench/frontend-wasm/profile.mjs <warp|leptos> <dir> <operation> [top]
//
// <dir> is a build under target/frontend-bench/ (e.g. warp/rows-debug, whose
// module carries debug names). <operation> is one of: select, swap, replace,
// update, create. The page first creates 1,000 rows, then the profiler runs
// around the one operation only.

import { createRequire } from "node:module";
import { createServer } from "node:http";
import { readFile, readdir, writeFile } from "node:fs/promises";
import { extname, join, resolve, dirname } from "node:path";
import { fileURLToPath } from "node:url";

const here = dirname(fileURLToPath(import.meta.url));
const served = join(resolve(here, "..", ".."), "target", "frontend-bench");
const require = createRequire(import.meta.url);
const { chromium } = require(process.env.PLAYWRIGHT_CORE ?? "playwright-core");
const MIME = { ".js": "text/javascript", ".wasm": "application/wasm" };

const OPERATIONS = {
  select: ["document.querySelectorAll('#tbody > tr')[4].querySelector('a.lbl')", "document.querySelectorAll('#tbody > tr')[4].classList.contains('danger')"],
  swap: ["document.querySelector('#swaprows')", "window.__swapDone()"],
  replace: ["document.querySelector('#run')", "window.__replaced()"],
  update: ["document.querySelector('#update')", "document.querySelectorAll('#tbody > tr')[0].cells[1].textContent.endsWith('!!!')"],
  create: ["document.querySelector('#runlots')", "document.querySelectorAll('#tbody > tr').length === 10000"],
  create1k: ["document.querySelector('#run')", "document.querySelectorAll('#tbody > tr').length === 1000"],
};

async function main() {
  const [impl, dir, operation, topArg = "25"] = process.argv.slice(2);
  const files = await readdir(join(served, dir));
  const script = impl === "warp"
    ? (() => {
        const loader = files.find((file) => file.endsWith(".loader.js"));
        const wasm = files.find((file) => file.endsWith(".wasm") && !file.endsWith(".opt.wasm"));
        return `const { loadUnisonModule } = await import('/${dir}/${loader}');
                const { exports } = await loadUnisonModule(fetch('/${dir}/${wasm}'));
                exports.main();`;
      })()
    : (() => {
        const js = files.find((file) => file.endsWith(".js"));
        const wasm = files.find((file) => file.endsWith("_bg.wasm"));
        return `const mod = await import('/${dir}/${js}'); await mod.default({ module_or_path: '/${dir}/${wasm}' });`;
      })();
  const html = `<!doctype html><html><body><script type="module">${script} window.__ready = true;</script></body></html>`;
  const server = createServer(async (request, response) => {
    const path = new URL(request.url, "http://localhost").pathname;
    if (path === "/") { response.writeHead(200, { "content-type": "text/html" }); response.end(html); return; }
    try {
      const body = await readFile(join(served, path));
      response.writeHead(200, { "content-type": MIME[extname(path)] ?? "application/octet-stream" });
      response.end(body);
    } catch { response.writeHead(404); response.end(); }
  });
  await new Promise((done) => server.listen(0, "127.0.0.1", done));
  const browser = await chromium.launch({ executablePath: process.env.CHROMIUM_BIN, headless: true });
  const tab = await browser.newPage();
  await tab.goto(`http://127.0.0.1:${server.address().port}/`);
  await tab.waitForFunction(() => window.__ready);
  if (operation !== "create1k") await tab.evaluate(async () => {
    document.querySelector("#run").click();
    while (document.querySelectorAll("#tbody > tr").length !== 1000) await new Promise((done) => setTimeout(done, 10));
    const id = (index) => document.querySelectorAll("#tbody > tr")[index].cells[0].textContent;
    const before998 = id(998);
    const before0 = id(0);
    window.__swapDone = () => id(1) === before998;
    window.__replaced = () => document.querySelectorAll("#tbody > tr").length === 1000 && id(0) !== before0;
  });
  const client = await tab.context().newCDPSession(tab);
  await client.send("Profiler.enable");
  await client.send("Profiler.setSamplingInterval", { interval: 200 });
  await client.send("Profiler.start");
  const [target, done] = OPERATIONS[operation];
  const elapsed = await tab.evaluate(`(async () => {
    const started = performance.now();
    ${target}.click();
    while (!(${done})) await new Promise((resolve) => setTimeout(resolve, 0));
    return performance.now() - started;
  })()`);
  const { profile } = await client.send("Profiler.stop");
  await browser.close();
  server.close();
  if (process.env.PROFILE_OUT) await writeFile(process.env.PROFILE_OUT, JSON.stringify(profile));

  // Self time per function, from the sample counts.
  const interval = (profile.endTime - profile.startTime) / profile.samples.length / 1000;
  const counts = new Map();
  for (const sample of profile.samples) counts.set(sample, (counts.get(sample) ?? 0) + 1);
  const selfTime = new Map();
  for (const node of profile.nodes) {
    const frame = node.callFrame;
    const name = `${frame.functionName || "(anonymous)"} ${frame.url ? frame.url.split("/").pop() + ":" + frame.lineNumber : ""}`.trim();
    selfTime.set(name, (selfTime.get(name) ?? 0) + (counts.get(node.id) ?? 0) * interval);
  }
  // Time spent in the runtime's comparison and equality, by the nearest
  // Unison-named caller (a wasm frame with a debug name that is not a helper).
  const byId = new Map(profile.nodes.map((node) => [node.id, node]));
  const parentOf = new Map();
  for (const node of profile.nodes) for (const child of node.children ?? []) parentOf.set(child, node.id);
  const runtimeFrame = (frame) => frame.url.endsWith(".loader.js") || frame.functionName.startsWith("js-to-wasm") || frame.functionName.startsWith("wasm-to-js")
    || frame.functionName === "get value" || frame.functionName === "compareValues" || frame.functionName === "compareArgs" || /^(apply|callDirect|handle|shift|force|continue|dispatch|wasm-function)/i.test(frame.functionName) || frame.functionName === "";
  const callers = new Map();
  for (const [nodeId, count] of counts) {
    let node = byId.get(nodeId);
    if (!runtimeFrame(node.callFrame)) continue;
    let up = parentOf.get(nodeId);
    while (up !== undefined && runtimeFrame(byId.get(up).callFrame)) up = parentOf.get(up);
    const name = up === undefined ? "(root)" : byId.get(up).callFrame.functionName;
    callers.set(name, (callers.get(name) ?? 0) + count * interval);
  }
  const topCallers = [...callers.entries()].sort((left, right) => right[1] - left[1]).slice(0, 15).map(([name, ms]) => [name, Math.round(ms)]);
  const top = [...selfTime.entries()].sort((left, right) => right[1] - left[1]).slice(0, Number(topArg));
  console.log(JSON.stringify({ impl, dir, operation, elapsedMs: Math.round(elapsed), top: top.map(([name, ms]) => [name, Math.round(ms)]), runtimeTimeByCaller: topCallers }, null, 1));
}

main().catch((error) => { console.error(error); process.exit(1); });
