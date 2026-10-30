// Times a million ability operations through a warp handler written the way UI handlers
// carry state (`go state resume`), against the same work as plain calls, in headless
// Chromium. Build with `run bench.handlerCost.build <dir>` on warp `handler-cost`, then
// optimise as the benchmarks do and run:
//   wasm-opt <dir>/handler-cost.wasm -o <dir>/handler-cost.opt.wasm --enable-gc \
//     --enable-multivalue --enable-reference-types --enable-tail-call \
//     --enable-exception-handling --closed-world -O3 --gufa --converge
//   PLAYWRIGHT_CORE=... CHROMIUM_BIN=... node bench/handler-cost/run.mjs <dir> [wasm file]
import { createRequire } from "node:module";
import { createServer } from "node:http";
import { readFile } from "node:fs/promises";
import { join } from "node:path";
const require = createRequire(import.meta.url);
const { chromium } = require(process.env.PLAYWRIGHT_CORE ?? "playwright-core");
const dir = process.argv[2];
const wasmFile = process.argv[3] ?? "handler-cost.opt.wasm";
const types = { ".js": "text/javascript", ".wasm": "application/wasm", ".html": "text/html" };
const server = createServer(async (request, response) => {
  const path = request.url === "/" ? null : join(dir, request.url.slice(1));
  try {
    const body = path ? await readFile(path) : Buffer.from("<!doctype html><title>handler cost</title>");
    response.writeHead(200, { "content-type": types[path ? path.slice(path.lastIndexOf(".")) : ".html"] ?? "application/octet-stream" });
    response.end(body);
  } catch { response.writeHead(404); response.end(); }
});
await new Promise((done) => server.listen(0, "127.0.0.1", done));
const origin = `http://127.0.0.1:${server.address().port}`;
const browser = await chromium.launch({ executablePath: process.env.CHROMIUM_BIN, headless: true });
const page = await browser.newPage();
await page.goto(origin + "/");
const result = await page.evaluate(async (wasmFile) => {
  const { loadUnisonModule } = await import("/handler-cost.loader.js");
  const { exports } = await loadUnisonModule(fetch("/" + wasmFile));
  const fns = { handled: exports.handled, under4: exports.under4, under16: exports.under16, direct: exports.direct };
  const n = 1_000_000;
  const expected = fns.direct();
  for (const f of Object.values(fns)) f();
  const runs = Object.fromEntries(Object.keys(fns).map((k) => [k, []]));
  for (let r = 0; r < 15; r++) for (const [name, f] of Object.entries(fns)) {
    const t = performance.now(); const got = f(); const ms = performance.now() - t;
    if (got !== expected) return { error: `${name} returned ${got}, expected ${expected}` };
    runs[name].push(ms);
  }
  const median = (xs) => xs.sort((a, b) => a - b)[xs.length >> 1];
  return { operations: n, medianMs: Object.fromEntries(Object.entries(runs).map(([k, v]) => [k, +median(v).toFixed(2)])), nsPerOperation: Object.fromEntries(Object.entries(runs).map(([k, v]) => [k, +(median(v) * 1e6 / n).toFixed(1)])) };
}, wasmFile);
console.log(JSON.stringify(result));
await browser.close();
server.close();
