// The page half of the dev loop (docs/REPORT.md, "The dev loop, wired up"):
// a running page that takes warp deltas instead of reloading.
//
//   node bench/frontend-wasm/devloop.mjs <dir> <iterations> <step>=<card>:<text> ...
//   node bench/frontend-wasm/devloop.mjs leptos/<dir> <iterations>
//
// <dir> is under target/frontend-bench/ and holds what the dev loop's host half
// wrote: `base.wasm` and `base.loader.js` (`bench.dev.base`), and for each step
// `delta-<step>.wasm` and `ui-<step>.bin` (`bench.dev.delta`). Each iteration
// opens a fresh browser context and loads the base page, which runs
// `bench.dev.client`. It then opens card 3 with a click, so the page holds
// state an edit does not touch, and applies the steps in order. For each step
// it times:
//
// - `fetch`: fetching the delta and the UI value,
// - `applied`: from handing them to the page until the client has loaded the
//   delta's terms, loaded the UI and rendered it (`host.applied()`),
// - `dom`: from handing them over until card <card>'s paragraph reads <text>,
//
// and checks that card 3 is still open with its count at 1. A reload of the
// base page is timed as well (`load (ready)`), since that is what a full
// rebuild costs the page instead. Medians and spread are printed as JSON and
// appended to results/devloop.jsonl, with the machine's load average.
//
// Playwright is `playwright-core` from node_modules (or PLAYWRIGHT_CORE)
// driving the devShell's Chromium (CHROMIUM_BIN), as in runtime.mjs.

import { createRequire } from "node:module";
import { createServer } from "node:http";
import { readFile, appendFile } from "node:fs/promises";
import { extname, join, resolve, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import { cpus, loadavg } from "node:os";

const here = dirname(fileURLToPath(import.meta.url));
const root = resolve(here, "..", "..");
const served = join(root, "target", "frontend-bench");
const require = createRequire(import.meta.url);
const { chromium } = require(process.env.PLAYWRIGHT_CORE ?? "playwright-core");

const MIME = { ".js": "text/javascript", ".wasm": "application/wasm", ".html": "text/html" };
const round = (value) => Math.round(value * 100) / 100;

// The card the page opens before any edit, whose state an edit must leave alone.
const KEPT_CARD = 3;

// The page is ready when the last card is drawn: card <count - 1>, from the
// build directory's name (`cards-<count>-...`).
const lastCard = (dir) => Number(dir.match(/cards-(\d+)/)?.[1] ?? 400) - 1;

// A Leptos build's page (`leptos/<dir>`, no steps): what a Leptos edit costs the
// page instead is a reload, so only `load (ready)` is timed.
function leptosPage(dir) {
  return `<!doctype html><html><head><meta charset="utf-8"><title>dev loop</title>
<style>.hidden { display: none; }</style></head><body><script type="module">
const started = performance.now();
const mod = await import('/${dir}/bench_cards.js');
await mod.default({ module_or_path: '/${dir}/bench_cards_bg.wasm' });
const ready = () => document.getElementById('card-${lastCard(dir)}') ? (window.__ready = performance.now() - started) : requestAnimationFrame(ready);
ready();
</script></body></html>`;
}

// The base page: the dev host the client polls, then the base module.
function page(dir) {
  if (dir.startsWith("leptos/")) return leptosPage(dir);
  return `<!doctype html><html><head><meta charset="utf-8"><title>dev loop</title>
<style>.hidden { display: none; }</style></head><body><script type="module">
const queue = [];
let waiting = null;
window.__applied = 0;
window.__dev = {
  next: () => new Promise((resolve) => { if (queue.length) resolve(queue.shift()); else waiting = resolve; }),
  applied: () => { window.__applied += 1; window.__appliedAt = performance.now(); },
  failed: () => { window.__failed = true; },
};
window.__push = (edit) => { if (waiting) { const take = waiting; waiting = null; take(edit); } else queue.push(edit); };
const started = performance.now();
const { loadUnisonModule } = await import('/${dir}/base.loader.js');
const { exports } = await loadUnisonModule(fetch('/${dir}/base.wasm'));
exports.main(window.__dev);
const ready = () => document.getElementById('card-${lastCard(dir)}') ? (window.__ready = performance.now() - started) : requestAnimationFrame(ready);
ready();
</script></body></html>`;
}

function serve(html) {
  const server = createServer(async (request, response) => {
    const url = new URL(request.url, "http://localhost");
    try {
      if (url.pathname === "/dev.html") {
        response.writeHead(200, { "content-type": "text/html", "cache-control": "no-store" });
        response.end(html);
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

// `<step>=<card>:<text>` arguments.
function parseSteps(args) {
  return args.map((arg) => {
    const [, step, card, text] = arg.match(/^([^=]+)=(\d+):(.*)$/) ?? [];
    if (!step) throw new Error(`a step is <step>=<card>:<text>, not ${arg}`);
    return { step, card: Number(card), text };
  });
}

function summarise(samples) {
  return Object.fromEntries(Object.entries(samples).map(([name, values]) => {
    const sorted = [...values].sort((left, right) => left - right);
    return [name, { median: round(sorted[Math.floor(sorted.length / 2)]), min: round(sorted[0]), max: round(sorted[sorted.length - 1]) }];
  }));
}

async function iteration(browser, base, dir, steps, samples, checks) {
  const record = (name, value) => (samples[name] ??= []).push(value);
  const context = await browser.newContext();
  const tab = await context.newPage();
  tab.on("pageerror", (error) => console.error(`page error: ${error.message}`));
  try {
    await tab.goto(`${base}/dev.html`);
    await tab.waitForFunction(() => window.__ready, null, { timeout: 120000 });
    record("load (ready)", await tab.evaluate(() => window.__ready));
    if (steps.length === 0) return;
    await tab.click(`#card-${KEPT_CARD} .toggle`);
    await tab.waitForFunction((card) => document.querySelector(`#card-${card} .count`)?.textContent === "1"
      && document.querySelector(`#card-${card} .details`) !== null, KEPT_CARD);
    for (const [index, { step, card, text }] of steps.entries()) {
      const timing = await tab.evaluate(async ({ dir, step, card, text, applied }) => {
        const started = performance.now();
        const [delta, ui] = await Promise.all([`delta-${step}.wasm`, `ui-${step}.bin`]
          .map((file) => fetch(`/${dir}/${file}`).then((response) => response.arrayBuffer())));
        const fetched = performance.now();
        const shown = new Promise((done) => {
          const paragraph = () => document.querySelector(`#card-${card} p`);
          const check = () => paragraph()?.textContent === text && (observer.disconnect(), done(performance.now()));
          const observer = new MutationObserver(check);
          observer.observe(document.body, { subtree: true, childList: true, characterData: true });
          check();
        });
        window.__push({ delta, ui });
        const domAt = await shown;
        while (window.__applied < applied && !window.__failed) await new Promise((next) => setTimeout(next, 0));
        return { fetch: fetched - started, applied: window.__appliedAt - fetched, dom: domAt - fetched, failed: Boolean(window.__failed) };
      }, { dir, step, card, text, applied: index + 1 });
      if (timing.failed) throw new Error(`step ${step}: the client could not load the UI`);
      record(`step ${step} fetch`, timing.fetch);
      record(`step ${step} applied`, timing.applied);
      record(`step ${step} dom`, timing.dom);
      const kept = await tab.evaluate((card) => document.querySelector(`#card-${card} .count`)?.textContent === "1"
        && document.querySelector(`#card-${card} .details`) !== null, KEPT_CARD);
      checks[`step ${step} keeps card ${KEPT_CARD} open`] = (checks[`step ${step} keeps card ${KEPT_CARD} open`] ?? true) && kept;
    }
    const nodes = await tab.evaluate(() => document.getElementsByTagName("*").length);
    record("dom nodes", nodes);
  } finally {
    await context.close();
  }
}

async function main() {
  const [dir, iterationArg = "5", ...stepArgs] = process.argv.slice(2);
  if (!dir || (stepArgs.length === 0 && !dir.startsWith("leptos/"))) {
    throw new Error("usage: node bench/frontend-wasm/devloop.mjs <dir> <iterations> <step>=<card>:<text> ...");
  }
  const steps = parseSteps(stepArgs);
  const loadAtStart = loadavg().map(round);
  const server = await serve(page(dir));
  const base = `http://127.0.0.1:${server.address().port}`;
  const browser = await chromium.launch({ executablePath: process.env.CHROMIUM_BIN, headless: true });
  const samples = {};
  const checks = {};
  const version = browser.version();
  try {
    for (let count = 0; count < Number(iterationArg); count += 1) {
      await iteration(browser, base, dir, steps, samples, checks);
    }
  } finally {
    await browser.close();
    server.close();
  }
  const line = { suite: "devloop", dir, iterations: Number(iterationArg), at: new Date().toISOString(),
    load: loadavg().map(round), loadAtStart, cpus: cpus().length, chromium: version, steps, checks, results: summarise(samples) };
  await appendFile(join(here, "results", "devloop.jsonl"), JSON.stringify(line) + "\n");
  console.log(JSON.stringify(line, null, 2));
}

await main();
