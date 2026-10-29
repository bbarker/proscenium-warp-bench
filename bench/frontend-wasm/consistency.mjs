// Checks that two builds of the rows app draw the same table after the same
// operations: `node bench/frontend-wasm/consistency.mjs <dirA> <dirB> [steps] [seed]`,
// with each dir a build under target/frontend-bench/ (e.g. leptos/rows-release and
// warp/rows-bare-perf). Both apps draw labels from the same seeded generator, so
// after every step their rows (id, label, selected) must match exactly. The
// operations are drawn at random, including clicks on rows, which exercises
// the keyed reconcile with moves, removals and insertions.

import { createRequire } from "node:module";
import { createServer } from "node:http";
import { readFile, readdir } from "node:fs/promises";
import { extname, join, resolve, dirname } from "node:path";
import { fileURLToPath } from "node:url";

const here = dirname(fileURLToPath(import.meta.url));
const served = join(resolve(here, "..", ".."), "target", "frontend-bench");
const require = createRequire(import.meta.url);
const { chromium } = require(process.env.PLAYWRIGHT_CORE ?? "playwright-core");
const MIME = { ".js": "text/javascript", ".wasm": "application/wasm" };

async function startScript(dir) {
  const files = await readdir(join(served, dir));
  if (dir.startsWith("warp/")) {
    const loader = files.find((file) => file.endsWith(".loader.min.js")) ?? files.find((file) => file.endsWith(".loader.js"));
    const wasm = files.find((file) => file.endsWith(".opt.wasm")) ?? files.find((file) => file.endsWith(".wasm"));
    return `const { loadUnisonModule } = await import('/${dir}/${loader}');
            const { exports } = await loadUnisonModule(fetch('/${dir}/${wasm}')); exports.main();`;
  }
  const js = files.find((file) => file.endsWith(".js"));
  const wasm = files.find((file) => file.endsWith("_bg.wasm"));
  return `const mod = await import('/${dir}/${js}'); await mod.default({ module_or_path: '/${dir}/${wasm}' });`;
}

// A small deterministic generator for the operation sequence.
function generator(seed) {
  let state = seed >>> 0;
  return (bound) => { state = (Math.imul(state, 1664525) + 1013904223) >>> 0; return state % bound; };
}

const SNAPSHOT = `[...document.querySelectorAll('#tbody > tr')].map((row) =>
  row.cells[0].textContent + '|' + row.cells[1].textContent + '|' + row.classList.contains('danger'))`;

async function main() {
  const [dirA, dirB, stepsArg = "60", seedArg = "7"] = process.argv.slice(2);
  const pages = new Map([["/a", await startScript(dirA)], ["/b", await startScript(dirB)]]);
  const server = createServer(async (request, response) => {
    const path = new URL(request.url, "http://localhost").pathname;
    if (pages.has(path)) {
      response.writeHead(200, { "content-type": "text/html" });
      response.end(`<!doctype html><html><body><script type="module">${pages.get(path)} window.__ready = true;</script></body></html>`);
      return;
    }
    try {
      const body = await readFile(join(served, path));
      response.writeHead(200, { "content-type": MIME[extname(path)] ?? "application/octet-stream" });
      response.end(body);
    } catch { response.writeHead(404); response.end(); }
  });
  await new Promise((done) => server.listen(0, "127.0.0.1", done));
  const base = `http://127.0.0.1:${server.address().port}`;
  const browser = await chromium.launch({ executablePath: process.env.CHROMIUM_BIN, headless: true });
  const tabs = await Promise.all(["/a", "/b"].map(async (path) => {
    const tab = await browser.newPage();
    await tab.goto(base + path);
    await tab.waitForFunction(() => window.__ready);
    return tab;
  }));
  const next = generator(Number(seedArg));
  const buttons = ["run", "add", "update", "clear", "swaprows", "rotate"];
  let failures = 0;
  const settle = async (tab) => {
    // Wait until the table stops changing for a few frames.
    let previous = null;
    for (let stable = 0; stable < 3;) {
      await tab.waitForTimeout(30);
      const now = JSON.stringify(await tab.evaluate(SNAPSHOT));
      stable = now === previous ? stable + 1 : 0;
      previous = now;
    }
    return JSON.parse(previous);
  };
  for (let step = 0; step < Number(stepsArg); step += 1) {
    const rows = (await tabs[0].evaluate(SNAPSHOT)).length;
    const choice = rows > 0 ? next(11) : next(2) === 0 ? 0 : 1;
    let description;
    if (choice < 6) {
      const button = buttons[choice];
      description = `click #${button}`;
      for (const tab of tabs) await tab.click(`#${button}`);
    } else {
      const index = next(rows);
      const target = choice < 9 ? "a.remove" : "a.lbl";
      description = `${target} on row ${index}`;
      for (const tab of tabs) await tab.evaluate(([at, selector]) => document.querySelectorAll("#tbody > tr")[at].querySelector(selector).click(), [index, target]);
    }
    const [a, b] = await Promise.all(tabs.map(settle));
    const same = a.length === b.length && a.every((row, at) => row === b[at]);
    if (!same) {
      failures += 1;
      const at = a.findIndex((row, index) => row !== b[index]);
      console.log(`step ${step} (${description}): MISMATCH at row ${at}: ${a[at]} vs ${b[at]} (${a.length} vs ${b.length} rows)`);
      if (failures > 3) break;
    } else {
      console.log(`step ${step} (${description}): ok, ${a.length} rows`);
    }
  }
  await browser.close();
  server.close();
  console.log(failures === 0 ? "CONSISTENT" : `INCONSISTENT (${failures} steps)`);
  process.exit(failures === 0 ? 0 : 1);
}

main().catch((error) => { console.error(error); process.exit(1); });
