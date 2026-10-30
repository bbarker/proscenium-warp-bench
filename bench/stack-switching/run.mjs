// Times the three one-shot handlers in handlers.wat in headless Chromium with V8's core
// stack switching enabled (--js-flags=--experimental-wasm-wasmfx; Node 24's V8 13.6 has
// the types but none of the instructions):
//   PLAYWRIGHT_CORE=... CHROMIUM_BIN=... node bench/stack-switching/run.mjs <handlers.wasm>
// Build the module with `wasm-tools parse bench/stack-switching/handlers.wat -o handlers.wasm`.
import { createRequire } from "node:module";
import { readFile } from "node:fs/promises";
const require = createRequire(import.meta.url);
const { chromium } = require(process.env.PLAYWRIGHT_CORE ?? "playwright-core");
const browser = await chromium.launch({ executablePath: process.env.CHROMIUM_BIN, headless: true, args: ["--js-flags=--experimental-wasm-wasmfx"] });
const page = await browser.newPage();
const bytes = [...await readFile(process.argv[2])];
const result = await page.evaluate(async (b) => {
  const { instance } = await WebAssembly.instantiate(new Uint8Array(b));
  const fns = { stackSwitching: instance.exports.stackSwitching, cps1: instance.exports.cps1, cps10: instance.exports.cps10 };
  const n = 1_000_000;
  const expected = Number(BigInt(n) * BigInt(n + 1) / 2n % 4294967296n) | 0;
  for (const f of Object.values(fns)) f(n);
  const runs = Object.fromEntries(Object.keys(fns).map((k) => [k, []]));
  for (let r = 0; r < 15; r++) for (const [name, f] of Object.entries(fns)) {
    const t = performance.now(); const got = f(n); const ms = performance.now() - t;
    if ((got | 0) !== expected) return { error: `${name} returned ${got}, expected ${expected}` };
    runs[name].push(ms);
  }
  const median = (xs) => xs.sort((a, b) => a - b)[xs.length >> 1];
  return { operations: n, medianMs: Object.fromEntries(Object.entries(runs).map(([k, v]) => [k, +median(v).toFixed(2)])), nsPerOperation: Object.fromEntries(Object.entries(runs).map(([k, v]) => [k, +(median(v) * 1e6 / n).toFixed(1)])) };
}, bytes);
console.log(JSON.stringify(result));
await browser.close();
