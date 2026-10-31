// Checks that a warp build still runs in a browser without the
// `wasm:js-string` builtins (docs/Gaps.md, "Browsers"): Safari before 26.2,
// for one, has Wasm GC and tail calls but not the builtins.
//
//   node bench/frontend-wasm/fallback.mjs <dir>/<stem> [--loader <file>]
//
// <dir>/<stem> names `<stem>.loader.js` and `<stem>.wasm` under
// target/frontend-bench/. The page is loaded twice in Chromium: as built, and
// with the `builtins` and `importedStringConstants` compile options withheld
// from every WebAssembly compile and instantiate call, as an engine without
// the builtins ignores them. Then each `wasm:js-string` import has to come
// from the fallbacks in the loader's `buildImports`, and a missing one fails
// instantiation. `--loader` serves another file in place of the build's
// loader, to try a changed fallback before warp emits it.
//
// Prints each load's outcome and exits 1 unless both drew the same page.

import { createRequire } from "node:module";
import { createServer } from "node:http";
import { createHash } from "node:crypto";
import { readFile } from "node:fs/promises";
import { extname, join, resolve, dirname } from "node:path";
import { fileURLToPath } from "node:url";

const here = dirname(fileURLToPath(import.meta.url));
const served = join(resolve(here, "..", ".."), "target", "frontend-bench");
const require = createRequire(import.meta.url);
const { chromium } = require(process.env.PLAYWRIGHT_CORE ?? "playwright-core");

const MIME = { ".js": "text/javascript", ".wasm": "application/wasm", ".html": "text/html" };

// Withholds the builtins from the calls the loader makes, keeping every other
// option.
const WITHHOLD = `
for (const [name, at] of [['compile', 1], ['compileStreaming', 1], ['validate', 1], ['instantiate', 2], ['instantiateStreaming', 2]]) {
  const original = WebAssembly[name].bind(WebAssembly);
  WebAssembly[name] = (...args) => {
    if (args[at]) {
      const { builtins, importedStringConstants, ...rest } = args[at];
      args[at] = rest;
    }
    return original(...args);
  };
}`;

function page(build, withhold) {
  return `<!doctype html><html><head><meta charset="utf-8"><title>fallback</title></head><body><script type="module">
${withhold ? WITHHOLD : ""}
try {
  const { loadUnisonModule } = await import('/${build}.loader.js');
  const { exports } = await loadUnisonModule(fetch('/${build}.wasm'));
  exports.main();
  window.__outcome = 'ran';
} catch (error) {
  window.__outcome = String(error);
}
</script></body></html>`;
}

function serve(build, loader) {
  const server = createServer(async (request, response) => {
    const url = new URL(request.url, "http://localhost");
    try {
      if (url.pathname === "/as-built.html" || url.pathname === "/withheld.html") {
        response.writeHead(200, { "content-type": "text/html", "cache-control": "no-store" });
        response.end(page(build, url.pathname === "/withheld.html"));
      } else {
        const file = loader && url.pathname === `/${build}.loader.js` ? loader : join(served, url.pathname);
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

async function load(browser, base, which) {
  const context = await browser.newContext();
  const tab = await context.newPage();
  const errors = [];
  tab.on("pageerror", (error) => errors.push(error.message));
  try {
    await tab.goto(`${base}/${which}.html`);
    await tab.waitForFunction(() => window.__outcome, null, { timeout: 60000 });
    await tab.waitForTimeout(500);
    const outcome = await tab.evaluate(() => window.__outcome);
    const drawn = await tab.evaluate(() => document.body.innerText);
    const nodes = await tab.evaluate(() => document.getElementsByTagName("*").length);
    return { which, outcome, errors, nodes, drawn: createHash("sha256").update(drawn).digest("hex").slice(0, 16) };
  } finally {
    await context.close();
  }
}

async function main() {
  const [build, flag, loaderArg] = process.argv.slice(2);
  if (!build || (flag && flag !== "--loader")) {
    throw new Error("usage: node bench/frontend-wasm/fallback.mjs <dir>/<stem> [--loader <file>]");
  }
  const loader = loaderArg ? resolve(loaderArg) : null;
  const server = await serve(build, loader);
  const base = `http://127.0.0.1:${server.address().port}`;
  const browser = await chromium.launch({ executablePath: process.env.CHROMIUM_BIN, headless: true });
  try {
    const results = [await load(browser, base, "as-built"), await load(browser, base, "withheld")];
    console.log(JSON.stringify({ build, loader, results }, null, 2));
    const [built, withheld] = results;
    const same = built.outcome === "ran" && withheld.outcome === "ran" && built.drawn === withheld.drawn && built.nodes === withheld.nodes;
    console.log(same ? "fallback: the page is the same without the builtins" : "fallback: the page differs without the builtins");
    process.exitCode = same ? 0 : 1;
  } finally {
    await browser.close();
    server.close();
  }
}

await main();
