import { readFile } from "node:fs/promises";
const bytes = await readFile(new URL("./textb.wasm", import.meta.url));
let last = null;
const { instance } = await WebAssembly.instantiate(bytes, { env: { sink: (s) => { last = s; } } }, { builtins: ["js-string"] });
const { toJS, passJS, fromJS } = instance.exports;
const time = (f) => { const t = performance.now(); f(); return performance.now() - t; };
const median = (xs) => xs.sort((a, b) => a - b)[xs.length >> 1];
const label = "pretty red table, number 4242";
for (const [n, len] of [[10000, 8], [10000, 30], [100000, 30]]) {
  for (let w = 0; w < 3; w++) { toJS(n, len); passJS(label, n); fromJS(label, n); }
  const a = [], b = [], c = [];
  for (let r = 0; r < 15; r++) { a.push(time(() => toJS(n, len))); b.push(time(() => passJS(label, n))); c.push(time(() => fromJS(label.slice(0, len), n))); }
  console.log(JSON.stringify({ strings: n, chars: len, wasmArrayToJS_ms: +median(a).toFixed(3), alreadyJS_ms: +median(b).toFixed(3), jsToWasmArray_ms: +median(c).toFixed(3), sample: last.slice(0, 12) }));
}
