// Checks that two builds of the meals page show the same week, grocery list
// and search after the same steps:
// `node bench/frontend-wasm/meals-check.mjs <dirA> <dirB> [steps] [seed]`, with
// each dir a build under target/frontend-bench/ (e.g. leptos/meals-release and
// warp/meals-bare-r5i). Both draw their recipes and weeks from the same seeded
// generator, so after every step the snapshots must match exactly. The steps
// are drawn at random: shuffle, serve, remove, re-plan, check, uncheck, move a
// day, type a query, wave. Which trays and macros panels are open is left out:
// the Leptos page rebuilds its day cards on every edit and closes them, as the
// app it imitates does, while Proscenium keeps a card's own state.

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

function generator(seed) {
  let state = seed >>> 0;
  return (bound) => { state = (Math.imul(state, 1664525) + 1013904223) >>> 0; return state % bound; };
}

const SNAPSHOT = `JSON.stringify({
  week: document.querySelector('#week-total')?.textContent ?? null,
  days: [...document.querySelectorAll('#week .day')].map((day) => [day.id, day.querySelector('.day-name').textContent,
    day.querySelector('.day-totals').textContent, ...[...day.querySelectorAll('.slot')].map((slot) =>
      [slot.dataset.slot, ...['.slot-type', '.slot-name', '.slot-kcal', '.slot-protein', '.servings'].map((part) => slot.querySelector(part).textContent)].join('|'))]),
  grocery: [...document.querySelectorAll('#grocery section')].map((section) => section.querySelector('h4').textContent + ': ' +
    [...section.querySelectorAll('.item')].map((item) => item.querySelector('.name').textContent + ' ' + item.querySelector('.qty').textContent).join(', ')),
  note: document.querySelector('#search-note').textContent,
  results: [...document.querySelectorAll('#results li .name')].map((name) => name.textContent).join(','),
  pose: document.querySelector('#mascot').getAttribute('data-pose'),
})`;

const QUERIES = ["", "c", "chicken", "soup", "roasted", "egg", "tofu bowl", "smoky", "s", "zzz"];

// One step, as [label, in-page code]; targets are picked by position in what
// page A shows, which page B must show too.
function step(draw, slots, items, checked) {
  const kind = draw(9);
  const slot = slots.length ? slots[draw(slots.length)] : null;
  switch (kind) {
    case 0: return slot && [`shuffle ${slot}`, `document.querySelector('[data-slot="${slot}"] .shuffle').click()`];
    case 1: return slot && [`serve ${slot}`, `document.querySelector('[data-slot="${slot}"] .serv-plus').click()`];
    case 2: return slot && [`remove ${slot}`, `document.querySelector('[data-slot="${slot}"] .remove').click()`];
    case 3: return ["replan", `document.querySelector('#replan').click()`];
    case 4: return items.length ? (() => { const name = items[draw(items.length)]; return [`check ${name}`, `document.querySelector('#grocery .aisle .item[data-name="${name}"] .check').click()`]; })() : null;
    case 5: return checked.length ? (() => { const name = checked[draw(checked.length)]; return [`uncheck ${name}`, `document.querySelector('#checked .item[data-name="${name}"] .check').click()`]; })() : null;
    case 6: return ["move", `document.querySelector('#move').click()`];
    case 7: { const query = QUERIES[draw(QUERIES.length)];
      return [`type "${query}"`, `{ const box = document.querySelector('#search-input'); box.value = ${JSON.stringify(query)}; box.dispatchEvent(new Event('input', { bubbles: true })); }`]; }
    default: return ["wave", `document.querySelector('#pose').click()`];
  }
}

async function main() {
  const [dirA, dirB, stepsArg = "80", seedArg = "7"] = process.argv.slice(2);
  const pages = new Map([["/a", await startScript(dirA)], ["/b", await startScript(dirB)]]);
  const server = createServer(async (request, response) => {
    const path = new URL(request.url, "http://localhost").pathname;
    if (pages.has(path)) {
      response.writeHead(200, { "content-type": "text/html" });
      response.end(`<!doctype html><html><head><style>.hidden { display: none; }</style></head><body><script type="module">${pages.get(path)} window.__ready = true;</script></body></html>`);
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
  const open = async (path) => {
    const tab = await browser.newPage();
    const errors = [];
    tab.on("pageerror", (error) => errors.push(String(error)));
    await tab.goto(base + path);
    await tab.waitForFunction(() => window.__ready && document.querySelector('#search-note'), null, { timeout: 60000 });
    return { tab, errors };
  };
  const [pageA, pageB] = [await open("/a"), await open("/b")];
  // Two frames: Proscenium renders in a microtask, a FLIP spring takes 31.
  const settle = (tab) => tab.evaluate(() => new Promise((done) => requestAnimationFrame(() => requestAnimationFrame(() => setTimeout(done, 0)))));
  const draw = generator(Number(seedArg));
  let compared = 0;
  try {
    const plan = `document.querySelector('#plan').click()`;
    const steps = [["plan", plan]];
    for (let index = 0; index < Number(stepsArg); index += 1) {
      const [label, code] = steps.length > index ? steps[index] : [null, null];
      const chosen = label ? [label, code] : await (async () => {
        const state = await pageA.tab.evaluate(() => ({
          slots: [...document.querySelectorAll('#week .slot')].map((slot) => slot.dataset.slot),
          items: [...document.querySelectorAll('#grocery .aisle .item')].map((item) => item.dataset.name),
          checked: [...document.querySelectorAll('#checked .item')].map((item) => item.dataset.name),
        }));
        let picked = null;
        while (!picked) picked = step(draw, state.slots, state.items, state.checked);
        return picked;
      })();
      for (const page of [pageA, pageB]) { await page.tab.evaluate(chosen[1]); await settle(page.tab); }
      const [snapA, snapB] = await Promise.all([pageA.tab.evaluate(SNAPSHOT), pageB.tab.evaluate(SNAPSHOT)]);
      if (snapA !== snapB) {
        console.error(`step ${index} (${chosen[0]}): the pages differ`);
        console.error("A:", snapA);
        console.error("B:", snapB);
        process.exitCode = 1;
        break;
      }
      compared += 1;
      console.log(`step ${index}: ${chosen[0]} ok`);
    }
    const errors = [...pageA.errors, ...pageB.errors];
    if (errors.length) { console.error("page errors:", errors); process.exitCode = 1; }
  } finally {
    await browser.close();
    server.close();
  }
  console.log(`${compared} steps compared: ${process.exitCode ? "MISMATCH" : "identical"}`);
}

main().catch((error) => { console.error(error); process.exit(1); });
