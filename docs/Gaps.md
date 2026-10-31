# Where Leptos is still ahead

Started 2026-10-31, beside [`REPORT.md`](REPORT.md). The report measures what is faster
and slower; this page keeps the list of places where Leptos still wins in one place, so
that future work can start from it. For each gap it says:

- **how big it is**, and where it was measured;
- **why**, as far as that is known;
- **whether it looks fixable**, or whether it follows from how Unison or warp works;
- **what to do next**.

Each figure is marked **measured**, **estimated** (worked out from measured parts), or
**not measured**. "Proscenium as it is" means Proscenium's API over a tree (round 7 or
the tree prototype); "signals" means the minimal signals core on the same warp
([`Signals.md`](Signals.md)).

## At a glance

| Gap | Size | Status | Looks | Section |
| --- | --- | --- | --- | --- |
| An edit to a widely used definition | 3 times Leptos's dev build at 400 cards | measured | partly structural; each layer fixable | [Hub edits](#an-edit-to-a-widely-used-definition) |
| UCM's start-up for each `run` | 0.9 s at 400 cards, 2.4 s at 1,600, per edit; minutes for a session's first | measured | fixable in UCM | [UCM start-up](#ucms-start-up-for-each-run) |
| Typechecking generated code | 10 GB for 400 cards; 1,600 in one file ran out of memory; time about rustc's | measured | fixable; upstream work under way | [Generated code](#typechecking-generated-code) |
| Browsers | Wasm GC and tail calls needed: Safari 18.2 or later, Chrome 119, Firefox 121 | not measured outside Chromium | structural | [Browsers](#browsers) |
| Building lists, Proscenium as it is | 2–3 times Leptos; 8 times for update every 10th; about 4 times the memory | measured | the library, not warp | [Runtime](#runtime) |
| Swap, and building many elements, with signals | swap 3.5 times; meals page ready 1.4 times, typing 1.7 times | measured | fixable in the library | [Runtime](#runtime) |
| js-framework-benchmark | 1.3–3 times where lists change; 2.8 times the memory at 1,000 rows | measured on round 7 only | probably the library | [Runtime](#runtime) |
| Shipped size, compressed | 1.3 times at 400 cards, 2.5 times at 1,600; about even below 100 | measured on the synthetic app | unknown for a real app | [Size](#shipped-size) |
| Router, server rendering, hydration | Leptos has them; Proscenium's `main` has none | not measured | work, not a limit | [Features](#features-and-tools) |

And one defect found while writing this page, now fixed: round 7's `Text` code made warp's
modules fail to load in a browser without the `wasm:js-string` builtins
([below](#found-on-the-way-the-string-builtin-fallback)).

The [Unison JIT](#will-the-unison-jit-help) does not change any of these much; the
section says why.

## Where Unison and warp are ahead

For balance, the report's results in the other direction:

- **Release builds** are 10 to 25 times faster, and the gap grows with the app.
- **A one-card edit** reaches the running page 2 to 9 times sooner than Leptos's dev
  build, and the page keeps its state ([The dev loop, wired up](REPORT.md#the-dev-loop-wired-up)).
- **Raw wasm** is about half Leptos's size at every app size.
- **The 400-card page** is ready in 89 ms against Leptos's 273, and the 1,600-card app
  mounts with the default stack, where Leptos's overflows it.
- **On the meals page,** editing one meal takes about half Leptos's time, and the FLIP
  animation costs less per frame.
- **In js-framework-benchmark,** selecting a row takes half Leptos's time, first paint is
  a little sooner, and memory when ready is half.

## An edit to a widely used definition

The report's dev loop edits one card, which only that card, its page and the UI depend
on. An edit to something every card uses is the case where Unison's model costs most,
and the report had only an estimate for it. It is now measured.

**The setup.** `bench.hub.s400` is the 400-card app with one change: each card draws its
paragraph through one shared helper, `paragraph`, so 400 cards, 20 pages and the UI
depend on it (`gen-cards.nu`, "the hub variant"). One session alternates three edits to a
card with three edits to the helper, each a `load`, an `update` and a warp delta
(`devloop.nu hub 400`), and the page applies each delta (`devloop.nu hub-page 400`). The
Leptos copy gets the same six edits, with a dev build after each
(`devloop.nu hub-leptos 400`). All on 2026-10-31 at load 3–7. Ranges are over the edits
of each kind, with the first edit left out as in the report; the page timings are
medians of 10 fresh pages.

| Step | Leptos dev, helper edit | Unison, card edit | Unison, helper edit |
| --- | --- | --- | --- |
| typecheck the edit (`load`) | | 2.0–2.3 s | 1.4–1.9 s |
| `update` | | 0.9–1.1 s | **9.8–10.3 s** |
| build | 6.9–8.3 s (compile 4.1–5.2, bindgen 2.7–3.1) | 2.3–2.7 s (warp 0.4 s) | **8.7–11.3 s** (warp 1.8–1.9 s) |
| delta | | 6 terms, 13 KB | 844 terms, 693 KB |
| page | reload 0.9 s, state lost | 1–3 ms, state kept | 49–55 ms, state kept |
| **edit to page** | **7.9–9.2 s** | **5.2–6.0 s** | **20.0–23.0 s** (median 22.7) |

Leptos's helper edit costs what its card edit does (6.9–7.6 s), because rustc
recompiles what changed and the callers refer to the helper by name. Unison's costs four
times its card edit, and about three times Leptos's.

**Why.** A Unison definition is named by the hash of its code, and its code includes the
hashes of what it calls. So an edit to the helper gives every card a new hash, then every
page, then the UI, and each step of the loop does its work again for all of them:

- **`update` typechecks each dependent again:** about 21 ms for each of the 424 (400
  cards, 20 pages, the UI and three entries).
- **The `run` that builds the delta prepares each new definition** before warp starts:
  6.9–9.4 s outside warp, against 1.9–2.3 s for a card edit, so about 16 ms each.
- **warp emits each one again:** 844 terms, 1.8–1.9 s in a fresh process. In the warm
  server it would be about 0.6 s, at the 0.7 ms per term measured there (estimated).
- **The page loads them all:** 693 KB instead of 13, applied in about 50 ms. The page
  keeps its state.

**Estimated at 1,600 cards:** about four times as many dependents, so about 75 s against
Leptos's 36–48 s (its card edit with the reload, from the report). That has not been
run.

**Does it have to be this way?** The hash change itself does: it is what makes Unison's
caching exact. But nothing forces the tools to pay full price for it:

- [ ] **UCM: carry a type-preserving edit to its dependents without typechecking them.**
  If the helper's type is unchanged, no dependent's type can change, so each needs a
  new hash, not a new check. That takes the 9.8 s of `update` to milliseconds.
- [ ] **UCM: keep the prepared code between `run`s**, so that a `run` prepares only what
  is new to the session ([UCM start-up](#ucms-start-up-for-each-run)). The dependents
  are new, so this alone saves little here; it matters for every other edit.
- [ ] **warp: a dev-mode patch by slot.** The base module keeps its terms in a table
  (`CodeCache`). A dev build could put the helper's new code in the old helper's slot
  and leave the dependents alone, which is how hot reloading usually works. The page
  would load one term, not 844, and UCM would need to ship only the helper. Within a session the old hash then runs new code, which
  is acceptable in a dev build and never in a shipped one.
- [ ] **Measure the warm server on a helper edit,** where UCM ships the new code to it
  rather than starting a `run`.
- [ ] **Run the 1,600-card version,** to replace the estimate above.

A real app's shared helpers (a button, a layout, a formatting function) are edited
often, so this is the dev loop's main gap, more than the per-edit start-up.

## UCM's start-up for each `run`

**Measured** ([The dev loop, wired up](REPORT.md#the-dev-loop-wired-up)): a `run` whose
entry reaches the whole UI costs 0.9 s more than one that does almost nothing at 400
cards, and 2.1–2.3 s more at 1,600, even when no code changed. A session's first `run` of
such an entry costs 4–48 s at 400 cards and 205–387 s at 1,600. Leptos has nothing like
it: cargo's first build in a session is an ordinary incremental build.

**Why.** UCM prepares the code an entry reaches for its interpreter on every `run`, and
the first `run` in a session also loads it from the codebase. Its cost grows faster than
the code does at 1,600 cards; why has not been looked into.

**Looks:** fixable in UCM. The work is keyed by hash, so it could be kept between `run`s
and between sessions. The warm build server already avoids warp's half of it by staying
up ([The dev loop, wired up](REPORT.md#the-dev-loop-wired-up)).

- [ ] Profile a first `run` at 1,600 cards, to find what grows faster than the code.
- [ ] Measure the same with UCM's trunk build ([the JIT section](#will-the-unison-jit-help)
  says what else is in it).

## Typechecking generated code

**Measured** ([The Unison side of an edit](REPORT.md#the-unison-side-of-an-edit)):

- **400 cards:** loading the generated file takes 40 s and peaks at 10 GB. rustc builds
  the same crate from scratch in 25 s (dev) to 33 s (release).
- **1,600 cards:** the file in one piece was killed after 4.5 minutes, almost certainly
  for memory. Split into four, each part loaded in 35–41 s, about 150 s in all, against
  rustc's 105 s (dev, at load 19) to 154 s (release).

So the gap is memory, and having to split the file, more than time.

**Looks:** this matters only for generated code and first loads. Code pulled from Share
arrives typechecked, and real edits are small files. UCM's trunk has a fix for the likely
cause: typechecking time and memory that grow faster than an expression is wide
(unisonweb/unison#6312; the fixes are #6322 and #6323, merged on 2026-10-26 and 10-28). The issue's own case, a
chain of 2,000 terms, went from 29.5 s and 3.7 GB to 15.2 s and 397 MB. Each of our pages
is a block of twenty card calls, and the UI a block of twenty pages, which is that
shape.

- [ ] Load the 400- and 1,600-card files with UCM's trunk build.

## Browsers

**Not measured outside Chromium.** Every runtime number in the report is Chromium 149.

**What warp's output needs.** A disassembly of the cards, rows and meals builds finds
Wasm GC (`struct.new`, `ref.cast`), tail calls (`return_call`, `return_call_ref`) and
typed function references (`call_ref`); no exception handling. Safari has had GC and tail
calls since 18.2 (December 2024), Chrome since 119 and Firefox since 121. Leptos's output
uses linear memory and none of these, so it runs in older browsers, including iPhones not
yet on iOS 18.2.

warp's modules also import the `wasm:js-string` builtins, which Chrome has had since 130
and Safari since 26.2. A browser without them takes JS versions from warp's loader
instead, which is what lets stock warp's modules load in Safari 18.2 to 26.1 (by design;
not tried here). Round 7's `Text` code broke that; see
[below](#found-on-the-way-the-string-builtin-fallback).

**Looks:** structural, and shrinking with time: warp is built on Wasm GC.

- [ ] Run `runtime.mjs` under Playwright's Firefox and WebKit. Wasm GC code depends on
  each engine's collector more than linear-memory code does, so the ratios to Leptos may
  differ by browser.

### Found on the way: the string-builtin fallback

warp's loader passes `builtins: ['js-string']` when it compiles a module, and supplies
JS versions of `equals`, `compare` and `concat` for a browser that ignores the option.
Round 7's `Text` code (`perf-r7`) and the code point loops of `offer-3-text` (and so
`perf-r7-142`) import five more: `length`, `charCodeAt`, `codePointAt`, `substring` and
`fromCodePoint`. A browser without the builtins, Safari 18.2 to 26.1 for one, then fails
to instantiate the module.

- **Found by** disassembling a build to list what it needs, and **confirmed** with
  `bench/frontend-wasm/fallback.mjs`. It loads a build in Chromium twice, the second time
  with the `builtins` option withheld from every compile and instantiate call, as an
  older engine ignores it. Stock warp's jfb build drew the same page both times. Round
  7's meals and rows builds failed with `LinkError: ... "wasm:js-string" "codePointAt":
  function import requires a callable`.
- **Fixed** on warp's `offer-3-text`, `perf-r7-142` and `perf-r7` (2026-10-31):
  `internal.javascript.supportJS.buildImportsJS` supplies all eight, with the builtins'
  unsigned indices. warp's tests pass on both offer branches. With the new fallback in
  their loaders, the meals and rows builds draw the same page, the same 987 and 17
  elements, with and without the builtins.
- **Not fixed** in the Proscenium bench branches' own copies of warp
  (`lib.dfreeman_warp_r7f`), which only ever run in Chromium here.

## Runtime

All measured; the report has the runs.

**Proscenium as it is** (the tree prototype, the better of the two; rows suite,
2026-10-30, [the summary's table](REPORT.md#executive-summary)):

| Operation | Leptos | Tree | Times Leptos |
| --- | --- | --- | --- |
| update every 10th row | 0.7 ms | 5.9 ms | 8.4 |
| swap two rows | 0.6 | 1.8 | 3 |
| create 1,000 rows | 26.4 | 69.2 | 2.6 |
| replace 1,000 rows | 26.7 | 74.7 | 2.8 |
| create 10,000 rows | 161.1 | 419.4 | 2.6 |
| JS heap at 10,000 rows | 31.5 MB, linear memory included | 120.5 MB | 3.8 |

**Why:** the model, not warp. A virtual DOM rebuilt from `useState` bodies allocates per
element and per update, and a keyed diff runs over every list. The same warp running a
signals core reaches Leptos's speed on all of these, with less memory than Leptos
([`Signals.md`](Signals.md)). **Looks:** a choice of library.

**With signals,** what is left:

| Operation | Leptos | Signals | Times Leptos | Why |
| --- | --- | --- | --- | --- |
| swap two rows | 0.6 ms | 2.1 ms | 3.5 | the keyed reconcile, the tree's algorithm in Unison |
| meals: page ready | 21.7 | 31.0 | 1.4 | not yet attributed |
| meals: re-plan the week | 1.3 | 2.3 | 1.8 | building many elements |
| meals: type 7 keys in the search | 2.2 | 3.7 | 1.7 | building many elements |
| meals: clear the search | 2.2 | 2.9 | 1.3 | building many elements |

**Looks:** fixable in the library, though neither cause is profiled yet. The swap is the
keyed reconcile, the tree's algorithm. Building many elements is where round 7's
attribution found most of warp's allocations
([Measured attribution](REPORT.md#measured-attribution)).

**In js-framework-benchmark** (round 7 only, [its section](REPORT.md#in-js-framework-benchmark)):
1.3–3 times Leptos's time where lists change, and 2.8 times the memory with 1,000 rows.
The suite repeats each operation before the measured run, so a garbage collection owed
by warp's allocations lands inside it.

- [ ] Run js-framework-benchmark with the signals app.
- [ ] Attribute the meals page's start: compile, instantiate, then the first build.
- [ ] Profile the signals swap against Leptos's keyed diff.

## Shipped size

**Measured** on the synthetic cards ([Code size](REPORT.md#code-size)), brotli, with
each side's JS included:

| App | Leptos | warp | warp's size is |
| --- | --- | --- | --- |
| counter | 36.9 KB | 39.8 KB | 1.08 times |
| rows | 52.2 | 42.9 | 0.82 |
| cards-100 | 66.4 | 66.2 | 1.0 |
| cards-400 | 106.2 | 142.0 | 1.34 |
| cards-1,600 | 183.7 | 449.9 | 2.45 |

**Why:** Leptos's monomorphised output for 1,600 near-identical cards is 5.5 MB raw,
twice warp's, but repeats itself so closely that brotli shrinks it 31 times. warp's is
less repetitive. warp's loader is also 11 KB against Leptos's 5 KB.

**Looks:** unknown for a real app, whose code is mostly logic, not 1,600 copies of one
card. js-framework-benchmark's app, closer to a real one, ships 54 KB against 49.

- [ ] Port one screen of a real app (the meals page is the nearest) and compare its
  compressed size.

## Features and tools

**Not measured.** Leptos ships a router, server rendering with hydration, server
functions, and `Suspense` with async resources. A name search of Proscenium's `main`
finds none of these. For a client-rendered app like the ones compared here, a router is
the one most apps need first. These are work, not limits: Unison runs natively too, so
server rendering of the same views is possible in principle, but nobody has built it.

Debugging is also different: a Leptos dev build carries Rust's names and panic messages,
while warp's debug build keeps term names but no source positions, because Unison's
compiled code carries none.

## Will the Unison JIT help?

**Not for anything the browser runs. Somewhat for warp's own builds. Hardly at all for
the dev loop.** Read from UCM's trunk (`f5f09443c0`, 2026-10-28) and its design notes; not
measured yet.

**What it is.** unisonweb/unison#6317, merged on 2026-10-25, after UCM 1.5.0 and not yet
in a release. When it is turned on (`--jit on`, with LLVM 20 or newer), UCM compiles the
interpreter's code for hot definitions to native code with LLVM, inside the UCM
process. It falls back to the interpreter for anything it cannot compile.

**The browser: no.**
- warp reads Unison's intermediate code at the ANF stage, through `Code.lookup`, and
  writes its own wasm. The JIT starts one stage later, from the interpreter's own code
  (MCode), and its output is native code built around GHC's heap, its collector and
  exits back to the Haskell interpreter. Nothing it produces can reach a wasm module.
- The JIT's changes are in MCode and in the runtime's `Text`. ANF and serialisation, which
  warp reads, are unchanged.
- LLVM can target wasm, but the JIT's code assumes GHC's runtime throughout, so it is not
  a route to better wasm.
- What could carry over is ideas. The main one, compiling handlers that resume once as
  direct calls, is already measured for warp: it would save 2–3% of building a row
  ([Handlers that resume once](REPORT.md#handlers-that-resume-once-detected-and-the-ceiling-measured)).

**warp's builds: some.** warp is a Unison program, so with the JIT on, UCM compiles it.
Of a release build at 400 cards (about 8 s):
- warp's own work is 2.5 s: 0.5–0.7 s loading code through `Code.lookup`, which stays
  interpreted; 1.4–1.5 s emitting; 0.4–0.5 s serialising (`results/builds.jsonl`, the
  round 7 builds' phases).
- wasm-opt (2.7 s) and loading the compiled program (3.5 s) are not Unison code.

So about 1.9 s of 8 is code the JIT could speed up, and about 6 s of 26 at 1,600 cards.
The JIT's own benchmarks give 4–130 times on calls, matches, records and bytes, but
0.3–0.4 times on building large `Map`s, and nothing on `Value` serialisation. warp's
emitter keeps its state in `Map`s of thousands of entries, which is where the JIT's
notes say the interpreter's Haskell maps win again (`UNISON_REPLACEMENTS=on` brings them
back). A guess, then: a release build 1–1.5 s faster at 400 cards and 4–5 s at 1,600,
about a sixth.

**The dev loop: hardly.** In the warm server, warp's share of an edit is 20–41 ms of
3.4–5.4 s. The rest is UCM's own Haskell: typechecking, `update` and preparing a `run`.
The JIT does not compile any of that. On a helper edit warp's share is larger (1.8 s of
the 22), so the JIT could save about a second there.

**What in the same trunk may help more:** the typechecker work for wide expressions
([Generated code](#typechecking-generated-code)).

- [ ] Measure with UCM's `trunk-build` release, which is that commit. Run
  `cards-400-build-r7.uc` and `cards-1600-devserver.uc` with `UNISON_JIT=off` and `on`,
  and `UNISON_LLVM_LIB` set to an LLVM 21 `libLLVM.so`. Compare warp's phases, and check
  that the wasm is the same byte for byte. The binary is downloaded but not run: running
  a downloaded binary needs your approval.
- [ ] If the JIT's `Map` caveat shows, try `UNISON_REPLACEMENTS=on`.
- [ ] Load the generated card files with the same binary ([Generated code](#typechecking-generated-code)).

## How to rerun

```
# helper edits against card edits, Unison then Leptos, then the page
nu bench/frontend-wasm/devloop.nu hub 400
nu bench/frontend-wasm/devloop.nu hub-leptos 400
nu bench/frontend-wasm/devloop.nu hub-page 400

# a build without the string builtins (exit 1 if the page differs)
node bench/frontend-wasm/fallback.mjs warp/meals-bare-sig2/meals-bare
```

The hub runs append to `results/devloop-builds.jsonl` (mode `hub`), `results/builds.jsonl`
(labels `hub-400-*`) and `results/devloop.jsonl`.
