// Runtime half of the frontend benchmark
// (docs/reports/FrontendWasmLeptosVsProscenium.md): serves the builds under
// target/frontend-bench/ and times each operation in headless Chromium.
//
//   node bench/frontend-wasm/runtime.mjs <suite> [iterations]
//
// <suite> is `rows` (js-framework-benchmark operations), `cards-<count>` or
// `counter`. Each iteration opens a fresh browser context, loads the page,
// and times each operation twice: until the DOM shows the end state (`dom`),
// and until the frame after it has been produced (`frame`). Medians and the
// spread are printed as JSON and appended to results/runtime.jsonl.
//
// Playwright is `playwright-core` from node_modules (`npm install` at the repo
// root, or PLAYWRIGHT_CORE=<path>) driving the
// devShell's Chromium (CHROMIUM_BIN).

import { createRequire } from "node:module";
import { createServer } from "node:http";
import { readFile, appendFile, stat } from "node:fs/promises";
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

function page(script) {
  return `<!doctype html><html><head><meta charset="utf-8"><title>bench</title>
<style>.danger { background: #fdd; }</style></head><body>
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
window.__frame = () => new Promise((done) => requestAnimationFrame(() => setTimeout(done, 0)));
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

async function runImplementation(browser, base, name, path, operations, iterations) {
  const samples = {};
  const add = (key, value) => { (samples[key] ??= []).push(value); };
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
    await tab.evaluate(HELPERS);
    for (const [operation, body] of operations) {
      const result = await tab.evaluate(`(async () => { ${body} })()`);
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
      }
    }
    if (errors.length) throw new Error(`${name}: ${errors.join("; ")}`);
    await context.close();
  }
  return Object.fromEntries(Object.entries(samples).map(([key, values]) => [key, {
    median: round(median(values)), min: round(Math.min(...values)), max: round(Math.max(...values)),
  }]));
}

async function main() {
  const [suite = "rows", iterationArg = "7"] = process.argv.slice(2);
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
  const browser = await chromium.launch({ executablePath: process.env.CHROMIUM_BIN, headless: true });
  const results = {};
  const version = browser.version();
  try {
    for (const name of Object.keys(available)) {
      results[name] = await runImplementation(browser, base, name, `/${name}.html`, operations, iterations);
    }
  } finally {
    await browser.close();
    server.close();
  }
  const line = { suite, iterations, at: new Date().toISOString(), load: loadavg().map(round), cpus: cpus().length,
    chromium: version, results };
  await appendFile(join(here, "results", "runtime.jsonl"), JSON.stringify(line) + "\n");
  console.log(JSON.stringify(line, null, 2));
}

main().catch((error) => { console.error(error); process.exit(1); });
