// Splits each rows operation into ink's reconcile (Session.resume) and Proscenium's
// DOM sync (synchronize), in headless Chromium
// (docs/reports/FrontendWasmLeptosVsProscenium.md, round 5):
//
//   node bench/frontend-wasm/phases.mjs <dir> [iterations]
//
// <dir> is a warp build under target/frontend-bench/ whose flush pushes
// t0, t1, t2 onto window.__benchTimings around the two phases; round5.nu writes
// that flush and the transcript that builds it.
import { createRequire } from "node:module";
import { createServer } from "node:http";
import { readFile, readdir } from "node:fs/promises";
import { extname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { dirname, resolve } from "node:path";
const here = dirname(fileURLToPath(import.meta.url));
const served = resolve(here, "..", "..", "target", "frontend-bench");
const require = createRequire(import.meta.url);
const { chromium } = require(process.env.PLAYWRIGHT_CORE ?? "playwright-core");
const MIME = { ".js": "text/javascript", ".wasm": "application/wasm" };
const [dir, iterationsArg = "5"] = process.argv.slice(2);
const files = await readdir(join(served, dir));
const loader = files.find((f) => f.endsWith(".loader.js") && !f.includes(".min."));
const wasm = files.find((f) => f.endsWith(".wasm") && !f.endsWith(".opt.wasm"));
const html = `<!doctype html><html><body><script>window.__benchTimings = [];</script><script type="module">
const { loadUnisonModule } = await import('/${dir}/${loader}');
const { exports } = await loadUnisonModule(fetch('/${dir}/${wasm}'));
exports.main(); window.__ready = true;</script></body></html>`;
const server = createServer(async (req, res) => {
  const path = new URL(req.url, "http://localhost").pathname;
  if (path === "/") { res.writeHead(200, { "content-type": "text/html" }); res.end(html); return; }
  try { const body = await readFile(join(served, path)); res.writeHead(200, { "content-type": MIME[extname(path)] ?? "application/octet-stream" }); res.end(body); }
  catch { res.writeHead(404); res.end(); }
});
await new Promise((done) => server.listen(0, "127.0.0.1", done));
const OPS = [
  ["create 1k", "#run", "rows().length === 1000"],
  ["update 10th", "#update", "rows()[0].cells[1].textContent.endsWith('!!!')"],
  ["select", "@rows()[4].querySelector('a.lbl')", "rows()[4].classList.contains('danger')"],
  ["swap", "#swaprows", "rows()[1].cells[0].textContent === window.__before"],
  ["remove", "@rows()[9].querySelector('a.remove')", "rows().length === 999"],
  ["replace 1k", "#run", "rows().length === 1000 && rows()[0].cells[0].textContent !== window.__first"],
  ["append 1k", "#add", "rows().length === 2000"],
  ["clear 2k", "#clear", "rows().length === 0"],
  ["create 10k", "#runlots", "rows().length === 10000"],
  ["clear 10k", "#clear", "rows().length === 0"],
];
const browser = await chromium.launch({ executablePath: process.env.CHROMIUM_BIN, headless: true });
const results = {};
for (let it = 0; it < Number(iterationsArg); it++) {
  const tab = await browser.newPage();
  await tab.goto(`http://127.0.0.1:${server.address().port}/`);
  await tab.waitForFunction(() => window.__ready);
  for (const [name, target, done] of OPS) {
    const r = await tab.evaluate(async ([target, done]) => {
      const rows = () => document.querySelectorAll('#tbody > tr');
      window.__before = rows()[998]?.cells[0].textContent;
      window.__first = rows()[0]?.cells[0].textContent;
      await new Promise((d) => setTimeout(d, 50));
      window.__benchTimings = [];
      const el = target.startsWith("@") ? eval(target.slice(1)) : document.querySelector(target);
      const started = performance.now();
      el.click();
      let spins = 0;
      while (!eval(done) && spins < 1000) { await null; spins++; }
      while (!eval(done)) await new Promise((d) => setTimeout(d, 0));
      const total = performance.now() - started;
      const t = window.__benchTimings; let reconcile = 0, sync = 0; for (let i = 0; i + 2 < t.length; i += 3) { reconcile += t[i + 1] - t[i]; sync += t[i + 2] - t[i + 1]; }

      return { total, reconcile, sync, flushes: window.__benchTimings.length / 3 };
    }, [target, done]);
    (results[name] ??= []).push(r);
  }
  await tab.close();
}
await browser.close(); server.close();
const median = (xs) => { const s = [...xs].sort((a, b) => a - b); return s[Math.floor(s.length / 2)]; };
console.log("op".padEnd(14), "total", "reconcile", "sync", "flushes");
for (const [name, rs] of Object.entries(results))
  console.log(name.padEnd(14), median(rs.map((r) => r.total)).toFixed(1).padStart(7), median(rs.map((r) => r.reconcile)).toFixed(1).padStart(9), median(rs.map((r) => r.sync)).toFixed(1).padStart(7), rs[0].flushes);
