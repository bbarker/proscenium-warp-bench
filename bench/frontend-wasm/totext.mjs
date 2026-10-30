// Times a warp module whose exported `main` formats a million numbers with
// `Nat.toText` (`bench.totext.build` on `@dfreeman/proscenium/perf-r7`), to
// compare implementations of one builtin, here JS against Unison:
//
//   node bench/frontend-wasm/totext.mjs <dir> [<dir> ...]
//
// Each <dir> is a build under target/frontend-bench/ holding totext-bare.opt.wasm
// and totext-bare.loader.js. The runs are interleaved, one per module in turn, and
// the median of 9 is printed after one warm-up each, with the module's size.

import { readFile, stat } from "node:fs/promises";
import { join, resolve, dirname } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

const here = dirname(fileURLToPath(import.meta.url));
const served = join(resolve(here, "..", ".."), "target", "frontend-bench");

async function load(dir) {
  const { loadUnisonModule } = await import(pathToFileURL(join(served, dir, "totext-bare.loader.js")).href);
  const wasm = join(served, dir, "totext-bare.opt.wasm");
  const { exports } = await loadUnisonModule(await readFile(wasm));
  return { dir, main: exports.main, bytes: (await stat(wasm)).size };
}

const modules = await Promise.all(process.argv.slice(2).map(load));
const times = new Map(modules.map((module) => [module.dir, []]));
for (const module of modules) module.main(null);
for (let run = 0; run < 9; run += 1) {
  for (const module of modules) {
    const started = performance.now();
    module.main(null);
    times.get(module.dir).push(performance.now() - started);
  }
}
for (const module of modules) {
  const sorted = times.get(module.dir).sort((left, right) => left - right);
  console.log(`${module.dir}: median ${sorted[4].toFixed(1)} ms for 1,000,000 calls (min ${sorted[0].toFixed(1)}, max ${sorted[8].toFixed(1)}), module ${module.bytes} bytes`);
}
