// Runtime half of the frontend benchmark
// (docs/reports/FrontendWasmLeptosVsProscenium.md): serves the builds under
// target/frontend-bench/ and times each operation in headless Chromium.
//
//   node bench/frontend-wasm/runtime.mjs <suite> [iterations]
//
// <suite> is `rows` (js-framework-benchmark operations), `meals` (a meal
// planner's week, grocery list and recipe search; see the report), `cards-<count>`
// or `counter`. Each iteration opens a fresh browser context, loads the page,
// and times each operation twice: until the DOM shows the end state (`dom`),
// and until the frame after it has been produced (`frame`). Medians and the
// spread are printed as JSON and appended to results/runtime.jsonl.
//
// Playwright is `playwright-core` from node_modules (`npm install` at the repo
// root, or PLAYWRIGHT_CORE=<path>) driving the
// devShell's Chromium (CHROMIUM_BIN).
//
// BENCH_COUNT=1 counts instead of timing: every function a wasm module imports
// from JS and every export JS calls is wrapped, and each operation reports how
// often each was called, with the JS import (if any) that was running when an
// export was called. The `wasm:js-string` builtins are compiled into the module
// and are not counted. The wrappers slow everything down, so the times are not
// kept; the counts go to results/boundary-<suite>.json.

import { createRequire } from "node:module";
import { createServer } from "node:http";
import { readFile, appendFile, stat, writeFile } from "node:fs/promises";
import { extname, join, resolve, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import { cpus, loadavg } from "node:os";

const here = dirname(fileURLToPath(import.meta.url));
const root = resolve(here, "..", "..");
const served = join(root, "target", "frontend-bench");
const require = createRequire(import.meta.url);
const { chromium } = require(process.env.PLAYWRIGHT_CORE ?? "playwright-core");

const MIME = { ".js": "text/javascript", ".wasm": "application/wasm", ".html": "text/html" };

// The implementations each suite compares: where its files are and how its page starts it.
function implementations(app) {
  const crate = `bench_${app.startsWith("cards") ? "cards" : app}`;
  const leptosDir = `leptos/${app}-release`;
  const warpDir = `warp/${app}-bare`;
  const warpStem = `${app}-bare`;
  return {
    leptos: {
      files: [`${leptosDir}/${crate}_bg.wasm`, `${leptosDir}/${crate}.js`],
      script: `const mod = await import('/${leptosDir}/${crate}.js');
               const wasm = await mod.default({ module_or_path: '/${leptosDir}/${crate}_bg.wasm' });
               window.__linearMemory = () => wasm.memory.buffer.byteLength;`,
    },
    warp: {
      files: [`${warpDir}/${warpStem}.opt.wasm`, `${warpDir}/${warpStem}.loader.min.js`],
      script: `const { loadUnisonModule } = await import('/${warpDir}/${warpStem}.loader.min.js');
               const { exports } = await loadUnisonModule(fetch('/${warpDir}/${warpStem}.opt.wasm'));
               exports.main();
               window.__linearMemory = () => 0;`,
    },
    ...Object.fromEntries((process.env.BENCH_VARIANTS ?? "perf,perf-compare,perf-eq,perf-keys,perf-targeted").split(",").map((variant) => [`warp-${variant}`, {
      files: [`${warpDir}-${variant}/${warpStem}.opt.wasm`, `${warpDir}-${variant}/${warpStem}.loader.min.js`],
      script: `const { loadUnisonModule } = await import('/${warpDir}-${variant}/${warpStem}.loader.min.js');
               const { exports } = await loadUnisonModule(fetch('/${warpDir}-${variant}/${warpStem}.opt.wasm'));
               exports.main();
               window.__linearMemory = () => 0;`,
    }])),
    "warp-unoptimized": {
      files: [`${warpDir}/${warpStem}.wasm`, `${warpDir}/${warpStem}.loader.js`],
      script: `const { loadUnisonModule } = await import('/${warpDir}/${warpStem}.loader.js');
               const { exports } = await loadUnisonModule(fetch('/${warpDir}/${warpStem}.wasm'));
               exports.main();
               window.__linearMemory = () => 0;`,
    },
  };
}

const COUNTING = process.env.BENCH_COUNT === "1";
// BENCH_INTERLEAVE=1 runs one iteration of each implementation in turn instead
// of all of one implementation's iterations together.
const INTERLEAVED = process.env.BENCH_INTERLEAVE === "1";
// BENCH_GC=1 forces a full garbage collection before each operation (Chromium is
// started with --expose-gc), so a collection owed by earlier operations is not
// paid inside a later one's time.
const FORCE_GC = process.env.BENCH_GC === "1";

// Installed before the page's script when counting. An import is labelled by
// its name when the name is readable (`##Nat.toText`), and otherwise (warp's
// FFI imports are keyed by hash) by the start of its source.
const COUNTER = `
window.__counts = {};
const running = [];
const labelOf = (module, name, fn) => /^[\\x20-\\x7e]+$/.test(name) ? module + ':' + name
  : module + ':ffi ' + String(fn).replace(/\\s+/g, ' ').replace(/^\\(?[^)]*\\)? ?=> ?\\{? ?/, '').slice(0, 90);
const bump = (key) => { window.__counts[key] = (window.__counts[key] ?? 0) + 1; };
const wrapImports = (imports) => Object.fromEntries(Object.entries(imports ?? {}).map(([module, members]) => [module,
  Object.fromEntries(Object.entries(members).map(([name, value]) => {
    if (typeof value !== 'function') return [name, value];
    const label = 'import ' + labelOf(module, name, value);
    return [name, function (...args) { bump(label); running.push(label); try { return value.apply(this, args); } finally { running.pop(); } }];
  }))]));
// A module rewritten by instrument.nu exports its site counters as memory.
let siteCounters = null;
const wrapExports = (instance) => (siteCounters ??= instance.exports.__counts ?? null, { exports: Object.fromEntries(Object.entries(instance.exports).map(([name, value]) =>
  [name, typeof value !== 'function' ? value : (...args) => {
    bump('export ' + name + (running.length ? ' <- ' + running[running.length - 1] : ' <- JS'));
    return value(...args);
  }])) });
const instantiate = WebAssembly.instantiate.bind(WebAssembly);
const instantiateStreaming = WebAssembly.instantiateStreaming.bind(WebAssembly);
WebAssembly.instantiateStreaming = async (source, imports, options) => {
  const result = await instantiateStreaming(source, wrapImports(imports), options);
  return { module: result.module, instance: wrapExports(result.instance) };
};
WebAssembly.instantiate = async (source, imports, options) => {
  const result = await instantiate(source, wrapImports(imports), options);
  return result instanceof WebAssembly.Instance ? wrapExports(result) : { module: result.module, instance: wrapExports(result.instance) };
};
window.__takeCounts = () => { const counts = window.__counts; window.__counts = {}; return counts; };
window.__takeSites = () => {
  if (!siteCounters) return null;
  const view = new Uint32Array(siteCounters.buffer);
  const sites = {};
  view.forEach((count, site) => { if (count) sites[site] = count; });
  view.fill(0);
  return sites;
};
`;

function page(script) {
  return `<!doctype html><html><head><meta charset="utf-8"><title>bench</title>
${COUNTING ? `<script>${COUNTER}</script>` : ""}
<style>.danger { background: #fdd; }
.hidden { display: none; }
.day { display: inline-block; vertical-align: top; width: 13rem; margin: 0 0.25rem; }
.thumb { display: inline-block; width: 2rem; height: 2rem; background: #ddd; }
.bar { height: 4px; background: #4a9; }
@keyframes mascot-bob { 0%, 100% { transform: translateY(0); } 50% { transform: translateY(-6px); } }
@keyframes mascot-wave { 0%, 100% { transform: rotate(0); } 50% { transform: rotate(-35deg); } }
.mascot-whole { animation: mascot-bob 1.2s ease-in-out 3; }
.mascot[data-pose="wave"] .mascot-limb { transform-origin: 89px 60px; animation: mascot-wave 0.6s ease-in-out 4; }
</style></head><body>
<script type="module">
try {
  ${script}
  window.__ready = performance.now();
} catch (error) { window.__failed = String(error && error.stack || error); }
</script></body></html>`;
}

function serve(pages) {
  const server = createServer(async (request, response) => {
    const url = new URL(request.url, "http://localhost");
    try {
      if (pages.has(url.pathname)) {
        response.writeHead(200, { "content-type": "text/html", "cache-control": "no-store" });
        response.end(pages.get(url.pathname));
      } else {
        const file = join(served, url.pathname);
        const body = await readFile(file);
        response.writeHead(200, { "content-type": MIME[extname(file)] ?? "application/octet-stream", "cache-control": "no-store" });
        response.end(body);
      }
    } catch {
      response.writeHead(404);
      response.end();
    }
  });
  return new Promise((done) => server.listen(0, "127.0.0.1", () => done(server)));
}

// In-page helpers: click, then yield one task at a time (no timer clamping)
// until the end state holds, then wait for the next frame.
const HELPERS = `
window.__yield = () => new Promise((done) => { const channel = new MessageChannel(); channel.port1.onmessage = () => done(); channel.port2.postMessage(0); });
// Every animation-frame callback the page asks for is timed, so an animation
// written in either language is measured by the scripting it costs per frame.
window.__raf = window.requestAnimationFrame.bind(window);
window.__rafStats = { ms: 0, calls: 0, max: 0 };
window.requestAnimationFrame = (callback) => window.__raf((stamp) => {
  const started = performance.now();
  try { callback(stamp); } finally {
    const spent = performance.now() - started;
    window.__rafStats.ms += spent; window.__rafStats.calls += 1; window.__rafStats.max = Math.max(window.__rafStats.max, spent);
  }
});
window.__frame = () => new Promise((done) => window.__raf(() => setTimeout(done, 0)));
window.__rows = () => document.querySelectorAll('#tbody > tr');
window.__rowId = (index) => { const row = window.__rows()[index]; return row ? row.cells[0].textContent : null; };
window.__measure = async (target, predicate) => {
  const element = typeof target === 'string' ? document.querySelector(target) : target();
  if (!element) throw new Error('no element for ' + target);
  const started = performance.now();
  element.click();
  // Microtasks first: a framework that flushes in a microtask (Proscenium) has
  // then finished without the browser rendering in between, as Leptos has
  // when click() returns. A task yield lets the browser lay out and paint
  // first, which would count rendering against one side only.
  let spins = 0;
  while (!predicate() && spins < 1000) { await null; ++spins; }
  while (!predicate()) { await window.__yield(); if (++spins > 2000000) throw new Error('timed out on ' + target); }
  const dom = performance.now() - started;
  await window.__frame();
  return { dom, frame: performance.now() - started };
};
// Like __measure, with an action in place of a click: typing into a box.
window.__measureAction = async (action, predicate) => {
  const started = performance.now();
  action();
  let spins = 0;
  while (!predicate() && spins < 1000) { await null; ++spins; }
  while (!predicate()) { await window.__yield(); if (++spins > 2000000) throw new Error('timed out'); }
  const dom = performance.now() - started;
  await window.__frame();
  return { dom, frame: performance.now() - started };
};
window.__type = (text) => () => { const box = document.querySelector('#search-input'); box.value = text; box.dispatchEvent(new Event('input', { bubbles: true })); };
window.__note = () => document.querySelector('#search-note').textContent;
window.__slotName = (slot) => document.querySelector('[data-slot="' + slot + '"] .slot-name').textContent;
window.__weekTotal = () => document.querySelector('#week-total').textContent;
`;

// Each suite's operations, in order, as [name, in-page async function body].
const SUITES = {
  counter: [
    ["click", `return __measure('#inc', () => document.querySelector('#count').textContent === '1');`],
  ],
  rows: [
    ["create 1k", `return __measure('#run', () => __rows().length === 1000);`],
    ["update every 10th", `return __measure('#update', () => __rows()[0].cells[1].textContent.endsWith('!!!'));`],
    ["select row", `return __measure(() => __rows()[4].querySelector('a.lbl'), () => __rows()[4].classList.contains('danger'));`],
    ["swap rows", `const before = __rowId(998); return __measure('#swaprows', () => __rowId(1) === before);`],
    ["remove row", `return __measure(() => __rows()[9].querySelector('a.remove'), () => __rows().length === 999);`],
    ["replace 1k", `const before = __rowId(0); return __measure('#run', () => __rows().length === 1000 && __rowId(0) !== before);`],
    ["append 1k", `return __measure('#add', () => __rows().length === 2000);`],
    ["clear 2k", `return __measure('#clear', () => __rows().length === 0);`],
    ["create 10k", `return __measure('#runlots', () => __rows().length === 10000);`],
    ["memory 10k", `return { jsHeap: 0, linear: __linearMemory() };`],
    ["clear 10k", `return __measure('#clear', () => __rows().length === 0);`],
  ],
  // A meal planner's page (bench-meals / bench.meals.ui): a 7-day week of 4 meals
  // with totals, its grocery list, a 240-recipe search and an SVG mascot.
  meals: [
    ["plan week", `return __measure('#plan', () => document.querySelectorAll('#week .slot').length === 28 && !!document.querySelector('#grocery .item'));`],
    ["open tray", `return __measure('[data-slot="21"] .more', () => !document.querySelector('[data-slot="21"] .tray').classList.contains('hidden'));`],
    ["open macros", `return __measure('#day-0 .macros-toggle', () => document.querySelectorAll('#day-0 .bar').length === 4);`],
    ["shuffle meal", `const before = __slotName(21); return __measure('[data-slot="21"] .shuffle', () => __slotName(21) !== before);`],
    ["add serving", `return __measure('[data-slot="21"] .serv-plus', () => document.querySelector('[data-slot="21"] .servings').textContent === '2');`],
    ["remove meal", `return __measure('[data-slot="43"] .remove', () => document.querySelectorAll('#day-4 .slot').length === 3);`],
    ["replan week", `const before = __weekTotal(); return __measure('#replan', () => __weekTotal() !== before && document.querySelectorAll('#week .slot').length === 28);`],
    ["check item", `return __measure(() => document.querySelector('#grocery .aisle .check'), () => document.querySelectorAll('#checked .item').length === 1);`],
    ["uncheck item", `return __measure('#checked .check', () => document.querySelectorAll('#checked .item').length === 0);`],
    ["move day (FLIP)", `document.body.removeAttribute('data-flip');
      Object.assign(__rafStats, { ms: 0, calls: 0, max: 0 });
      const timed = await __measure('#move', () => document.querySelector('#week .day').id === 'day-1');
      while (!document.body.hasAttribute('data-flip')) await new Promise((done) => setTimeout(done, 5));
      return { ...timed, raf: { ...__rafStats }, moved: Number(document.body.getAttribute('data-flip')) };`],
    ["type 7 keys", `let dom = 0, frame = 0;
      for (const prefix of ['c', 'ch', 'chi', 'chic', 'chick', 'chicke', 'chicken']) {
        const timed = await __measureAction(__type(prefix), () => __note().endsWith('"' + prefix + '"'));
        dom += timed.dom; frame += timed.frame;
      }
      return { dom, frame };`],
    ["clear search", `return __measureAction(__type(''), () => __note().endsWith('""') && document.querySelectorAll('#results li').length === 240);`],
    ["wave", `return __measure('#pose', () => document.querySelector('#mascot').getAttribute('data-pose') === 'wave');`],
    ["dom nodes", `return { nodes: document.getElementsByTagName('*').length };`],
  ],
};

function cardsSuite(count) {
  const last = count - 1;
  return [
    ["toggle card 7", `return __measure('#card-7 .toggle', () => !!document.querySelector('#card-7 .details'));`],
    ["toggle card 7 back", `return __measure('#card-7 .toggle', () => !document.querySelector('#card-7 .details'));`],
    [`toggle card ${last}`, `return __measure('#card-${last} .toggle', () => !!document.querySelector('#card-${last} .details'));`],
    ["dom nodes", `return { nodes: document.getElementsByTagName('*').length };`],
  ];
}

const median = (values) => {
  const sorted = [...values].sort((left, right) => left - right);
  const middle = Math.floor(sorted.length / 2);
  return sorted.length % 2 ? sorted[middle] : (sorted[middle - 1] + sorted[middle]) / 2;
};
const round = (value) => Math.round(value * 100) / 100;

const summarise = (samples) => Object.fromEntries(Object.entries(samples).map(([key, values]) => [key, {
  median: round(median(values)), min: round(Math.min(...values)), max: round(Math.max(...values)),
}]));

async function runImplementation(browser, base, name, path, operations, iterations, samples = {}) {
  const add = (key, value) => { (samples[key] ??= []).push(value); };
  // With BENCH_COUNT, each operation's counts from the last iteration, and
  // the site counters of a module instrument.nu rewrote, under `sites`.
  const counts = {};
  const takeCounts = async (operation, tab) => {
    if (!COUNTING) return;
    counts[operation] = await tab.evaluate(() => window.__takeCounts?.() ?? {});
    const sites = await tab.evaluate(() => window.__takeSites?.() ?? null);
    if (sites) (counts.sites ??= {})[operation] = sites;
  };
  for (let iteration = 0; iteration < iterations; iteration += 1) {
    const context = await browser.newContext();
    const tab = await context.newPage();
    const client = await context.newCDPSession(tab);
    await client.send("Performance.enable");
    const errors = [];
    tab.on("pageerror", (error) => errors.push(String(error)));
    await tab.goto(base + path);
    await tab.waitForFunction(() => window.__ready || window.__failed, null, { timeout: 120000 });
    const failed = await tab.evaluate(() => window.__failed);
    if (failed) throw new Error(`${name}: ${failed}`);
    await tab.waitForSelector("#app", { timeout: 120000 });
    add("load (ready)", await tab.evaluate(() => window.__ready));
    await takeCounts("load (ready)", tab);
    await tab.evaluate(HELPERS);
    for (const [operation, body] of operations) {
      if (FORCE_GC) await tab.evaluate(() => window.gc?.());
      const result = await tab.evaluate(`(async () => { ${body} })()`);
      await takeCounts(operation, tab);
      if (operation.startsWith("memory")) {
        const metrics = (await client.send("Performance.getMetrics")).metrics;
        const heap = metrics.find((metric) => metric.name === "JSHeapUsedSize").value;
        add(`${operation} js heap MB`, heap / 1e6);
        add(`${operation} linear memory MB`, result.linear / 1e6);
      } else if (operation === "dom nodes") {
        add("dom nodes", result.nodes);
      } else {
        add(`${operation} dom`, result.dom);
        add(`${operation} frame`, result.frame);
        if (result.raf) {
          add(`${operation} rAF script ms`, result.raf.ms);
          add(`${operation} rAF callbacks`, result.raf.calls);
          add(`${operation} rAF max ms`, result.raf.max);
          add(`${operation} elements moved`, result.moved);
        }
      }
    }
    if (errors.length) throw new Error(`${name}: ${errors.join("; ")}`);
    await context.close();
  }
  if (COUNTING) return counts;
  return summarise(samples);
}

async function main() {
  const [suite = "rows", iterationArg = "7"] = process.argv.slice(2);
  const loadAtStart = loadavg().map(round);
  const iterations = Number(iterationArg);
  const operations = suite.startsWith("cards-") ? cardsSuite(Number(suite.slice(6))) : SUITES[suite];
  if (!operations) throw new Error(`unknown suite ${suite}`);
  const impls = implementations(suite);
  const available = {};
  const wanted = process.env.BENCH_IMPLS ? process.env.BENCH_IMPLS.split(",") : Object.keys(impls);
  for (const [name, impl] of Object.entries(impls).filter(([name]) => wanted.includes(name))) {
    const present = await Promise.all(impl.files.map((file) => stat(join(served, file)).then(() => true, () => false)));
    if (present.every(Boolean)) available[name] = impl;
    else console.error(`skipping ${name}: missing ${impl.files.join(", ")}`);
  }
  const pages = new Map(Object.entries(available).map(([name, impl]) => [`/${name}.html`, page(impl.script)]));
  const server = await serve(pages);
  const base = `http://127.0.0.1:${server.address().port}`;
  const browser = await chromium.launch({ executablePath: process.env.CHROMIUM_BIN, headless: true, args: FORCE_GC ? ["--js-flags=--expose-gc"] : [] });
  const results = {};
  const version = browser.version();
  try {
    if (INTERLEAVED && !COUNTING) {
      // One iteration of each implementation in turn, so a change in the
      // machine's load during the run reaches every implementation alike.
      const samples = Object.fromEntries(Object.keys(available).map((name) => [name, {}]));
      for (let iteration = 0; iteration < iterations; iteration += 1) {
        for (const name of Object.keys(available)) {
          await runImplementation(browser, base, name, `/${name}.html`, operations, 1, samples[name]);
        }
      }
      for (const name of Object.keys(available)) results[name] = summarise(samples[name]);
    } else {
      for (const name of Object.keys(available)) {
        results[name] = await runImplementation(browser, base, name, `/${name}.html`, operations, iterations);
      }
    }
  } finally {
    await browser.close();
    server.close();
  }
  const line = { suite, iterations, at: new Date().toISOString(), load: loadavg().map(round), cpus: cpus().length,
    chromium: version, interleaved: INTERLEAVED, forcedGC: FORCE_GC, loadAtStart, results };
  if (COUNTING) {
    await writeFile(join(here, "results", `boundary-${suite}.json`), JSON.stringify({ ...line, kind: "boundary counts" }, null, 1) + "\n");
  } else {
    await appendFile(join(here, "results", "runtime.jsonl"), JSON.stringify(line) + "\n");
  }
  console.log(JSON.stringify(line, null, 2));
}

main().catch((error) => { console.error(error); process.exit(1); });
