// Renders the card app in each build, clicks through a fixed script of toggles,
// and prints a digest of every card's markup after each step, so builds can be
// compared step by step (docs/reports/FrontendWasmLeptosVsProscenium.md, round 5):
//
//   node bench/frontend-wasm/cards-check.mjs <dir> <dir> ...
//
// <dir> is a build under target/frontend-bench/, e.g. warp/cards-400-bare-r5 or
// leptos/cards-400-release.
import { createRequire } from "node:module";
import { createServer } from "node:http";
import { readFile, readdir } from "node:fs/promises";
import { extname, join } from "node:path";
import { createHash } from "node:crypto";
import { fileURLToPath } from "node:url";
import { dirname, resolve } from "node:path";
const here = dirname(fileURLToPath(import.meta.url));
const served = resolve(here, "..", "..", "target", "frontend-bench");
const require = createRequire(import.meta.url);
const { chromium } = require(process.env.PLAYWRIGHT_CORE ?? "playwright-core");
const MIME = { ".js": "text/javascript", ".wasm": "application/wasm" };
const pageFor = async (dir) => {
  const files = await readdir(join(served, dir));
  if (dir.startsWith("leptos")) {
    const js = files.find((f) => f.endsWith(".js")); const wasm = files.find((f) => f.endsWith("_bg.wasm"));
    return `<!doctype html><html><body><script type="module">const mod = await import('/${dir}/${js}'); await mod.default({ module_or_path: '/${dir}/${wasm}' }); window.__ready = true;</script></body></html>`;
  }
  return `<!doctype html><html><body><script type="module">const { loadUnisonModule } = await import('/${dir}/cards-400-bare.loader.min.js'); const { exports } = await loadUnisonModule(fetch('/${dir}/cards-400-bare.opt.wasm')); exports.main(); window.__ready = true;</script></body></html>`;
};
let html = "";
const server = createServer(async (req, res) => {
  const path = new URL(req.url, "http://localhost").pathname;
  if (path === "/") { res.writeHead(200, { "content-type": "text/html" }); res.end(html); return; }
  try { const body = await readFile(join(served, path)); res.writeHead(200, { "content-type": MIME[extname(path)] ?? "application/octet-stream" }); res.end(body); }
  catch { res.writeHead(404); res.end(); }
});
await new Promise((done) => server.listen(0, "127.0.0.1", done));
const browser = await chromium.launch({ executablePath: process.env.CHROMIUM_BIN, headless: true });
const steps = [null, "#card-7 .toggle", "#card-7 .toggle", "#card-399 .toggle", "#card-0 .toggle", "#card-0 .count", "#card-0 .count", "#card-213 .toggle", "#card-213 .count", "#card-399 .toggle"];
const out = {};
for (const dir of process.argv.slice(2)) {
  html = await pageFor(dir);
  const tab = await browser.newPage();
  await tab.goto(`http://127.0.0.1:${server.address().port}/`);
  await tab.waitForFunction(() => window.__ready);
  const lines = [];
  for (const step of steps) {
    const shape = await tab.evaluate(async (step) => {
      if (step) { const el = document.querySelector(step); if (!el) return "missing " + step; el.click(); await new Promise((d) => setTimeout(d, 30)); }
      const walk = (node) => node.nodeType === 3 ? JSON.stringify(node.textContent) : node.nodeType === 1
        ? `<${node.tagName.toLowerCase()}${[...node.attributes].map((a) => ` ${a.name}=${JSON.stringify(a.value)}`).sort().join("")}>${[...node.childNodes].map(walk).join("")}</>` : "";
      const cards = [...document.querySelectorAll("[id^=card-]")];
      return `cards=${cards.length} nodes=${document.getElementsByTagName("*").length} ` + cards.map(walk).join("|");
    }, step);
    lines.push(`${step ?? "mount"}: ${shape.slice(0, 50)} sha=${createHash("sha1").update(shape).digest("hex").slice(0, 12)}`);
  }
  out[dir] = lines;
  await tab.close();
}
await browser.close(); server.close();
const dirs = Object.keys(out);
for (let i = 0; i < steps.length; i++) console.log(dirs.map((d) => out[d][i]).join("  ||  "));
