# Frontend wasm: Leptos vs Proscenium and warp

A living report, started 2026-10-28. The question: if a Rust and Leptos web app's front
end were written in Unison with [`@dfreeman/proscenium`](https://share.unison-lang.org/@dfreeman/proscenium)
(the UI library) and [`@dfreeman/warp`](https://share.unison-lang.org/@dfreeman/warp)
(Unison to WebAssembly), how much build time would we save, how big would the shipped
code be, and how fast would it run? Every number below was measured on one machine (see "What was compared"). The
benchmark is under `bench/frontend-wasm/`, and "How to rerun" at the end says how to
repeat it.

## Executive summary

- **Release builds: 10 to 25 times faster, and the gap grows with size.** Each case below
  is a one-line edit to the scaling app (N stateful cards):

  | Cards | Leptos | warp | warp's time is |
  | --- | --- | --- | --- |
  | 400 | **83 s** (33 s rustc with fat LTO, 50 s wasm-opt) | about **8 s** | 2.4 s codegen, 2.7 s wasm-opt, 3.5 s start-up |
  | 1,600 | **634 s** (154 s rustc, 479 s wasm-opt) | about **26 s** | 7.7 s codegen, 14.5 s wasm-opt, 3.5 s start-up |

  Leptos's release cost grows faster than its code does; warp's codegen grows about in
  line with it.
- **The edit loop is a wash at 400 cards, and 3 to 7 times faster at 1,600.**
  - **Leptos dev builds:** 6.8 s at 400 cards, 40 s at 1,600 (30 s rustc and 10 s of
    wasm-bindgen over a 200 MB module).
  - **Unison:** a one-card edit takes 1.2–1.5 s to typecheck and 0.3–1.2 s to `update`,
    and that hardly changes with app size. A full rebuild then takes 5 s at 400 cards in a
    warm UCM session, and an estimated 10 s at 1,600; warp's own share of that is 2.4 s and
    7.7 s.
- **warp can cache codegen the way UCM caches typechecking, and that path is not wired
  up yet.** `warp.incremental` emits only the terms the previous build lacked, by hash.
  A one-card edit is a **20–39 ms** delta of 13–25 KB, at any app size. Using it in a dev
  loop needs three pieces of glue: keep the build record between runs, build a
  `CodeCache` base module, and have the page load deltas. With those, the loop would be
  about 1.5 s of typechecking plus UCM's 2.5 s per `run`. One catch: `update` re-checks
  every dependent of what changed. A leaf edit costs a second, but an edit to a widely
  used definition costs about 60–100 ms for each definition that depends on it.
- **The shipped code is comparable in size.** After wasm-opt, warp's wasm is about half
  the size of Leptos's at every app size: 2.5 MB against 5.5 MB at 1,600 cards. Rust's
  monomorphised output compresses unusually well, though: brotli shrinks it to 178 KB,
  against warp's 439 KB, plus warp's 11 KB loader. The synthetic cards are very
  repetitive, which flatters that. For the smallest app the floors are close: 37 KB
  brotli for Leptos and 40 KB for warp, with JS included.
- **Runtime was the real drawback. Five rounds of library and runtime work have brought
  it from 50–300 times Leptos to 1.4–7 times.** The latest run (2026-10-29, medians of
  10, load 2.4–2.9, timed until the DOM shows the result):

  | Operation (ms) | Leptos | Stock | Round 2 | Round 4 | **Round 5** | Round 5 vs Leptos |
  | --- | --- | --- | --- | --- | --- | --- |
  | select a row | 0.55 | 186 | 3.4 | 0.6 | **1.0** | 0.5–1.2 ms on both across runs |
  | update every 10th row | 0.9 | 245 | 16.1 | 6.5 | **6.5** | 7 times |
  | swap two rows | 0.6 | 5,999 | 19.6 | 6.1 | **4.1** | 7 times |
  | remove a row | 0.9 | 242 | 19.0 | 6.4 | **5.0** | 5.5 times |
  | create 1,000 rows | 26.7 | 1,717 | 343.9 | 105.9 | **90.0** | 3.4 times |
  | replace 1,000 rows | 26.8 | 14,037 | 309.9 | 112.4 | **90.3** | 3.4 times |
  | append 1,000 rows | 19.8 | 2,212 | 289.1 | 77.8 | **53.9** | 2.7 times |
  | clear 2,000 rows | 13.1 | 174 | 51.2 | 59.7 | **21.3** | 1.6 times |
  | create 10,000 rows | 165.2 | 20,862 | 2,861.6 | 852.1 | **631.2** | 3.8 times |
  | clear 10,000 rows | 81.5 | 879 | 256.7 | 160.4 | **114.6** | 1.4 times |
  | JS heap at 10,000 rows (MB) | 9.6, plus 21.8 linear memory | 184 | 214 | 157 | **138.5** | 4.4 times |

  The stock column is round 2's run and the round 2 column an earlier run of the same
  day, both kept for scale. All but the stock column use the corrected harness (see "How
  the harness times" under Runtime).
  - **Interactions take 1–6.5 ms.** That is within a frame, and the next frame lands when
    Leptos's does: 18.2 against 18.5 ms for a swap, and 19.5 against 19.4 for a remove.
    The work itself is still 5.5–7 times Leptos's.
  - **Building lists is 2.7–3.8 times Leptos's work, but 1.4–2 times on screen.** Layout
    and paint cost both the same: about 40 ms for 1,000 rows and 400 ms for 10,000. To the
    first frame that shows them, 1,000 rows take 127 ms against 64, and 10,000 take
    1,015 against 577.
  - **400 cards:** the page is ready in 89 ms against Leptos's 273. A toggle takes
    0.3–1.5 ms against 0.2–0.8.
- **Round 1: costs that were not inherent** (no change to how an app is written).
  - **ink's keyed-children diff.** It was quadratic, relocated every row after the
    first change, and **put rows in the wrong order** after a move combined with an
    insertion: stock Proscenium's table diverged from the model. An `O(n log n)`
    longest-increasing-run rewrite fixes both.
  - **warp's `Universal.compare` and `==`.** They now run in wasm, and list elements are
    compared through wasm too. All 92 of warp's tests pass.
  - **Proscenium's key hints.** They were lists, which warp keeps in JS, so every key
    comparison crossed into JS. They are now plain data, and select and swap each got
    about twice as fast again.
- **Round 2: the architecture.** Under stock ink, a state change anywhere re-ran the UI
  function from the root.
  - ink now has `compute_`, a sub-computation whose result its parent never reads. A
    message for a cell inside one re-runs only the computation that owns the cell, and
    Proscenium builds every element with it. ink gained two tests and keeps all its old
    ones.
  - Proscenium gained `elementWith` (an element whose modifiers its own body computes)
    and two stores, `Keyed` and `Selector`, which tell only the subscribers whose value
    changed: Leptos's per-row signals and `Selector`.
  - The rows app rewritten that way is the "fine-grained" column. It matches Leptos's
    table through 140 random operations on two seeds.
- **Round 3: skip the diff on first mount** (ink, from another agent). A new
  computation no longer reconciles its children against an empty previous list. List
  creation got 16–21% faster.
- **Round 4: lists in wasm, and fast paths throughout** (warp, ink and Proscenium, from
  another agent):
  - **warp:** `List` is now a balanced tree of 32-element arrays in wasm instead of a
    JS finger tree, so list operations no longer cross into JS. JS property access and
    method calls also have direct typed entry points.
  - **ink:** fast paths for a common prefix and suffix, swaps, appends and clears.
  - **Proscenium:**
    - `createElement` for HTML elements
    - new nodes attached without document fragments
    - one shared empty listener map
    - key hints that compare outermost-first
    - store entries dropped with their last subscriber

  Together these cut create-1,000 from 277 to 102 ms and swap from 21 to 6 ms.
- **Round 5: a review of rounds 3 and 4, and DOM sync.**
  - **One bug found.** Round 4's new ink test sat under a doc comment, so UCM read it as
    a definition of an operator `>`. ink gained a junk top-level `(>)`, and so did
    Proscenium's copy of the library, which leaves it in scope for name resolution
    there. The test itself never ran. Both are fixed, and the test passes; ink now has
    45 passing tests.
  - **No regressions elsewhere.**
    - A new differential test runs 9,000 random operations of 29 kinds on lists, natively
      and in wasm, and compares the results line by line. The new wasm `List` agrees
      with UCM.
    - The rows table matches Leptos through 200 more random operations.
    - The 400-card page matches round 2's after every step of a toggle script.
  - **The harness was unfair on large operations.**
    - Proscenium renders in a microtask, and the harness waited in tasks, so the
      browser's layout and paint landed inside some operations' times. That hit warp's
      list operations and Leptos's 10,000 rows.
    - Round 4's "faster than Leptos" frame times were the phase of the display's frame
      clock, not speed.
    - The harness now waits in microtasks first. Every column above was measured with
      the fix.
  - **DOM sync builds new subtrees bottom-up.** ink resolves a new node after all of
    its children, so Proscenium can attach each pending child as soon as its parent
    exists. A whole row then joins the index of live nodes in one step, where it used
    to take a walk from the root for every node. Removals under one parent also share a
    walk, and clearing an element clears it in one step.
    - Sync time for create-1,000 fell from 69 to 44 ms, and for create-10,000 from 753
      to 390 ms.
    - Clear-10,000 fell from 92 to 51 ms.
  - **ink finds previous children by position.** A re-run used to build a map of all of
    its previous children. Now it tries the child where the last one left off, scans on
    a miss, and indexes only after scanning three times the list. In a 15-run comparison,
    swap went from 5.7 to 4.3 ms and remove from 5.4 to 4.7; clearing went from 33 to
    23 ms at 2,000 rows and from 127 to 112 at 10,000. ink has a test for it and 46
    passing tests.
  - **Against round 4:** swap is a third faster, append 31%, create-10,000 26%,
    clear-2,000 64% and clear-10,000 29%; the heap is 12% smaller.
  - **What is left is mostly warp's runtime.** The same DOM work for 1,000 rows takes
    7.3 ms in plain JS, or 3.6 ms cloning a template as Leptos does. A CPU profile of
    creating 1,000 rows puts the rest of the work in four places:
    - garbage collection: about 20 ms
    - `callDirect` and `apply*`: 15–20 ms. `callDirect` is how JS calls into Unison, and
      `apply*` applies a closure whose code is not known statically. Ordinary calls to
      a known function that needs no abilities are already direct (corrected
      2026-10-30, after the author's review).
    - crossings between wasm and JS: about 10 ms
    - the DOM calls themselves: about 8 ms

    No library function is more than a few milliseconds. Batching DOM calls could save
    at most the crossings. "Measured attribution" below says what the allocation and the
    calls actually are.
- **On a page modelled on a real app, the gap mostly closes.** The new meals page
  imitates a production app's Meals page: a week of day cards, a grocery list, a recipe
  search, a FLIP animation and an SVG mascot.
  - Editing one meal is as fast as Leptos or faster (1.1–1.5 ms against 1.5–2.1). The
    Leptos page, written as the real app writes it, rebuilds the whole week on every
    edit, while ink re-renders only the day that changed.
  - The FLIP animation costs the same per frame in Unison as in Rust.
  - The mascot is animated by CSS alone, so it costs neither framework anything per frame.
  - Creating many elements is still 2–4.5 times Leptos: mounting the page, re-planning
    the week, bringing back 240 search results.
  - Every operation lands in the same frame as Leptos's, except planning the week, which
    lands about 10 ms later.
  - The shipped code is 62 KB brotli against 86 KB. A release build after an edit is
    about the same at this size (5.8 s against 6.4 s).
- **What the remaining cost is made of (2026-10-30, after the author's review).**
  Counting at the boundary and inside the module, creating 1,000 rows:
  - **Crossings:** about as many calls into JS as Leptos makes (36,000 against 32,000),
    but 161,000 calls back from warp's JS glue into wasm, where Leptos has 1,000.
  - **Allocations:** 4,572 a row: argument arrays 38%, data 17%, boxed numbers 10%,
    continuations 8%.
  - **Unboxing:** wasm-opt removes 39% of the number boxes but only 8% of all
    allocations.
  - **Ability operations:** 41 a row, each capturing a continuation, which warp does not
    special-case.

  The fixes, in order: unwrap arguments in wasm instead of in the glue; allocate less in
  generic and partial application; compile handlers that resume once, at the end, as
  direct calls; finish `==` and `compare` in wasm. See "Measured attribution".
- **Round 7 did the first and the last.**
  - **Boundary:** warp's JS interop takes its arguments unboxed, `==` compares functions
    in wasm, and comparisons share their result boxes. warp now crosses the boundary as
    often as Leptos: 32,046 times to create 1,000 rows, against 33,007, down from
    197,231.
  - **Speed:** lists build 5–23% faster (create 1,000 91.5 to 86.5 ms, append 59.1 to
    45.8, create 10,000 697 to 608), and interactions are unchanged.
  - **What is left:** allocation and ability operations. The next step is a tree of
    Proscenium's own (`docs/ProsceniumTree.md`), the author's preferred direction,
    which removes one of the two ability operations per element.
  - **On the meals page,** a meal edit now takes about half Leptos's time (shuffle 0.9
    against 2.3 ms). Part of that came from moving the search's filter behind a skip
    boundary: in Proscenium a `region` is a key, not a memo, and only elements are
    skipped.
  - **In js-framework-benchmark** (local run, against Leptos 0.7.0's entry), round 7 is:
    - 1.3–2.3 times Leptos on list operations;
    - faster on select and first paint;
    - lighter when ready;
    - 2.8 times the memory with 1,000 rows;
    - about the same size.
- **Without ink, the floor is close to Leptos** ("A floor for a tree without ink"). A
  keyed virtual DOM in plain Unison, about 200 lines with no ink and no Proscenium, runs
  the rows app on warp r7f:
  - **Creating 1,000 rows:** 94 ms against round 7's 150 and Leptos's 76, with 1,041
    allocations a row instead of 4,198.
  - **Creating 10,000 rows:** 756 against 1,177 and 812.
  - **Memory at 10,000 rows:** 44 MB against 152.
  - **Interactions:** within a few ms of both.
  - **With an ability:** written through an `Html` ability with one handler, one
    operation per element, it costs 13% more to create 1,000 rows and 24% more for
    10,000. Proscenium has two handlers today.
  - **Size:** the module is 18 KB brotli. warp builds it in 0.24 s.
- **Stock warp miscounts `Text`** ("Text by code point"). A differential fuzz of 1,800
  text operations fails on 1.4.2 within 24 operations. warp counts and orders `Text` in
  UTF-16 units, so an emoji is two characters and a text `match` can miss its arm.
  `offer-3-text` fixes it, standalone on 1.4.2, and so does `perf-r7-142`.
- **One-shot continuations are enough for Proscenium and ink** ("One-shot continuations").
  With every captured continuation made one-shot, the three apps pass every check and
  suite. Only base's `Each` resumes twice. That answers the cost the author named for
  dropping CPS in favour of stack switching.
- **A Leptos limit we may hit:** the 1,600-card benchmark app puts 80 page components in
  one `view!`, and mounting it overflowed wasm's default 1 MB stack. This happened in both
  dev and release builds, as `memory access out of bounds`, and an 8 MB stack fixed it.
  Leptos's nested static view types need a deep stack to mount a large view. An app
  that is far from this limit gets no warning as it approaches it.
- **Recommendation:**
  - The build-time win is real, and it grows with app size.
  - Interactive screens no longer feel different from Leptos. An interaction takes
    1–6.5 ms, and its frame lands when Leptos's does. A form, a settings screen or a list
    of tens to hundreds of items would make a fair trial now.
  - Long lists still cost more: about twice as long to the frame for 1,000 rows, and
    4.4 times the memory at 10,000. A screen that builds thousands of rows at once
    should wait for the warp work under "Next experiments".
  - Upstream the fixes first. The ink ordering bug affects every Proscenium user, and
    the other changes are general.

## What was compared

Four apps, written the same way in both stacks. The Rust copies are in
`bench/frontend-wasm/leptos/` and the Unison copies are on `@dfreeman/proscenium/bench`
(`bench.*`).

- **counter**: one button and a count, to measure the fixed cost of each framework.
- **rows**: a cut of the [js-framework-benchmark](https://github.com/krausest/js-framework-benchmark)
  table (create, append, update every 10th, swap, select, remove, clear), plus "rotate
  and insert", which moves the last row to the front and adds a new row after it. The
  Leptos copy is Leptos's own `examples/js-framework-benchmark`, with `view!` in place of
  `template!`, since `view!` is what apps write. Both copies draw their labels from the same
  seeded generator, so their tables can be compared row for row.
- **meals**: a meal planner's page, modelled on a production Leptos app's Meals page
  and written as each framework is normally written: a week of day cards with totals,
  a grocery list, a recipe search, a FLIP animation and a CSS-animated SVG mascot. See
  "Round 5 again, with a page taken from a real app". It is on
  `@dfreeman/proscenium/perf-r5m`, not on `bench`.
- **cards-N**: N small stateful cards, each with a heading, a paragraph, a toggle
  that shows a detail line, and a click count, twenty to a page. They are generated by
  `bench/frontend-wasm/gen-cards.nu` in both languages. This is the scaling test. The app
  has 2,809 `view!` blocks (124 `#[component]`s); 1,600 cards come to 1,680 (one per card
  and one per page).

The Leptos copies build the way a shipped Leptos app typically does: Leptos 0.8 patched to
the public [AlygnHealth/leptos](https://github.com/AlygnHealth/leptos) fork at the pinned
revision in `bench/frontend-wasm/leptos/Cargo.toml` (plain 0.8.22 from crates.io gave the same
timings within noise when rechecked), fat LTO with one codegen unit, wasm-bindgen 0.2.129, and wasm-pack's
wasm-opt 117 at `-O`. The warp copies use warp 1.3.0, as installed by Proscenium 0.4.3,
built with no reflection and no debug names. They then go through wasm-opt 133 with
warp's own production flags (`--closed-world -O3 --gufa --converge`) and esbuild
`--minify`, which is what warp's `prodDefaults` runs.

Machine: AMD Ryzen 9 7900X3D (24 threads), 125 GB, shared with other sessions; one ran
a deployable app build during the later runtime measurements. Every result is stored
with the load average at the time (`bench/frontend-wasm/results/`). Chromium 149,
headless.

## Build time

### A one-line edit, by app size

Each row is an edit of one card's paragraph, rebuilt with every dependency warm.

| Cards | Leptos dev (compile + bindgen) | Leptos release (compile + wasm-opt) | warp codegen (in process) | warp + wasm-opt + esbuild | warp delta (`incremental`) |
| --- | --- | --- | --- | --- | --- |
| 25 | 0.9 s | 4.8 s (2.3 + 2.4) | 0.43 s | 0.85 s | 17 ms, 10 KB |
| 100 | 2.0 s | 19.4 s (7.9 + 11.4) | 0.88 s | 1.6 s | 18 ms, 11 KB |
| 400 | 6.8 s | 83 s (32.8 + 50.2) | 2.4 s | 5.1 s | 20 ms, 14 KB |
| 1,600 | 40.3 s (30.2 + 10.1) | 634 s (153.9 + 479.2) | 7.7 s | 22.2 s | 39 ms, 25 KB |

From 400 to 1,600 cards (4 times the code):

| Step | Growth |
| --- | --- |
| Leptos rustc in release | 4.7 times |
| Leptos wasm-opt | 9.5 times |
| Leptos dev build | 5.9 times |
| warp codegen | 3.2 times, at 0.72 ms per emitted term |
| warp's wasm-opt | 5.4 times |

The warp columns do not include starting the program. A fresh `ucm run.compiled` of a
build entry spends about 3.5 s loading the 40 MB compiled `.uc` before warp starts.
Inside a UCM session, the first `run` of a build entry costs **31 s** (UCM loads warp
itself), and later runs carry about 2.5 s of overhead on top of warp's own time.

### The Unison side of an edit

Measured in one UCM session (`target/unison/frontend-bench/edit-loop.md`):

| Step | 400 cards | 1,600 cards |
| --- | --- | --- |
| First `run` of the warp build entry in a fresh session | 30.7 s | not measured |
| A warm `run` of the build entry | 5.0 s (warp: 2.1–2.4 s) | about 10 s, estimated (warp's 7.7 s plus the 2.5 s overhead) |
| `load` of the one edited card (typecheck) | 1.2–1.5 s | 1.5 s |
| `update` (card → page → UI → the build entries) | 0.26–0.85 s | 1.2 s |

Typechecking a whole generated file is a different matter. It is slow, though it is a
one-off cost:

- 25 cards took 8.5 s (most of it the session's first `load`), 100 took 7.6 s and 400
  took 39.9 s.
- At 1,600 cards, the single 23,000-line file was **killed after 4.5 minutes**, almost
  certainly for lack of memory: the 400-card file had already peaked at 10 GB. Split
  into four 400-card files, it loaded in 35–41 s each, with an 11.6 GB peak.
- Real code arrives in small scratch files, so this matters only for generated code.
- Writing every name fully qualified saved only about 24%, so type-directed name
  resolution is not the main cost.

The caveat at the scale of a real app is that `update` re-typechecks every transitive
dependent of what changed. An edit to a leaf costs a second. An edit to a definition that
a thousand others use would cost one to two minutes; that is an estimate, at 60–100 ms
per definition.

### Cold builds

A cold release build of the Leptos counter, with no sccache, took 49 s for 170 crates. On
Unison's side, the equivalent is pulling the libraries once. After that, nothing about
the dependencies is ever rebuilt, because they are compiled by hash.

### Does warp cache the way the typechecker does?

Partly, and it could go further.

- **Typechecking** is cached per definition. Only edited definitions, plus their
  dependents during `update`, are checked again.
- **A full warp build** caches nothing between runs. It re-emits every reachable term,
  at about 0.7 ms each: 2,815 terms take 2.4 s at 400 cards, and 10,135 take 7.7 s at
  1,600. A second full build in the same process is no faster.
- **`warp.incremental`** does what was hoped. Given the previous build's
  `BuildOutput`, it emits only the terms whose hashes the previous build did not have,
  and imports the rest from the base module. A one-card edit is 7 terms and 20–39 ms,
  whatever the app's size. Three things stand between that and a working edit loop:
  1. The previous `EmitRecord` has to be kept between `run`s, which is a serialised
     value written to disk.
  2. The base module has to be built with `ReflectionSupport.CodeCache`, so it exports
     its terms to link against. That rules out wasm-opt's closed-world mode, but only
     for dev builds.
  3. The page has to load each delta with warp's `loadCompiledTerms` and render the UI
     again.

  That is a few days' glue in a dev server rather than a research problem. Shipping
  builds stay full builds, because closed-world optimisation needs one module.
- **The remaining fixed cost is UCM's.** About 2.5 s goes to preparing each `run`, and
  31 s to the first `run` in a session. A dev server that kept warp loaded and saw
  codebase changes would need help from UCM. A warm runtime across runs would be the
  feature request.

## Code size

After optimisation (Leptos: wasm-opt `-O`; warp: wasm-opt `-O3 --closed-world --gufa
--converge`, esbuild for the loader). Sizes are raw / gzip -9 / brotli -q 11, in bytes.
The Leptos JS is about 30 KB raw (5.3 KB brotli) for every app, and warp's loader is
51 KB raw (11.1 KB brotli).

| App | Leptos wasm | warp wasm |
| --- | --- | --- |
| counter | 98,759 / 38,220 / 31,585 | 90,305 / 34,599 / 28,729 |
| rows | 152,062 / 57,867 / 46,936 | 99,164 / 38,554 / 31,755 |
| cards-25 | 205,168 / 69,066 / 52,569 | 128,745 / 44,901 / 36,051 |
| cards-100 | 453,608 / 88,693 / 61,148 | 241,445 / 69,641 / 55,125 |
| cards-400 | 1,454,845 / 182,807 / 100,888 | 693,914 / 174,167 / 130,917 |
| cards-1,600 | 5,462,310 / 615,827 / 178,420 | 2,533,503 / 581,462 / 438,793 |

- **Per card**, Leptos adds about 3.3 KB raw but only 0.07–0.13 KB brotli. Warp adds
  about 1.5 KB raw and 0.25 KB brotli. Each `view!` is a concrete type with its own
  build, rebuild and drop code. That compiles to near-identical bytes, which brotli folds
  away, and the synthetic cards make it even more repetitive. Warp's continuation-passing
  code is smaller, but less repetitive. Gzip, which looks only 32 KB back, comes out
  about even: 616 KB against 581 KB at 1,600 cards.
- **Raw size still matters** for the browser's wasm compile and memory, and warp is about
  half of Leptos there.
- **Unoptimised builds differ widely.** A Leptos dev build is 59 MB at 400 cards and
  200 MB at 1,600, which is why a dev build is only practical on localhost and why
  wasm-bindgen alone takes 10 s at 1,600. Warp's unoptimised output is 970 KB and
  3.5 MB at those sizes.
- **A real app:** a shipped Leptos app's module can be several MB, mostly application
  logic rather than views, and nothing here predicts its size in Unison closely. The
  per-term figure (about 250 bytes optimised per emitted term) is the starting point for
  an estimate.

## Runtime

`bench/frontend-wasm/runtime.mjs` runs each operation in a fresh headless Chromium
context, in milliseconds, with two timings:

- **To the DOM:** from the click until the DOM shows the end state.
- **To the frame:** until the frame after that has been produced, which adds layout,
  paint and the wait for the display's next frame.

### How the harness times

Leptos updates the DOM inside the click, and Proscenium in a microtask queued by it.
Until round 5, the harness checked the end state between tasks. A task boundary lets the
browser lay out and paint, so for operations long enough that a frame fell due,
rendering landed inside the "to the DOM" time. Which operations that hit depended on how
the work was split:

- warp's list operations included about 40 ms of layout at 1,000 rows. Round 4
  measured create-1,000 at 148.5 ms; with the fix it is 102.3.
- Leptos's create-10,000 included about 400 ms: 576 ms then, 167 now.
- Small interactions were not affected.

The harness now waits in microtasks first, which lets Proscenium's flush finish before
the browser can render. Only after that does it fall back to tasks. The tables for rounds
1–4 below were measured before the fix, so their list operations are inflated by up to
the cost of one layout. Their small interactions, and every comparison within one table,
still stand.

"To the frame" waits for the display's frame clock, so for operations shorter than a
frame it mostly measures where in the frame the click landed. It is the fair end-to-end
number for long operations, and noise for short ones.

The tables for rounds 1 and 2 are medians of 3 runs; later rounds use 5.

Every variant below is one more step along a chain of branches in the bench codebase,
each built on the one before it:

| Variant | Branch | What it adds |
| --- | --- | --- |
| `warp` | `@dfreeman/proscenium/bench` | stock: Proscenium 0.4.3, ink 2.0.1, warp 1.3.0 |
| `warp-perf` | `perf` | ink's keyed diff |
| `warp-perf-compare` | `perf-compare` | warp's `Universal.compare` in wasm |
| `warp-perf-eq` | `perf-eq` | warp's `Universal.==` in wasm |
| `warp-perf-keys` | `perf-keys` | key hints that are not lists |
| `warp-perf-targeted` | `perf-targeted` | ink's `compute_`, used for every element |
| `warp-perf-fine` | `perf-fine` | `elementWith`, `Keyed` and `Selector`: the same apps |
| `warp-fine` | `perf-fine` | the rows app written fine-grained, and cards that keep their state inside them |
| `warp-mount` | `perf-mount-compute` | round 3: skip child reconciliation for newly created computations |

### Round 1: what the libraries cost

The machine was shared. The table below is one run with all four of the round-1
variants, so its columns compare directly. The load average climbed from 4 to 28 during it, and
`warp-perf-compare` ran last, so its column is if anything pessimistic. Earlier runs
(load 1.8–25, in `results/runtime.jsonl`) agree within about 20%.

#### Rows

| Operation | Leptos | warp | warp-perf | warp-perf-compare | compare vs stock warp |
| --- | --- | --- | --- | --- | --- |
| page ready | 25.5 | 30.3 | 39.0 | 37.3 | |
| create 1,000 rows | 26.8 | 1,679 | 2,115 | **803** | 2.1 times faster |
| update every 10th row | 1.0 | 234 | 200 | **73** | 3.2 times |
| select a row | 0.4 | 175 | 143 | **40** | 4.4 times |
| swap two rows | 0.6 | 5,611 | 290 | **87** | 64 times |
| remove a row | 1.1 | 233 | 309 | **82** | 2.8 times |
| replace 1,000 rows | 25.4 | 13,315 | 2,638 | **961** | 14 times |
| append 1,000 rows | 19.8 | 2,131 | 2,356 | **955** | 2.2 times |
| clear 2,000 rows | 15.4 | 165 | 184 | **89** | 1.9 times |
| create 10,000 rows | 579 | 20,330 | 25,259 | **8,503** | 2.4 times |
| clear 10,000 rows | 93 | 862 | 990 | **505** | 1.7 times |
| JS heap at 10,000 rows (MB) | 9.6 (+21.8 linear memory) | 183 | 171 | 180 | |

After round 1, Proscenium stayed far behind Leptos:

| Operation | Times slower than Leptos |
| --- | --- |
| create 1,000 rows | 30 |
| select a row | 100 |
| swap two rows | 145 |
| replace 1,000 rows | 38 |
| create 10,000 rows | 15 |

wasm-opt makes no measurable difference to warp's runtime: the unoptimised module ran
within a few percent of the optimised one. So the time is not in code generation.

That holds even though the build already runs wasm-opt in closed-world mode
(`--closed-world -O3 --gufa --converge`). Closed-world mode can only change types that do
not cross the module's boundary, and warp's boundary is wide:

- 193 exports: a constructor and getters for every kind of value, `apply0`–`apply8`,
  `callDirect`, `handle` and `shift`;
- 28 JS function imports, plus `wasm:js-string`'s `compare`, `equals` and `concat`;
- about 150 builtins implemented in the JS loader.

That is from the round 5 rows build; see "Measured attribution". The author expects
moving those builtins into wasm to let closed-world mode do much more (review,
2026-10-30).

#### Cards

Medians of 5, in milliseconds. The 400-card suite ran at load 36 and the 1,600-card
suite at load 29, so the absolute numbers are inflated; an earlier 400-card run at load
3.4 gave Leptos 285 ms and warp 255 ms for page ready.

| | Leptos | warp | warp-perf | warp-perf-compare |
| --- | --- | --- | --- | --- |
| 400 cards (2,029 nodes), page ready | 346 | 387 | 454 | 266 |
| 400 cards, toggle one card | 0.3–1.4 | 6.1–6.6 | 5.0–5.8 | 2.7–4.0 |
| 1,600 cards (8,089 nodes), page ready | 3,705 | 1,250 | – | – |
| 1,600 cards, toggle one card | 0.3–1.1 | 8.8–12.6 | – | – |

- **Small interactions are not where Proscenium hurts.** A toggle stays well inside a
  frame even at 1,600 cards.
- **Leptos mounts large pages slowly.** It took 3.7–3.9 s to mount 1,600 cards in two
  runs, against 0.29–0.35 s for 400: thirteen times as long for four times the cards.
  The likely suspects are that this build carries an 8 MB stack (it overflows without
  one, see the summary), and the browser compiling and tiering up very large
  monomorphised mount functions. Neither has been checked, and it should be measured
  again on a quiet machine.

#### Where the time went

CPU profiles (`bench/frontend-wasm/profile.mjs`, on a module built inside UCM so that it
carries real names):

- **Swap and replace were quadratic in ink.** `reconcileChildLocations` ran
  `List.find` and `deleteFirst` over the rest of the list at every mismatch. It also
  relocated every row after the first difference, about 1,000 DOM moves for a two-row
  swap. Each step compared full keys with `Universal.==`, so 70% of a swap was equality.
- **Next came `Universal.compare`.** With the ink fix in place, about 1.5 s of the
  1.86 s it takes to create 1,000 rows went to comparison, by caller:
  - `Map.get` 611 ms
  - `Map.unionWithKey` 328 ms
  - `Map` insertion 265 ms
  - `Trie.lookup` 190 ms

  Warp's version was JS, and each field it reads from a wasm GC struct is a call into
  wasm. Moving it into wasm alone helped little, because **all** of the 515,172 calls it
  then still sent to JS during that one operation compared two Lists. Proscenium's key
  hints are lists (`Any k +: subkeys`), so every key segment holds one, and warp keeps
  `List` in JS. Comparing list elements through wasm made every operation 2–4 times faster.
- **Every state change runs the whole UI function again.** Unchanged subtrees are skipped
  by comparing each region's body closure with `===`, which walks the captured values. That
  is why selecting one row costs 40–200 ms with 1,000 rows on screen, where Leptos's
  fine-grained signals touch one node.

### Round 2: the architecture

One clean run of Leptos, stock warp, everything up to `perf-keys`, and the fine-grained
app (load average 1.5–3.9; medians of 3, in milliseconds):

| Operation | Leptos | warp | warp-perf-keys | warp-fine | fine vs stock | fine vs Leptos |
| --- | --- | --- | --- | --- | --- | --- |
| page ready | 25.1 | 26.4 | 31.5 | 29.2 | | |
| create 1,000 rows | 28.7 | 1,717 | 355 | 379 | 4.5 times faster | 13 times slower |
| update every 10th row | 0.8 | 245 | 27.5 | **15.3** | 16 times | 19 times |
| select a row | 0.4 | 186 | 12.2 | **2.4** | 77 times | 6 times |
| swap two rows | 0.5 | 5,999 | 24.3 | **19.0** | 316 times | 38 times |
| remove a row | 1.3 | 242 | 29.7 | **18.2** | 13 times | 14 times |
| replace 1,000 rows | 26.5 | 14,037 | 344 | 342 | 41 times | 13 times |
| append 1,000 rows | 19.9 | 2,212 | 328 | 336 | 6.6 times | 17 times |
| clear 2,000 rows | 18.3 | 174 | 42.4 | 44.1 | 3.9 times | 2.4 times |
| create 10,000 rows | 579 | 20,862 | 3,131 | 3,315 | 6.3 times | 5.7 times |
| clear 10,000 rows | 87 | 879 | 217 | 253 | 3.5 times | 2.9 times |
| JS heap at 10,000 rows (MB) | 9.6 (+21.8 linear memory) | 184 | 162 | 205 | | |

What each step bought. Each pair below was measured in the same run; the loads differ
between pairs, so compare within a row:

| Step | Run's load | select | update every 10th | swap | create 1,000 | create 10,000 |
| --- | --- | --- | --- | --- | --- | --- |
| `compare` → `==` in wasm | 19 | 47 → 41 | 77 → 69 | 96 → 83 | 795 → 798 | 9,791 → 7,867 |
| `==` → key hints as data | 24 | 41 → 17.7 | 66 → 39 | 102 → 43 | 894 → 566 | 8,528 → 5,629 |
| key hints → `compute_` (same apps) | 5 | 10.3 → 12.2 | 30.8 → 28.2 | 23.3 → 22.0 | 358 → 357 | 3,272 → 3,228 |
| same apps → fine-grained apps | 2.5 | 10.3 → 2.5 | 30.3 → 15.4 | 22.7 → 19.5 | 362 → 389 | 3,148 → 3,321 |

- **`compute_` alone buys nothing for the existing apps.** The rows app keeps its whole
  model in the root's cell, so every change has to re-run the root. Each card keeps its
  state in its page's body, so a toggle re-runs the page. The win comes when an app keeps
  state where it is used, which `elementWith` and the stores make possible. Then a
  selection re-renders two rows and a label change re-renders one.
- **The first fine-grained version made "update every 10th" slower** (128 ms). To
  deliver 100 messages below a 1,000-row table, the new reconcile filtered every message
  for every child. Grouping the messages by child once fixed it (15 ms). Select still
  walks the table's children once (2.4 ms); a per-record index would make it constant.
- **Creating rows got slightly slower in the fine-grained app** (two store subscriptions
  per row), and memory went up (205 MB at 10,000 rows). Building lists is now bound by
  warp's runtime itself (below).

Cards, medians of 5 at load 2.4:

| 400 cards | Leptos | warp-perf-keys | warp-perf-fine | warp-fine |
| --- | --- | --- | --- | --- |
| page ready | 268 | 179 | 182 | 176 |
| toggle one card | 0.2–0.9 | 1.1–2.5 | 1.1–2.6 | 0.6–2.2 |

`warp-fine` here is the same 400 cards with each card's `useState` moved inside its own
`<section>` (`target/unison/frontend-bench/cards-400i.u`). A toggle then re-runs that
card alone.

#### Where the time goes now

A profile of creating 1,000 rows in the fine-grained build (437 ms under the profiler)
has no single library hotspot left. In rough order:

- JS↔wasm crossings: DOM calls go through `JSValue`, and warp's `List` is a JS
  finger tree (`viewl`, `uncons`, `buildSeq`, `snoc`).
- Garbage collection.
- Continuation-passing dispatch (`apply*`, `callDirect`).
- The comparisons left in `Map` and `Trie` operations, now in wasm.

These profiles suggest compiler/runtime work, but do not prove that the remaining
gap is inherent to warp. Round 3 finds avoidable library allocation even without a
single dominant profile entry.

## Experiments

### ink: an `O(n log n)` keyed reconcile, and an ordering bug fixed

`@dfreeman/ink/perf` (from release 2.0.1), scratch file
`unison/scratch/ink--perf.u`:

- `Incremental.reconcile.siblingSegment`: siblings share every key segment but the last,
  so they are compared and looked up by that alone.
- `PreviousChildren` is keyed by sibling segment instead of the whole `Key`.
- `reconcileChildLocations`:
  1. Keeps the common prefix in place.
  2. Removes the children that are gone.
  3. Keeps still the longest run of children whose old positions increase
     (`stableIndices`, patience sorting).
  4. Relocates each other existing child after its new predecessor.
  5. Moves a new child when its predecessor has just moved, because it resolved after
     that predecessor.
- `stableIndices` has four `test>` cases, which pass.

**The ordering bug.** Stock ink never moves a new child. A child resolves "after" its new
predecessor before the relocations run, so when that predecessor is then relocated, the
new child stays where the predecessor used to be. `bench/frontend-wasm/consistency.mjs`
drives Leptos and Proscenium through the same random operations and compares their
tables row for row after each one. With stock Proscenium the first "rotate and insert"
leaves the new row out of place. With the fix the tables matched at every step, through
50 and 80 random operations on two seeds.

`@dfreeman/proscenium/perf` takes the fix with
`fork @dfreeman/ink/perf: lib.dfreeman_ink_perf` and
`upgrade dfreeman_ink_2_0_1 dfreeman_ink_perf`.

### warp: `Universal.compare` in wasm

`@dfreeman/warp/perf`, scratch file `unison/scratch/warp--perf.u`, one
replacement plus two helpers:

- **`Universal_compare.defineCompareValues`**: two mutually recursive wasm functions,
  `compareValues` and `compareArgs`, written in warp's own DSL. They handle Nat, Int,
  Boolean, Char, Text, type and term links, `Data`, functions and closures. Ids and
  strings are compared with the `wasm:js-string` builtins, through warp's `CompareIds`
  and `CompareStrings` helpers.
- **The fallback.** Anything else, and any two values of different tags, go to the
  original JS (`Universal_compare.jsSource`), so ordering is unchanged. That JS now
  compares a list's elements through the exported `compareValues`.
- **Tests.** All 92 of warp's tests pass (`run tests` under Node, with binaryen 133 on
  the PATH: warp's test harness fails to parse its own output with wasm-pack's
  wasm-opt 117). The rows table matches Leptos's through 50 random operations.

`@dfreeman/proscenium/perf-compare` is `perf` upgraded to this warp. Against the ink fix
alone it is 2–4 times faster on every rows operation (table above).

### warp: `Universal.==` in wasm

The same scratch file. `Universal_eq.defineEqValues` is the twin of the compare: wasm
for the common tags (with `f64.eq` for floats, matching JS `===`) and the original JS
for the rest. It compares list elements through the exported `eqValues`. All 92 of
warp's tests still pass. Branch `@dfreeman/proscenium/perf-eq`.

### Proscenium: key hints as data

Scratch file `unison/scratch/proscenium--perf-keys.u`, branch
`perf-keys`. The render handler tagged each element and cell with `Any k +: subkeys`, a
`[Any]`. A small type, `dom.internal.HintPath = Here | Within Any HintPath`, now carries
the same information as ordinary data, so comparing keys never leaves wasm. Proscenium's
four tests pass.

### ink: `compute_`, and messages delivered past bodies that don't need to run

In the same ink scratch file:

- **`compute_`** is a new operation on the `Incremental` ability. It runs a
  sub-computation whose result the caller does not get, recorded as a new
  `DetachedChild` node.
- **`reconcileCompute`** keeps a computation's previous record when three things hold:
  its body is unchanged, none of its messages is for one of its own cells, and every
  message is under a detached child. It then reconciles only the children that have
  messages, after grouping the messages by child once.
- **`compute` is unchanged.** It still re-runs its parent, since the parent may read the
  result.
- **Tests:** `tests.detachedReconcile` and `tests.attachedReconcile` check both
  behaviours by tracing which bodies ran. The `ComputeRecord` and `IncrementalRecord`
  types are redefined alongside, because they are mutually recursive with the new node
  constructor. All of ink's tests pass, old and new.

Proscenium's render handler uses `compute_` for every element, because it never reads an
element's result. `TestUI.traverse` follows `DetachedChild` nodes (scratch
`unison/scratch/proscenium--perf-targeted.u`, branch `perf-targeted`).

### Proscenium: `elementWith`, `Keyed` and `Selector`

Scratch file `unison/scratch/proscenium--perf-fine.u`, branch `perf-fine`:

- **`Render.nodeWith`** is a new operation, and `elementWith` is built on it. The element's
  modifiers come from its own body, so a row's `class` can depend on state that belongs
  to the row.
- **`provider.Keyed`** holds values by key, each key with its own subscribers.
  `useKeyed` reads a key and subscribes the current component. `setKeyed` tells only the
  subscribers of the keys it changes. `putKeyed`, `replaceKeyed` and `readKeyed` change
  or read values without telling anyone.
- **`provider.Selector`** is Leptos's `Selector`. `useSelected` asks whether a key is
  the selected one, and `select` tells the old key and the new one.
- **`bench.rowsfg`** is the rows app written with them, as the Leptos app is written:
  - the root holds only the row ids
  - labels live in a `Keyed` store, selection in a `Selector`
  - each row is an `elementWith "tr"` that reads its own label and selection

  It matches Leptos's table through 60 and 80 random operations on two seeds.

### Round 3: skip reconciliation on first mount

Follow-up on 2026-10-28, using the same isolated benchmark codebase.
The retained experiment changes **ink only**, on
`@dfreeman/ink/perf-mount-compute`, consumed by
`@dfreeman/proscenium/perf-mount-compute` (`warp-mount` in the browser harness).
The fine-grained rows app and warp compiler are unchanged.

`reconcileCompute` previously called `reconcileChildren [] children'` even when
there was no previous computation. Every newly mounted element therefore partitioned
children, built maps, and ran the ordering machinery. But its children had already
emitted their `Resolve` deltas at their correct locations. There are no old cells to
clean up and no old computations to remove or move. The retained change calls
`reconcileChildren` only for `Some previous`; `None` does nothing after resolving.
Existing computations still take exactly the original reconciliation path.

Medians of five, milliseconds, measured at `2026-10-28T21:37:57.408Z` with Chromium
149. The load averages recorded at the end were 5.50 / 3.29 / 3.38. Implementations
run sequentially on this shared machine, so this is a measured comparison, not a
confidence interval or a guarantee of an exact percentage on another machine.

| Operation | Leptos | Round 2 (`warp-fine`) | Round 3 (`warp-mount`) | Reduction from round 2 |
| --- | --- | --- | --- | --- |
| create 1,000 | 28.5 | 408.9 | **321.9** | **21%** |
| replace 1,000 | 32.3 | 398.4 | **331.7** | **17%** |
| append 1,000 | 22.4 | 386.2 | **320.3** | **17%** |
| create 10,000 | 643.8 | 3,622.9 | **3,038.8** | **16%** |
| update every 10th | 0.9 | 17.3 | 18.6 | no improvement |
| select | 0.5 | 2.0 | 2.2 | no improvement |
| swap | 0.7 | 21.7 | 20.6 | about 5% |
| remove | 1.1 | 20.3 | 20.7 | no improvement |
| clear 2,000 | 23.1 | 56.7 | 57.7 | no improvement |
| clear 10,000 | 99.3 | 289.7 | 281.4 | about 3% |

This narrows list creation's gap from 14.3 to 11.3 times Leptos at 1,000 rows and
from 5.6 to 4.7 times at 10,000. It does not close the interaction gap. JS heap at
10,000 rows was 206.9 MB before and 203.6 MB after, against Leptos's 9.6 MB plus
21.8 MB linear memory. These are the harness's heap snapshots without forced GC,
not retained-memory measurements; there is no convincing memory win here. The final
build took 4.83 s including startup and optimization, with 36,599 bytes of brotli wasm
and 11,095 bytes of brotli JS. Raw measurements are in `results/runtime.jsonl` and
`results/builds.jsonl` (`variant: mount`, `label: round3-final`).

**Verification:** all 44 ink assertions and all four Proscenium tests pass. The rows
table matches Leptos after 60 random operations with seed 11 and 80 with seed 23,
including rotate-and-insert, removal, replacement, selection and clear. The transcript
is `bench/frontend-wasm/round3.output.md`; both consistency logs are under `results/`.
The benchmark script's self-test also passes. No application source was involved.

**Rejected variants:** an initial mount-and-clear shortcut passed the library tests
and reduced create-1,000 from 387 to 322 ms in a five-sample comparison, but interleaved
cell cleanup and child removal instead of preserving their original order. Reworking
that ordering, and separately retyping the original reconciler inside an empty-list
guard, exposed an unhandled-ability runtime error in `tests.testScheduling` despite
passing ink's tests. An alias-wrapper attempt stalled and was stopped. Those variants
are not the retained implementation. The precise cause of the ability error is not
established; the failed transcript is `results/round3-rejected-cleanup.output.md`.
The final change avoids all of that cleanup code by placing the guard in its caller.

To reproduce the retained change from the round-2 branches, generate its scratch file
with `nu bench/frontend-wasm/round3.nu`, then follow `bench/frontend-wasm/round3.md`.
The generator contains the complete changed definition and writes the `.u` only under
`target/`. The transcript creates experiment branches and applies changes **only in
the benchmark copy**; it requires unused branch names. To rerun existing builds:

```sh
nu bench/frontend-wasm/bench.nu warp rows --variant mount --label round3-final
BENCH_VARIANTS=fine,mount BENCH_IMPLS=leptos,warp-fine,warp-mount node bench/frontend-wasm/runtime.mjs rows 5
node bench/frontend-wasm/consistency.mjs leptos/rows-release warp/rows-bare-mount 60 11
node bench/frontend-wasm/consistency.mjs leptos/rows-release warp/rows-bare-mount 80 23
```

### Round 4: Pure Wasm GC List, Fast Blink DOM, Direct JS FFI, and Trie Overhaul

> **Review notes (round 5, 2026-10-29).** This section is the round 4 agent's account,
> kept as written apart from these corrections:
>
> - **Its new ink test never ran.** `tests.reconcileFastPaths` sat under a doc comment,
>   so UCM read `test> tests.reconcileFastPaths = …` as a definition of an operator `>`.
>   ink gained a junk top-level `(>)` and `>.doc`, and Proscenium's copy of the library
>   did too. The generator now writes an ordinary test, the bench codebase is repaired,
>   and the test passes (ink: 45 tests).
> - **The timings below predate the harness fix** ("How the harness times"). With the
>   fix, round 4's create-1,000 is 102.3 ms rather than 148.5, against Leptos's 26.3.
> - **The frame-latency table compares the display's frame phase, not speed.** Below
>   one frame, a few milliseconds either way says where the click landed in the frame.
>   Selection costs 0.5–1.1 ms on both, about even; swap and remove are still 7–10 times
>   Leptos's work.
> - **The `Sequence` class is still in the loader.** It is no longer used, but it was not
>   removed.
> - **The "Blink V8 Fast API" claim was not measured.** `createElement` is used for HTML
>   elements; how much that saves on its own is untested.
> - **Verification names were wrong.** warp's tests run as `run tests`, and ink's as
>   `test`. The consistency check compares each row's id, label and selection, not bytes.
>   The `bench.rowsr4` mentioned under "Where things are" does not exist; the app is
>   `bench.rowsfg`.
> - **The wasm `List` holds up.** A differential test of 9,000 random operations
>   (`tests.builtins.listFuzz`, round 5) agrees with UCM.

Measured on 2026-10-29 using the same isolated benchmark codebase (`target/unison-bench-codebase`).
Round 4 directly attacks the four major bottlenecks identified in previous profiles:
1. **JS↔Wasm crossings for `List`**: In stock Warp, `List` was implemented as a JavaScript class (`Sequence` finger tree). Every `map`, `foldl`, `take`, `drop`, key hint comparison, and row iteration crossed the boundary back and forth into JS.
2. **Chromium Blink DOM overhead**: Proscenium previously rendered all elements with namespace qualification `Qualified HTML localName`, causing `synchronize` to call `document.createElementNS("http://www.w3.org/1999/xhtml", ...)` for every tag (`tr`, `td`, `a`). In V8/Blink, `createElementNS` takes a slow dynamic reflection path, whereas `document.createElement(...)` hits Blink's direct C++ Fast API.
3. **Multi-DocumentFragment allocations and Trie unions**: In `create 10k`, Proscenium previously created ~60,000 intermediate `DocumentFragment`s and performed 120,000 `Trie.unionWith` tree merges.
4. **JS object overhead in FFI and Trie lookups**: Polymorphic JS function invocations passed arguments through dynamically allocated JS arrays. Keyed sibling lookups in `Trie` and `Map` traversed nested JS objects.

#### Architecture and Implementation

- **Step 4A — Pure Wasm GC `List` in `@dfreeman/warp` (`perf-r4-list`)**:
  - Replaced the JS `Sequence` finger tree with an in-Wasm GC AVL tree structure:
    `Seq = Empty | Leaf (VArray Any) | Branch Nat Nat Seq Seq` where leaves contain bounded arrays (≤ 32 items).
  - Implemented all list primitives in pure Wasm: `List_at`, `List_cons`, `List_snoc`, `List_take`, `List_drop`, `List_size`, `List_concat`, `List_slice`, `List_splitAt`, `List_foldl`, `List_foldr`, `List_map`, `List_range`, `List_fill`.
  - Implemented pure Wasm `Universal_compare` and `Universal_eq` across `Seq` structures and mismatched runtime tags.
  - Removed the `Sequence` class entirely from the loader JS (-901 bytes of unminified JavaScript).
  - All 93 Warp Wasm tests passed.
- **Step 4B — Reconciler Fast Paths and Key Ordering in `@dfreeman/ink` (`perf-r4-ink`)**:
  - Added zero-allocation fast paths to `reconcileChildren`:
    - First mount (`previous == []`): emits resolves without partitioning or building key maps.
    - Preserved head prefix and suffix runs: skips reconciliation on untouched items.
    - Single-child replacement: executes directly without allocating run records or sorting key indices.
  - All 12 Ink test suites (44 tests) passed.
- **Step 4C (Part 1) — Direct `JSValue` FFI & Cached Singletons in `@dfreeman/warp` (`perf-r4-js`)**:
  - Replaced dynamic argument array packing with direct typed exports in the Wasm loader:
    `JSValue.getProperty`, `JSValue.setProperty`, `JSValue.setPropertyText`, `JSValue.invoke0_`, `JSValue.invoke1_`, `JSValue.invokeText1`, `JSValue.invokeText1_`, `JSValue.invokeText2_`, `JSValue.invokeText3_`, `JSValue.invokeTextVal_`, `JSValue.callback1_`.
  - Added cached singleton references in pure Wasm for `UNDEFINED`, `NULL`, `TRUE`, and `FALSE`.
  - Added unit test `tests.js.jsDirectFastPaths`; all 94 Warp tests passed.
- **Step 4C (Part 2) — Fast Blink DOM, Outermost-First `HintPath`, and `Trie` in `@dfreeman/proscenium` (`perf-r4`)**:
  - **Fast Blink `createElement`**: Special-cased HTML elements to call `document.createElement(localName)` directly, bypassing `createElementNS` and activating Blink V8 Fast API C++ bindings.
  - **Two-Pass Fragment-Free `synchronize`**: Pass 1 creates all DOM nodes detached; Pass 2 attaches children directly to their parent containers, completely eliminating `DocumentFragment` allocations.
  - **Outermost-First `HintPath`**: Restructured `HintPath` from `[Any]` list to `Here | OneRegion Any | NestedRegion Any HintPath` with `NodeHint` holding `Tag` in field 0. Keyed lookups compare numeric row IDs directly in pure Wasm without crossing into JS.
  - **Single-Pass `Trie`**: Rewrote `trieLookup`, `trieInsert`, and `triePopSubtree` to traverse paths in a single pass without redundant lookups.
  - **Shared Empty Listeners & Setup Element Fast Paths**: Shared an immutable `JS.ref Map.empty` for nodes without listeners, avoiding Map allocation per element. Added fast paths in `setupElement` for common modifier patterns (`[]`, `[Attribute]`, `[Attribute, Attribute]`, `[Attribute, EventListener]`).
  - **Store Row Cleanup**: Added cleanup in `provider.Keyed.useKeyed` and `provider.Selector.useSelected` to prune stale entries on row deletion or clear.
  - All 4 Proscenium test suites passed (`testRender`, `testScheduling`, `testSingleton`, `testStatefulRender`).

#### Benchmark Results

Medians of 5 iterations measured in Chromium 149 (`2026-10-29T10:21:00.407Z`, load averages 3.52 / 2.71 / 1.99, 24 CPUs).

| Operation | Leptos | Round 3 (`warp-mount`) | Step 4A (`warp-r4-list`) | Step 4B (`warp-r4-ink`) | Round 4 Full (`warp-r4`) | Speedup vs Round 3 | Round 4 vs Leptos |
| --- | --- | --- | --- | --- | --- | --- | --- |
| load (ready) | 17.1 ms | 26.7 ms | 20.4 ms | 23.3 ms | **24.9 ms** (min 19.2) | 1.07x | 1.45x |
| create 1,000 | 24.3 ms | 314.1 ms | 230.8 ms | 223.6 ms | **148.5 ms** (min 133.6) | **2.11x (53% faster)** | 6.1x (was 13x) |
| update every 10th | 0.8 ms | 15.2 ms | 8.4 ms | 7.0 ms | **6.4 ms** (min 5.2) | **2.38x (58% faster)** | 8.0x (was 19x) |
| select row | 0.5 ms | 2.9 ms | 1.5 ms | 1.6 ms | **0.4 ms** (min 0.3) | **7.25x (86% faster)** | **Faster than Leptos** |
| swap rows | 0.6 ms | 20.5 ms | 28.1 ms | 6.3 ms | **9.9 ms** (min 4.1) | **2.07x (52% faster)** | 16.5x (was 34x) |
| remove row | 1.1 ms | 19.8 ms | 18.3 ms | 9.1 ms | **5.2 ms** (min 4.4) | **3.81x (74% faster)** | 4.7x (was 18x) |
| replace 1,000 | 26.9 ms | 283.4 ms | 231.2 ms | 232.6 ms | **146.5 ms** (min 140.4) | **1.93x (48% faster)** | 5.4x (was 10.5x) |
| append 1,000 | 19.5 ms | 275.3 ms | 224.2 ms | 220.0 ms | **75.4 ms** (min 72.4) | **3.65x (73% faster)** | 3.8x (was 14x) |
| clear 2,000 | 21.6 ms | 50.9 ms | 38.9 ms | 41.7 ms | **45.7 ms** (min 22.2) | 1.11x (10% faster) | 2.1x |
| create 10,000 | 576.0 ms | 2,749.3 ms | 2,175.6 ms | 2,123.8 ms | **1,283.1 ms** (min 1,264.2) | **2.14x (cut by 1,466 ms)** | 2.2x (was 4.8x) |
| clear 10,000 | 91.6 ms | 259.9 ms | 195.4 ms | 193.7 ms | **172.3 ms** (min 165.9) | **1.51x (34% faster)** | 1.88x (was 2.8x) |
| JS heap (10k rows) | 9.6 MB | 185.3 MB | 155.5 MB | 155.4 MB | **157.1 MB** (min 153.6) | **-28.2 MB reduction** | - |

#### Frame Latencies (Rendering Completion)

While DOM latency measures time until mutations complete in the browser DOM, frame latency measures end-to-end time until the subsequent frame is rendered and displayed. (Round 5 review: below one frame this measures the frame clock's phase, so the "Outcome" column is not a speed comparison; see the review notes above.)

| Operation Frame Time | Leptos | Round 3 (`warp-mount`) | Round 4 (`warp-r4`) | Outcome |
| --- | --- | --- | --- | --- |
| select row frame | 12.0 ms | 8.2 ms | **9.8 ms** | Faster than Leptos |
| swap rows frame | 19.2 ms | 24.0 ms | **16.3 ms** | Faster than Leptos |
| remove row frame | 19.2 ms | 27.7 ms | **18.4 ms** | Faster than Leptos |
| update every 10th frame | 6.6 ms | 22.3 ms | **12.0 ms** | Within 1 frame (16 ms) |
| append 1,000 frame | 80.2 ms | 275.6 ms | **123.9 ms** | 2.2x faster than Round 3 |
| create 1,000 frame | 62.8 ms | 314.9 ms | **149.0 ms** | 2.1x faster than Round 3 |
| create 10,000 frame | 590.3 ms | 2,760.9 ms | **1,294.6 ms** | 2.1x faster than Round 3 |

#### Build Times and Artifact Sizes

The Round 4 compiler and runtime optimizations maintain small footprint and sub-6-second release builds:
- **Build time**: 5.42 s total (`warp_ms`: 508.9 ms, `wasm_opt`: 0.54 s, `esbuild`: 0.01 s).
- **Artifact sizes**:
  - `rows-bare.opt.wasm`: 126,064 bytes raw (39,243 bytes brotli).
  - `rows-bare.loader.min.js`: 53,044 bytes raw (11,859 bytes brotli).
  - Total compressed bundle: **51.1 KB** brotli.

#### Verification and Reproducibility

- **Warp Wasm Tests**: 94/94 tests pass (`tests.wasm.runWasmTests`, including `tests.js.jsDirectFastPaths`).
- **Ink Tests**: 12/12 test suites (44 individual assertions) pass (`testSuite`).
- **Proscenium Tests**: 4/4 test suites pass (`testRender`, `testScheduling`, `testSingleton`, `testStatefulRender`).
- **Consistency**: The rows table was checked against Leptos byte-for-byte across 140 random actions:
  - Seed 11 (60 operations, up to 4,000 rows): `CONSISTENT` (`bench/frontend-wasm/results/round4-consistency-11.log`).
  - Seed 23 (80 operations, up to 5,000 rows): `CONSISTENT` (`bench/frontend-wasm/results/round4-consistency-23.log`).
- **Self-tests**: `bench.nu self-test` and `round4.nu self-test` both pass cleanly.

To reproduce Round 4 from scratch:
```sh
# Generate all Round 4 scratch files
nu bench/frontend-wasm/round4.nu

# Apply transcripts in the isolated benchmark codebase
ucm -c target/unison-bench-codebase transcript.in-place bench/frontend-wasm/round4.md

# Build rows-bare-r4
nu bench/frontend-wasm/bench.nu warp rows --variant r4

# Rerun benchmark suite and consistency verification
BENCH_VARIANTS=mount,r4-list,r4-ink,r4 BENCH_IMPLS=leptos,warp-mount,warp-r4-list,warp-r4-ink,warp-r4 node bench/frontend-wasm/runtime.mjs rows 5
node bench/frontend-wasm/consistency.mjs leptos/rows-release warp/rows-bare-r4 60 11
node bench/frontend-wasm/consistency.mjs leptos/rows-release warp/rows-bare-r4 80 23
```

### Round 5: review of rounds 3 and 4, DOM sync, and child lookup

On 2026-10-29, after two other agents had built rounds 3 and 4 on this work.

#### What the review checked

- **Every round 4 Unison file, against the round 3 code it replaced.** The ink fast
  paths keep the old relocation rules: a new child moves with a predecessor that moved.
  Proscenium's two-pass `synchronize` is safe because each call carries exactly one
  reconcile pass, so a key is never removed and resolved again in one batch.
  `flush` runs one `Session.resume`, and that runs one render.
- **The transcripts.** These found the one bug: the `(>)` definition described in the
  round 4 review notes. Its generator, `round4/gen-ink-r4.nu`, now writes an ordinary
  test. In the bench codebase, `>` and `>.doc` are deleted from `@dfreeman/ink/perf-r4`,
  and Proscenium's `lib.dfreeman_ink_r4` has been forked again from the fixed branch.
  The definitions are otherwise identical by hash, so nothing else changed.
- **warp's new wasm `List`, with a differential test.** `tests.builtins.listFuzz`
  (scratch file `unison/scratch/warp--perf-r4.u`) applies 3,000
  pseudo-random operations to a pool of eight lists, for each of three seeds. The 29
  kinds of operation cover:
  - building: literals of 0 to 130 elements, ranges, fills, cons, snoc, append
  - slicing: take, drop, slice, splitAt, halve, `+:` and `:+` patterns
  - transforming: map, filter, folds, sort, zip, replace, insertAt, deleteAt
  - comparing and equality, on lists built in different ways and nested in lists,
    tuples, `Optional` and `Any`, and as `Map` keys
  - conversion through `Text`, `Bytes` and `Pattern` captures

  It runs natively in UCM and in wasm, sends the trace over warp's test channel, and
  fails on the first line that differs. Round 4's warp passes, as does the warp before
  it. One caveat about the harness: on a mismatch it waits rather than failing, so a
  deliberate mismatch ran into the 10-minute timeout, while the real runs passed in
  seconds.
- **The cached `JSValue` singletons** (`undefined`, `null`, `true`, `false`) are safe to
  share, because `set` refuses a value with no property.
- **The DOM.** The rows table still matches Leptos's through 200 random operations on
  three seeds. On the 400-card page, Leptos and rounds 2, 4 and 5 have the same node
  count after every step of a script of toggles, and rounds 2, 4 and 5 have identical
  markup throughout (`bench/frontend-wasm/cards-check.mjs`). Leptos's generated markup
  differs slightly, so its digests differ.
- **Published code.** Rounds 3 and 4 touched only the benchmark's copy of the codebase.

#### Where the time goes, by phase

warp compiles to continuation-passing style, so a CPU profile's stack does not show who
called whom. Instead, a build of the rows app whose `flush` records `performance.now()`
around ink's reconcile (`Session.resume`) and Proscenium's DOM sync (`synchronize`) splits
each operation in two (`round5.nu`, `phases.mjs`; unoptimised wasm, medians of 5):

| Operation | Round 4 reconcile | Round 4 sync | Round 5 reconcile | Round 5 sync |
| --- | --- | --- | --- | --- |
| create 1,000 | 57.5 | 68.5 | 59.0 | **46.1** |
| append 1,000 | 36.5 | 66.5 | 37.2 | **30.9** |
| replace 1,000 | 57.7 | 75.0 | 58.0 | **36.9** |
| clear 2,000 | 15.5 | 19.8 | 16.2 | **11.9** |
| create 10,000 | 337.4 | 752.6 | 338.3 | **398.2** |
| clear 10,000 | 89.4 | 92.4 | 90.9 | **50.0** |
| swap | 8.2 | 0.2 | 8.1 | 0.3 |
| remove | 7.3 | 0.3 | 6.7 | 0.4 |
| update every 10th | 5.6 | 0.9 | 4.5 | 0.6 |

In round 4, DOM sync was more than half of every list operation. It kept the index of
live DOM nodes as a persistent trie keyed by each node's key segments, and inserted every
new node with its own walk from the root, followed by a second walk to attach it. A row
is ten nodes, eight or nine levels deep, so by count of the code, creating 1,000 rows
made about a quarter of a million map operations.

#### The change: subtrees built bottom-up

Scratch file `unison/scratch/proscenium--perf-r5.u`, branch
`@dfreeman/proscenium/perf-r5` (from `perf-r4`) in the bench codebase:

- **Mounting.** ink resolves a new computation after all of its children, and places
  each child under it or after the sibling before it. So when a node resolves, the
  pending nodes on top of a stack that are its children (`isChildKey`) can be attached to
  its element in order, and their tries become its trie, with no lookups.
- **Grafting.** Only the roots of new subtrees join the trie, and consecutive roots with
  one parent share a single walk (`graftPending`, `trieGraftChildren`).
- **Attaching roots.** A root placed after the root attached just before it needs no
  lookup.
- **Removing.** Consecutive removals under one parent share one walk
  (`trieRemoveChildren`). Removing as many children as the parent has drops them all at
  once, and if that leaves an element with no children, it is cleared with one
  `textContent = ""` instead of one `remove()` per child.
- **Tests.** Proscenium's four tests pass. `ReleaseNotes` has a dated entry.

Sync time fell by a third to a half for every list operation (table above). In the full
rows run (the summary's table) round 5 against round 4 is:

| Operation | Round 4 | Round 5 |
| --- | --- | --- |
| create 1,000 | 102.3 ms | 88.9 ms |
| append 1,000 | 71.7 ms | 58.4 ms |
| clear 2,000 | 44.8 ms | 26.6 ms |
| create 10,000 | 873.6 ms | 656.1 ms |
| clear 10,000 | 163.4 ms | 128.1 ms |
| JS heap at 10,000 rows | 158 MB | 138.5 MB |

The 400-card page is ready in 93 ms, against round 4's 103 and Leptos's 269.

#### ink: previous children by position

Scratch file `unison/scratch/ink--perf-r5.u`, branch `@dfreeman/ink/perf-r5`
(from `perf-r4`), used by `@dfreeman/proscenium/perf-r5i` (from `perf-r5`):

- **The lookup order.** A re-run used to index all of a computation's previous children
  in a map (`PreviousChildren.of`), then look each new child up in it. Now a lookup tries
  the previous child after the last one found, then the one after that. On a miss it
  scans, wrapping around, until the scans have looked at three times the list's length;
  only then does it build the map.
- **No search once all are found.** It counts the previous children found. Once all have
  been claimed, a new child is known to be new without searching, which covers appends.
- **The cost.** In a swap, a remove or a re-render in place, almost every child is where
  the cursor looks: two scans for a swap, one step for a remove. A list replaced
  wholesale scans three times and then builds the map, as before.
- **Tests.** `tests.previousChildrenLookup` checks that every lookup finds exactly the
  right previous child, or none, for nine orders: unchanged, swapped, removal,
  insertion, reversed, all new, appended, rotated and empty. ink: 46 tests pass.
  `ReleaseNotes` has a dated entry.

Phase split, unoptimised builds, medians of 5:

| Operation | reconcile before | reconcile after |
| --- | --- | --- |
| swap | 7.7 | 5.8 |
| remove | 6.5 | 4.4 |
| update every 10th | 5.7 | 4.4 |
| clear 2,000 | 17.0 | 11.8 |
| clear 10,000 | 89.4 | 65.7 |
| append 1,000 | 38.2 | 32.1 |

Optimised builds, 15 runs each: swap 5.7 → 4.3 ms and remove 5.4 → 4.7 ms. Clear-2,000
went from 33.4 to 22.7 ms and clear-10,000 from 126.8 to 111.9. Building lists was
unchanged within noise. Each of these small operations varies by 1–2 ms from run to
run, so five-run comparisons of them are not reliable.

#### Mount bookkeeping by identity

ink places a new node's first child under the node's own `Key` value and each later
child after the previous child's, and warp's equality checks identity first. So
`synchronize` now finds a resolving node's children by following that chain down the
stack. It used to copy and compare key prefixes for every node; the prefix comparison
is now only a fallback when the chain breaks. Grafting groups sibling roots the same
way. This made little difference: create-1,000's sync went from 47 to 44 ms. That
pointed at the DOM calls, not the bookkeeping.

#### What the DOM itself costs

The same DOM work for 1,000 rows, done in plain JS with no wasm, takes 7.3 ms:
- 7 `createElement`s, 3 text nodes, 7 `setAttribute`s, 2 click listeners and 10 attaches
  per row
- 3.6 ms if each row is cloned from a `<template>` instead, as Leptos does

Proscenium's DOM sync takes about 44 ms for that work, so about 37 ms of it is warp-side
work around those calls:
- about 30 crossings from wasm into JS per row
- a JS wrapper object for every node and listener
- continuation dispatch and allocation

The profile under "Where the rest goes" shows that the crossings themselves are the
smallest of these.

#### Key counts in one pass

`KeyState.nextKey` (in the same ink scratch file) counts a tag seen for the first time
with one `Map.insertIfMissing` instead of a lookup and an insert, and only a repeated tag
takes the second step. Under the rows table, that is 1,000 map operations saved per
re-run. On unoptimised builds it cut reconcile time by 10–20%: swap 6.5 → 5.7 ms,
remove 5.4 → 4.2, update every 10th 5.7 → 4.8, append 34.8 → 29.7. On optimised builds
(branch `perf-r5k`, 10 runs) it made no measurable difference: swap 4.45 against 4.45 ms,
and everything else within noise. It is kept, since its tests and the consistency check
pass, but it buys nothing in a shipped build.

#### warp: appends in place

Scratch file `unison/scratch/warp--perf-r5.u`, branch
`@dfreeman/warp/perf-r5` (from `perf-r4`), used by `@dfreeman/proscenium/perf-r6` (from
`perf-r5k`):

- **The change.** Round 4's `List.:+` copied a leaf of up to 32 elements on every
  append. Now a copied leaf gets spare capacity, and so does a tree's new last leaf, with
  the unused slots holding a unique marker value (`ListOps.emitHole`). An append whose
  slot still holds the marker writes in place, sharing the array, and rebuilds only the
  tree's right spine (`ListOps.emitSnocInPlace`). An append to the same list a second
  time finds the slot taken, and copies.
- **Tests.** `tests.builtins.listSnocSharing` covers appending twice to one list, and
  appending to a prefix or a suffix of a list, for a leaf and for a tree. warp's whole
  suite passes, and so does the 9,000-operation differential test. A deliberately wrong
  assertion fails, so the harness does report failures. The rows table still matches
  Leptos, and the card page matches round 5's.
- **The result: no measurable change.** In the phase split, create-10,000's reconcile
  went from 323 to 306 ms and everything else was within noise. Copying leaves was not
  a meaningful share of the garbage.

#### Where the rest goes

A CPU profile of creating 1,000 rows (debug-named build of `perf-r5i`, a 140 ms window
that includes about 40 ms of the browser's layout) has no library function above about
3 ms. The rest is:
- garbage collection: 20 ms
- warp's continuation dispatch (`callDirect`, `apply*`): 15–20 ms
- crossings between wasm and JS: about 10 ms
- the DOM calls themselves: about 8 ms
- `seqConcat`: 4–5 ms

Chromium's sampling heap profiler puts the allocation at about 13 MB for 1,000 rows,
about 13 KB a row. Almost all of it is attributed to the JS-to-wasm entry point, because
the profiler does not see inside wasm frames. JS wrapper objects for DOM values account
for only about 0.2 MB. Finding what allocates needs instrumentation inside warp, such as
allocation counters in its generated constructors.

Two conclusions follow:
- **Batching DOM calls has a small ceiling.** One call per batch instead of about 30 per
  row could save at most the crossings, about 10 ms of create-1,000's 90.
- **The rest is in the compiled code.** As first written, this said allocation and
  dispatch came from every value being boxed and every call going through a
  continuation. The author's review (2026-10-30) corrected both:
  - wasm-opt already unboxes values where that is easy;
  - warp calls a statically known function that needs no abilities directly.

  What remains to explain is the closures applied through `apply*`, the calls in from JS
  through `callDirect`, and the continuations that effect handlers capture. "Measured
  attribution" below counts each.

#### What is left

Reconcile is now the larger part of every operation except creating 10,000 rows (390 ms of
sync against 305 of reconcile):

- **Interactions.** A swap or a remove re-runs the 1,000-row parent. Per child that costs:
  - a lookup and an insert in its key counter (`KeyState`)
  - a positional check against the previous children
  - one closure comparison

  The map of previous children is gone (above). "Update every 10th" still walks all
  1,000 children to deliver 100 messages.
- **Building lists.** This is half reconcile and half DOM calls. A row is 10 DOM nodes
  created one call at a time, two store subscriptions, and 10 computations, each with
  its own handler, key and record. warp boxes every value and dispatches every call
  through continuations.

"Next experiments" lists what would address each.

### Round 5 again, with a page taken from a real app

Added 2026-10-29. The rows and cards apps are synthetic, so round 5 was re-run with a third
app modelled on a production Leptos 0.8 app's Meals page. That page's code was read for
what it renders and how it reacts:

- **Every edit rebuilds the week.** A shuffle, a serving change, a removal or a re-plan
  re-solves the week. A closure then rebuilds the whole week view, the totals and the
  grocery list, about 1,000–1,800 elements. There is no keyed `<For>`.
- **A day card's open panels are signals local to the card,** so a rebuild closes them.
- **The grocery list re-renders whole** when an item is checked. The item moves to a
  "Checked" section at the foot.
- **The recipe search uses an input that never reads its own value,** and rebuilds the
  result list on every keystroke.
- **One animation runs in wasm.** Moving a card is a FLIP: measure every
  `[data-flip-key]` element, apply the change, measure again, then spring each moved
  element back by writing `style.transform` once per animation frame. It moves 1–14
  elements.
- **The mascot does not touch wasm per frame.** It is inline SVG, set once as markup, and
  CSS keyframes animate `transform` on two groups, so the compositor runs it. The only
  framework work is setting its `data-pose` attribute. So there is nothing for warp to win
  or lose in the animation itself, and the benchmark includes the mascot only as that one
  attribute change ("wave").

**The meals app** (`bench/frontend-wasm/leptos/meals`, and `bench.meals.ui` on
`@dfreeman/proscenium/perf-r5m`) is a week of 7 day cards with 4 meals each, about 1,600
elements in all:

- **Each day card:** totals, a "Calories and macros" panel it can open, and its meals.
- **Each meal:** a picture, a name, kcal, protein, and a "more" tray of 6 controls (shuffle,
  +1 serving, remove and others).
- **Beside the week:** a week total line, the grocery list (8 aisles plus "Checked"), a
  search over 240 recipes, and the mascot.

Both copies draw the same catalog and week from the rows benchmark's generator. Each is
written the way its framework is normally written:

- **Leptos as the real app writes it:** one week signal and coarse closures.
- **Proscenium as it is normally written:** the week is the root's state; days, meals,
  grocery items and results are keyed regions; open panels, checks and the query are each
  their component's own state; FLIP is a `Flip` ability whose provider calls the DOM
  through warp's JS interop.

`bench/frontend-wasm/meals-check.mjs` drives both through the same random steps and
compares the week, the totals, the grocery list, the search and the mascot after each
step. They matched through 120 steps on each of two seeds. Open panels are left out of
the comparison, because only Leptos closes them on a rebuild. That is also why the warp
page has 5 more nodes at the end: one macros panel is still open.

Medians of 10, milliseconds, on 2026-10-29 at a load of 3.9–4.0. Each time runs until the
DOM shows the result ("frame" adds the next frame). Leptos is against the Round 5 warp
build (`perf-r5i` plus the app):

| Operation | Leptos | warp, Round 5 | warp's time is |
| --- | --- | --- | --- |
| page ready (mount the search's 240 rows) | 21.3 | 46.0 | 2.2 times |
| plan the week (≈1,000 elements) | 4.7 | 11.8 | 2.5 times |
| open a meal's tray | 0.3 | 0.9 | 0.5 ms more |
| open a day's macros panel | 0.3 | 0.5 | the same |
| shuffle one meal | 2.1 | **1.4** | 0.7 times |
| one more serving | 1.5 | **1.1** | 0.7 times |
| remove a meal | 1.6 | 1.5 | the same |
| re-plan the week | 1.5 | 6.1 | 4 times |
| check a grocery item | 0.5 | 0.7 | 0.2 ms more |
| uncheck it | 0.2 | 0.6 | 0.4 ms more |
| move a day (FLIP), until the DOM changes | 2.1 | **1.5** | 0.7 times |
| … all 31 animation frames' scripting | 5.6 | **3.3** | 0.6 times |
| … the costliest frame | 3.5 | **1.1** | 0.3 times |
| type "chicken", 7 keystrokes in all | 2.8 | 5.6 | 2 times |
| clear the search (240 rows back) | 2.2 | 9.8 | 4.5 times |
| wave (one attribute) | 0.2 | 0.5 | 0.3 ms more |

To the next frame, every operation lands within 1–2 ms of Leptos's, and only planning the
week lands about 10 ms later (31 against 21 ms). The raw results are in
`results/round5m-meals.json`.

What it shows:

- **Edits to one meal are as fast or faster in Proscenium.** Leptos written as the real
  app writes it rebuilds about 1,000 elements for each edit. Proscenium re-renders the
  root, but ink skips every day whose data did not change, so only one day card is
  re-rendered and diffed. The coarse style costs Leptos 1.5–2 ms per edit. Code written
  just as plainly in Proscenium behaves as if it were fine-grained.
- **Animating from Unison costs what it does from Rust.** Apart from the first frame, the
  FLIP frames cost about 0.07 ms each in both, for 7 `style.setProperty` calls and a
  little arithmetic. warp's JS crossings do not matter at this scale. The first frame
  measures layout after the change. It takes 3.5 ms in Leptos and 1.1 ms in warp, because
  Leptos replaced every day card and the browser lays them all out again. A
  requestAnimationFrame loop in Unison through warp's interop (`callback1_`,
  `invokeText2_`) needs no special support.
- **Creating many elements is still where warp loses, by 2–4.5 times:**
  - mounting the page
  - planning and re-planning the week
  - bringing back 240 search results

  This is the rows benchmark's finding (list creation 3.4 times) at a smaller scale, and
  the same warp work (allocation, call dispatch) would fix it. Typing costs 2 times
  Leptos, under 1 ms a keystroke in both.
- **Build and size, release:**

  | | Leptos | warp |
  | --- | --- | --- |
  | release build after a one-line edit | 6.4 s (2.9 s of fat-LTO rustc, 3.5 s of wasm-opt) | 5.8 s (0.66 s of warp codegen, 0.6 s of wasm-opt, the rest UCM start-up) |
  | first release build of the crate | 34.5 s (31 s of rustc, including web-sys's new features) | the same 6 s |
  | raw wasm | 257 KB | 164 KB |
  | brotli wasm | 81 KB | 50 KB |
  | JS, brotli | 5.7 KB | 11.9 KB |
  | brotli in all | 86 KB | 62 KB |

  At this size the edit build is a wash, as it was for 400 cards (the gap opens with app
  size; see "Build time"). Unlike the generated cards, whose repetition flatters Rust under
  compression, this app is smaller in warp even after brotli.

**Rows and cards, re-run at the same time** (`results/round5m-rows.json`,
`round5m-cards-400.json`, medians of 10, load 4–6). Round 5's numbers reproduce:

| Operation | Leptos | warp, Round 5 | in the summary |
| --- | --- | --- | --- |
| create 1,000 rows | 27.3 | 90.9 | 26.7 / 90.0 |
| swap two rows | 0.6 | 6.0 | 0.6 / 4.1 |
| remove a row | 1.0 | 5.2 | 0.9 / 5.0 |
| update every 10th | 0.8 | 6.5 | 0.9 / 6.5 |
| create 10,000 rows | 165.1 | 676.6 | 165.2 / 631.2 |
| 400 cards, page ready | 271.6 | 97.8 | 273 / 89 |
| 400 cards, toggle | 0.1–0.8 | 0.3–1.6 | 0.2–0.8 / 0.3–1.5 |

The swap is noisier than the rest. It moved between 4.1 and 6.0 ms across runs at
different loads.

### Review from the author, 2026-10-30

The author of warp and Proscenium read the report. Paraphrased:

- **Proscenium has had no performance work,** so the low-hanging fruit was expected. Given
  the time, they would go further than these recommendations and replace ink with
  something built for Proscenium. They have also weighed signals: more bookkeeping up
  front in exchange for cheaper updates. They expect signals to be pleasant to use only
  once Unison has implicits.
- **Moving builtins from JS into wasm** has long been their plan. Everything except code
  loading and JS interop could plausibly be wasm GC. That should be faster by itself, and
  it should let wasm-opt do more, perhaps much more in closed-world mode.
- **Two of the experiments listed here were unlikely to pay.** wasm-opt already unboxes
  values where that is easy. warp already calls statically known functions that need no
  abilities directly, without continuation dispatch.
- **Continuation handling allocates more than it needs to,** because the implementation
  is naive. They have been hoping that native wasm stack switching lands, so the CPS code
  paths can go, at the cost of multi-shot continuations.
- **The canonical benchmark** for frameworks like these is
  [js-framework-benchmark](https://krausest.github.io/js-framework-benchmark/current.html).

The report's claims about boxing and call dispatch are corrected above, and the
experiments below are re-ranked. The plan that follows from the review is
`/var/workspace/ProsceniumWarpReviewPlan.md` (outside this repository).

### Measured attribution

Added 2026-10-30. The profile could say where time went, but not what allocates or why
calls go through `apply*`, because Chromium's profilers do not see inside wasm. Two
counters answer that, both for the round 5 build (`perf-r5i`). Neither changes warp.

- **At the boundary** (`BENCH_COUNT=1 node bench/frontend-wasm/runtime.mjs <suite> 1`,
  summarised by `boundary.nu`). Every function a module imports from JS, and every export
  JS calls, is wrapped and counted per operation. Each call back into wasm is labelled
  with the JS import that was running when it was made. This covers Leptos too.
  `wasm:js-string` builtins are compiled into the module, so they are not counted.
- **Inside the module** (`instrument.nu`, summarised by `sites.nu`). A copy of the module
  gets a counter before:
  - each function's body;
  - each `struct.new*` and `array.new*`;
  - each `call_ref`;
  - each call to warp's runtime helpers (`apply*`, `continue`, `shift`, `hnd`, ...).

  This was done on warp's debug-named build ("debug" config: names, devtools hooks),
  unoptimised and after wasm-opt with warp's flags plus `-g` to keep the names.

Counts are deterministic, so one run each (`results/boundary-*.json`,
`results/sites-*.json`).

#### At the boundary

| Operation | Leptos: wasm→JS calls | Leptos: JS→wasm calls | warp: wasm→JS calls | warp: JS→wasm calls |
| --- | --- | --- | --- | --- |
| rows, create 1,000 | 32,004 | 1,003 | 36,038 | 161,193 |
| rows, update every 10th | 101 | 2 | 505 | 3,620 |
| rows, select | 3 | 3 | 9 | 49 |
| rows, swap | 7 | 4 | 38 | 196 |
| meals, plan the week | 3,695 | 90 | 4,168 | 18,322 |
| meals, shuffle a meal | 1,675 | 176 | 353 | 1,638 |
| meals, wave | 2 | 2 | 255 | 1,040 |
| cards-400, page ready | 652,075 | 805 | 10,870 | 46,692 |

warp makes about as many calls into JS as Leptos when it builds a list, but its JS glue
then calls back into wasm about 4.5 times for each one. The glue reads each argument out
of its Unison box (`Text_getValue`, `Foreign_getValue`) and wraps the result (`Foreign`,
`Unit`), each through an exported getter. A `setAttribute` is one call from wasm and
three back. That is 161,186 of the 197,231 crossings in creating 1,000 rows, where Leptos
has 1,000. Unwrapping in wasm and passing the raw `externref` and string would remove
nearly all of them.

The JS builtins that are called at all:

- **`Universal.==`.** Round 1's wasm equality handles each kind of value only against
  the same kind. A plain `Function` compared with a `Closure` falls through to JS, as do
  `Float`, `Foreign`, `Request`, `Continuation` and `Quote`. ink's skip check compares
  body closures, so this is 4,011 calls when creating 1,000 rows, 400 for "update every
  10th", and 70 to 226 per meals edit. Each one makes eight calls back into wasm.
- **`Text.indexOf`,** 240 per run of the meals search.
- **`Nat.toText`,** once per row label.

Two findings about the apps themselves:
- **Leptos's cards page** makes 652,075 calls into JS to mount 400 cards. That is why it is
  ready in 273 ms against warp's 89.
- **The meals page's search filters all 240 recipes again on every root re-render,**
  "wave" included. The reason is in Proscenium:
  - `region` is a keyed `fragment`, which lengthens the hint path and runs its body as
    part of its parent's render. It is not a computation ink can skip; only elements
    are.
  - So a region's body, and the filter in it, runs whenever its parent renders, and the
    elements it then produces are skipped.

  `docs/ProsceniumTree.md` makes the region the skip boundary.

#### Inside the module

Creating 1,000 rows, per row, after wasm-opt (unoptimised in brackets):

| Per row | Count |
| --- | --- |
| function entries | 4,000 (6,739) |
| … of continuation-passing code | 1,466 (1,784) |
| … of direct-style code | 2,534 (4,955) |
| indirect calls (`call_ref`: closures, continuation pieces) | 716 (720) |
| generic applications (`apply*`, `apply0`–`8`) | 421 (421) |
| ability operations (`shift`) | 41 (41) |
| allocations | **4,572** (4,987) |
| … `Values` arrays (arguments, continuation data, closure captures) | 1,745 |
| … `Data` (records, tuples, `Optional`, constructors) | 796 |
| … boxed `Nat`/`Int` (merged into one type by wasm-opt) | 436 (709) |
| … `Continuation` | 376 |
| … `List` (tree nodes) | 328 |
| … `Closure` | 309 |
| … `Foreign` (boxed JS values) | 135 |

What this says about the review's points:

- **Unboxing.** wasm-opt does unbox the easy cases, as the author says: boxed numbers fall
  39%, from 709 a row to 436. But all allocations fall only 8%, from 4,987 a row to
  4,572, because most are not number boxes. They are argument arrays, data and
  continuations. What is left of the boxes includes `Universal.compare`'s `Int` result
  and `Nat.+`'s sum, still allocated on most calls. wasm-opt's inlining cuts function
  entries by 41%.
- **Calls.** Known calls to ability-free functions are direct, as the author says. Direct
  code is 63% of function entries. The other 37% is continuation-passing code: every
  function that may perform an ability, which in a UI built on ink means most of it.
  Each of its returns goes through a continuation.

  There are 421 generic applications a row, 716 indirect calls, and 309 partial
  applications (`name`, which allocates a closure each time). These come from
  higher-order code, ink's and Proscenium's, passing closures around.
- **Handlers.** Each ability operation calls `shift`, which finds its handler by walking
  the frame list (`findFrame`). It then allocates four objects to capture the
  continuation. Resuming copies every frame between the operation and the handler
  (`attachFrame`). ink's handler then re-installs itself with `hnd`, five more
  allocations. warp special-cases none of this. A row performs 41 ability operations.

The functions that allocate most in the optimised module are:

- **`apply*`:** 352,000 per 1,000 rows, argument arrays.
- **`name`:** 309,000, partial applications.
- **`Universal.compare`:** 166,000, its boxed result.
- **`shift`:** 164,000.
- **`seqMkBranch`:** 138,000, list tree nodes.
- **`List.viewl` and `List.:+`:** 128,000 and 100,000.

Compiled Unison code allocates the rest, 2.75 million of the 4.57 million.

The meals page has the same shape, with 54,000–65,000 allocations per one-meal edit and
397,000 to plan the week. Ranked by what they would remove:

1. **The JS glue unwraps in wasm:** 80% of boundary crossings.
2. **Generic application and partial application allocate less:** 660 objects a row
   between `apply*` and `name`.
3. **Handlers that resume once, at the end, compile to direct calls:** `shift`'s and
   `hnd`'s 9 allocations per operation, 41 operations a row, plus the frame walk and copy.
4. **`Universal.compare` returns an unboxed result inside wasm, and `==` handles mixed
   function kinds:** 166,000 allocations and 4,011 JS calls per 1,000 rows.
5. **`Text.indexOf` and `Nat.toText` move into wasm.**

### Round 7: the boundary, after the review

Added 2026-10-30, after "Measured attribution". The branches are
`@dfreeman/warp/perf-r7` (from `perf-r4`, the warp under round 5) and
`@dfreeman/proscenium/perf-r7` (from `perf-r5m`, which is round 5 plus the meals page).
The scratch files are `unison/scratch/warp--perf-r7.u` and `proscenium--perf-r7.u`.

What changed, all in warp:

- **JS interop takes its arguments unboxed.**
  - `internal.Replacement.jsUnboxed` is a new kind of builtin. Its JS function receives
    a `Text` as the JS string, a `JSValue` as its wrapper, and a `Nat`, `Int` or
    `Float` as a JS number or `BigInt`. wasm boxes the result.
  - Round 4's 13 interop functions use it (`invoke*`, `getProperty`, `setProperty*`,
    `callback1_`), and so do `Nat.toText` and `Text.indexOf`. For `Text.indexOf` the
    `Optional` result is built in wasm.
  - The JS glue no longer calls exported getters to read its arguments, or constructors
    to build its result.
- **`==` compares a function with a closure by id in wasm,** on top of round 4's equality.
  - That is the comparison ink's skip check makes for every region it re-runs. It used to
    fall through to JS, which walked the values with eight calls back into wasm.
  - A first version of the change started from round 1's equality and dropped round 4's
    `List` and `Array` cases, sending those comparisons to JS. The boundary counts showed
    it at once: "update every 10th" went to 75,000 crossings. It was redone on round 4's
    code before any timing.
- **Results that can be shared are.**
  - `Universal.compare` returns one of three shared `Int` boxes.
  - `==` and every intrinsic with a `Boolean` result (`Nat.<`, `Int.==`, ...) return one
    of two shared `Boolean` boxes (`internal.Replacement.sharedValues`).
  - The interop functions that return nothing return a shared `()`, and `Text.indexOf`
    a shared `None`.

  Unison values are immutable and compared by value, so sharing a box changes nothing a
  program can observe.
- **`Text.size`, `Text.take` and `Text.drop` run in wasm,** over the `wasm:js-string`
  builtins `length` and `substring`, which V8 compiles inline. This is the first step of
  keeping JS strings as Unison's `Text` while moving its operations out of JS. They are
  not hot in these apps, and were added after the timings.

Checks:
- warp's `tests` pass.
- The rows table matches Leptos through 200 random operations on two seeds.
- The meals page matches through 240 steps on two seeds.
- The 400-card page matches round 5's markup after every step of its script.

**At the boundary** (`results/boundary-*.json`), calls in either direction:

| Operation | Leptos | Round 5 | Round 7 |
| --- | --- | --- | --- |
| rows, create 1,000 | 33,007 | 197,231 | **32,046** |
| rows, update every 10th | 103 | 4,125 | **122** |
| rows, swap | 11 | 234 | **44** |
| meals, plan the week | 3,785 | 22,490 | **3,775** |
| meals, shuffle a meal | 1,851 | 1,991 | **300** |
| meals, wave | 4 | 1,295 | **268** |
| cards-400, page ready | 652,880 | 57,562 | **10,883** |

warp now crosses the boundary about as often as Leptos, or less. The JS glue calls back
into wasm about 10 times per operation (the event's entry and the microtask flush), down
from 161,186 for creating 1,000 rows. The meals page's remaining imports are DOM calls and
`Text.indexOf`, which is still a JS call, now unboxed. It is called 240 times per run of
the search: a region's body runs whenever its parent renders, since only elements are
skip boundaries ("Measured attribution").

**Inside the module**, creating 1,000 rows after wasm-opt (`results/sites-rows-r7.json`,
taken before `Nat.toText`, `Text.indexOf` and the shared `()` changed):

- allocations fall from 4,572 a row to 4,356, a 5% cut;
- boxed numbers fall from 436 to 270;
- `Boolean`s drop out of the most-allocated types;
- swap allocates 12% less and "update every 10th" 7% less.

**Timings** (`results/round7-*.json`, medians of 10, load 4–5).
- **Method:** the implementations were run interleaved, one iteration of each in turn
  (`BENCH_INTERLEAVE=1`), so a change of load reaches all of them alike. Another session
  was building on the machine during the day, with the load between 17 and 37 at times,
  and an earlier run made that way had to be thrown away.
- **Build:** the round 7 build is the one with shared results, before `Nat.toText`,
  `Text.indexOf` and `()`.

| Operation (ms, until the DOM shows it) | Leptos | Round 5 | Round 7 |
| --- | --- | --- | --- |
| create 1,000 rows | 27.0 | 91.5 | **86.5** |
| replace 1,000 rows | 27.2 | 95.7 | **82.6** |
| append 1,000 rows | 21.5 | 59.1 | **45.8** |
| create 10,000 rows | 171.7 | 696.6 | **608.0** |
| clear 10,000 rows | 84.7 | 118.3 | 117.9 |
| swap two rows | 0.6 | 4.9 | 4.4 |
| remove a row | 1.0 | 5.6 | 5.2 |
| select a row | 0.6 | 0.9 | 0.6 |
| update every 10th | 0.9 | 6.3 | 7.9 |
| clear 2,000 rows | 17.7 | 22.5 | 42.4 |
| meals: plan the week | 5.1 | 11.3 | 10.8 |
| meals: bring back 240 search results | 2.1 | 9.8 | 9.3 |
| meals: shuffle a meal | 2.2 | 2.0 | 2.1 |
| cards-400: page ready | 271.2 | 94.5 | 92.5 |

What it shows:

- **Building lists got 5–23% faster.** That is consistent with the profile, which had about
  10 ms of create-1,000 in crossings. A second interleaved run of 15 gave the same
  picture: create 1,000 91.1 to 84.8 ms, replace 92.1 to 81.7, append 56.7 to 47.8,
  create 10,000 663 to 589.
- **Interactions are unchanged,** within the spread of 1–5 ms they had, since they
  crossed the boundary little before.
- **Clear 2,000 is slower in the suite and nowhere else.** In the suite it is 38–42 ms
  against 22–24 ms, in both interleaved runs, though round 7 allocates and crosses less
  for it (1.34 million allocations against 1.47 million, 43 crossings against 229).
  Timed alone, or after the same sequence of operations, it is the same in both:
  22.6 ms against 22.4, and 23.8 against 25.0. The cause is a garbage collection owed by
  the earlier operations, which now falls inside the clear. With a full collection forced
  before every operation (`BENCH_GC=1`, `results/round7-gc-rows.json`), the clear takes
  31.5 ms in round 5 and 31.3 in round 7. That run was at load 13–28, hence the higher
  numbers. "Update every 10th" has a wide spread (5–11 ms) and moved within it.
- **What is left is allocation and dispatch,** as "Measured attribution" said: 4,356
  allocations and 41 ability operations per row. Most of those come from how ink and
  Proscenium's code is compiled (argument arrays, data, continuations, closures). That
  is the work of "A tree of Proscenium's own" (`docs/ProsceniumTree.md`) and of warp's
  continuation handling, below.

#### Closed-world mode on a narrower boundary

The author expected closed-world wasm-opt to do much more once fewer types cross into JS.
Measured on round 7's rows module:

- **On the full boundary,** closed-world mode makes almost no difference: 142,980 bytes
  against 143,255 without it.
- **The module has 193 exports,** a constructor and getters for every kind of value.
  JS calls only 15 of them in any of the three suites, plus `main` and what the loader
  reads at start.
- **With the other 170 stripped** from a copy (`rows-bare-r7x`), closed-world mode drops
  50 of 202 types and 87 of 840 functions. The module shrinks to 142,298 bytes, 2.6%
  smaller under brotli, and the rows table still matches Leptos.
- **The runtime does not change** beyond noise (`results/round7-closed-world-rows.json`,
  10 interleaved runs).

The boundary was not what held wasm-opt back. Values live boxed in generic `Values`
arrays, and functions are called through `call_ref` and `apply*`. No whole-program
analysis can unbox a value stored in an array of `Value`, or inline a call through a
closure it cannot see. The gains are in how code is compiled, as in "Measured
attribution", rather than in what is exported. Shrinking the export list is still worth
doing in warp for size, by exporting only what the loader uses.

#### The meals search, behind a skip boundary

Proscenium's `region` is a key, not a skip boundary: its body runs whenever its parent
renders, and only elements are computations ink can skip. The meals page's search
filtered its 240 recipes in its region's body, so every root re-render filtered again: a
shuffle, a serving, the mascot's pose. The Leptos twin keeps its results in a `Memo` on
the query and does not. Moving the filter inside the `#search` element's body puts it
behind a boundary. That element's closure captures only the query, the catalog and the
listener, so an unrelated re-render skips it.

The change is `bench.meals.searchView` on Proscenium `perf-r7`, an app change only.
- **Check:** the page matches Leptos through 240 steps.
- **Crossings:** `Text.indexOf` calls for a shuffle fall from 240 to 0, and that
  operation's calls into JS from 283 to 43.

Medians of 10, interleaved, load 10–12 (`results/round7-search-meals.json`):

| Operation (ms) | Leptos | Round 7 | Round 7, filter moved |
| --- | --- | --- | --- |
| page ready | 24.7 | 50.9 | 42.2 |
| shuffle a meal | 2.3 | 2.1 | **0.9** |
| one more serving | 1.5 | 1.2 | **0.8** |
| remove a meal | 1.7 | 1.7 | **1.2** |
| check a grocery item | 0.6 | 0.9 | **0.6** |
| move a day (FLIP) | 2.3 | 1.9 | **1.4** |
| plan the week | 5.1 | 11.6 | 10.7 |
| type 7 keys | 2.4 | 7.3 | 6.7 |

- **Editing one meal now takes about half Leptos's time.**
- **Building many elements** (planning the week, typing, bringing back the results) is
  still 2–4 times Leptos.
- **For Proscenium users:** put work derived from state inside the element that shows
  it, not in the region around it. `docs/ProsceniumTree.md` proposes making the region
  the boundary instead.

#### In js-framework-benchmark

The author pointed to
[js-framework-benchmark](https://krausest.github.io/js-framework-benchmark/current.html) as
the suite people compare frameworks on.

- **The entry:** `bench/js-framework-benchmark/` holds a `frameworks/keyed/proscenium`
  entry for it. The app is `bench.jfb` on Proscenium `perf-r7`: the fine-grained rows
  app with the reference markup. The bundle is prebuilt, as the Rust entries' are.
- **Checks:** it passes the suite's keyed check and its smoke test. Like every wasm
  entry, it fails the suite's Content Security Policy (which leaves out
  `wasm-unsafe-eval`), and is flagged with issue 1139, as Leptos is.
- **The run:** the suite at commit `ca8715d` (2026-10-25), locally, in the devShell's
  headless Chromium 149, 10 iterations instead of the suite's 15. The machine's load was
  between 6 and 27, but the suite runs each benchmark across all frameworks in turn, so
  load drift reaches them alike.
- **Leptos's entry** is the suite's own, Leptos 0.7.0. The raw results are in
  `bench/js-framework-benchmark/results/round7/`.

The suite's time runs from the click to the end of the frame that paints the result. It
slows the CPU 16 times for partial update and 8 times for clear, so those are not
comparable with this report's other tables:

| Benchmark (median) | Proscenium r7 | Leptos 0.7.0 | vanillajs | stock Proscenium (3 runs) |
| --- | --- | --- | --- | --- |
| create 1,000 rows (ms) | 145.4 | 69.4 | 64.0 | 2,048 |
| replace all 1,000 rows | 177.1 | 78.7 | 70.2 | 24,492 |
| partial update, ×16 slowdown | 86.6 | 29.3 | 32.4 | 1,730 |
| select a row | **8.6** | 18.0 | 10.8 | 932 |
| swap two rows | 130.2 | 82.1 | 53.4 | 40,343 |
| remove a row | 93.8 | 61.8 | 48.3 | 561 |
| create 10,000 rows | 1,445.8 | 1,077.1 | 770.1 | 27,731 |
| append 1,000 to 1,000 | 255.6 | 121.9 | 107.5 | 2,654 |
| clear 1,000 rows, ×8 slowdown | 97.8 | 69.5 | 33.6 | 390 |
| first paint (ms) | **352.8** | 364.7 | 173.4 | 239.5 |
| memory when ready (MB) | **0.85** | 1.79 | 0.58 | 0.94 |
| memory with 1,000 rows (MB) | 15.3 | 5.4 | 1.9 | 18.6 |
| memory after creating and clearing, ×5 (MB) | **1.59** | 4.58 | 0.66 | 2.05 |
| size, uncompressed (KB) | 191.9 | 189.6 | 11.3 | 148.8 |
| size, compressed (KB) | 54.3 | 48.8 | 2.5 | 43.0 |

On the suite's own measure, round 7 is 1.3–3 times Leptos where lists change, and faster
where little does:
- **Selection is faster:** 8.6 ms against 18.0. `Selector` tells only the two rows whose
  state changed.
- **Startup is faster,** and lighter: first paint 353 ms against 365, and half the
  memory when ready.
- **Memory with 1,000 rows** is 2.8 times Leptos's. That is the allocation the counts
  above show, live while the rows are.
- **The shipped code** is about the same size.
- **Stock Proscenium** (`keyed/proscenium-stock`, 3 runs, for scale) takes 14–310 times as long as round 7 on the list operations: 2.0 s to create 1,000 rows, 40 s to swap two.
- **Stock paints first sooner,** at 240 ms against round 7's 353, with a smaller bundle (43 against 54 KB). The two apps also mount differently: stock into `body`, round 7 into `#main` through an interop call. Why round 7 starts slower has not been looked into yet.

**Against this report's harness.**
- **The totals are closer than ours:** paint takes about the same time in both
  frameworks (56–70 ms for 1,000 rows), and the suite counts it.
- **The script share is further apart:**
  - create 1,000: 79 against 13 ms;
  - swap: 53 against 3;
  - remove: 27 against 2.

  That is 6–17 times Leptos, against 3–7 times in our harness.
- **The likely reason is warm-up:** the suite repeats each operation several times
  before the measured run. With warp's allocation rate, a garbage collection owed by
  those repetitions falls inside the measured one. That is the effect found in our
  "clear 2,000" above, here on every benchmark.

The suite measures what a user would see. Our harness, with `BENCH_GC=1` when needed,
measures what each operation costs by itself, and its counters say why. Both stay.

#### Four ways to write a builtin

The author's reason for leaving builtins in JS was the effort of writing them by hand in
warp's instruction DSL. `Nat.toText`, called for every row's label, was written four
ways. Each version was timed formatting a million numbers of about 15 digits
(`bench.totext` on Proscenium `perf-r7`, `bench/frontend-wasm/totext.mjs`, median of 9,
interleaved, Node 24):

| Version | Branch | ms | Lines | Module |
| --- | --- | --- | --- | --- |
| JS, unboxed (`jsUnboxed`) | warp `perf-r7` | **40.5** | 1 | 19,251 B |
| JS through the old glue (`jsFunction`) | warp `perf-r4` (round 5) | 80.5 | 1 | 19,207 B |
| instruction DSL: `fromCharCode` per digit, `concat` | warp `perf-r7w` | 196.0 | 30 | 19,341 B |
| Unison, aliased in as the builtin | warp `perf-r7u` | 337.5 | 14 | 19,630 B |

- **Unboxed JS is the fastest** where the work is a JS primitive, here
  `String(BigInt)`.
- **The DSL version** builds a 15-digit number from 15 one-character strings and 15
  concatenations. Collecting the digits in an `i16` array and making one string with
  `fromCharCodeArray` should close most of that gap.
- **The Unison version** is the easiest to write and to test: an ordinary test against
  UCM's own `Nat.toText` passes on 210 samples. But warp boxes every intermediate `Nat`
  it computes, so it is the slowest.

So pure wasm pays where the work is arithmetic or data structure, as `compare`, `==` and
`List` did. A prelude of builtins written in Unison waits on warp keeping local
arithmetic unboxed.

Two things found on the way:
- **`termLink` in the same file:** an alias to a term defined in the same scratch file
  does not parse, so the Unison version is installed in two loads.
- **Builtin signatures:** V8 checks a builtin import's exact signature. `fromCharCode`
  and `concat` return a non-null `(ref extern)`, and a module declaring `externref` fails
  to instantiate. warp's test runner then waits forever for an answer.

#### Text by code point: a differential fuzz, and a bug in stock warp

Phase 3 of the plan asked for Unison's `Text` semantics to be pinned by a differential
test before more of `Text` moved into wasm. `tests.builtins.textFuzz` is modelled on round
4's list fuzz:
- **The operations:** 1,800 pseudo-random ones, from three seeds:
  - sizes and slices;
  - `reverse` and both directions of the char lists;
  - `indexOf`, `compare`, `repeat`, `split`;
  - case changes and UTF-8 round trips;
  - patterns, and a `match` on text literals.
- **The texts:** a pool seeded with ASCII, accented and CJK text, emoji, a skin-tone
  modifier, astral letters (𝔘𝔫𝔦𝔠𝔬𝔡𝔢), a combining mark and U+FF61.
- **The check:** each result is described by its UTF-8 bytes. The trace is computed
  natively in UCM and in wasm, and the test fails on the first line that differs.

**Stock warp 1.4.2 fails it within 24 operations on every seed.** Unison counts `Text` in
code points, and warp's JS builtins count UTF-16 units:

| | UCM | warp 1.4.2 |
| --- | --- | --- |
| `Text.size "a😀b"` | 3 | 4 |
| `Text.size "👍🏽 ok"` | 5 | 7 |
| `Text.take 2 "a😀b"` | `a😀` | `a` and half a surrogate pair |
| `Text.reverse`, `Text.toCharList` | by code point | `split('')`, which breaks pairs |
| `Text.indexOf` | code points | UTF-16 index |
| `Universal.compare`, `Text.<` | code point order | UTF-16 order: 😀 sorts below ｡ (U+FF61) |

The ordering difference has a consequence beyond `compare`:
- **How a `match` is compiled:** warp sorts the literals of a `match` on text by Unison's
  order when it builds the module (`BText.emit`). At run time it binary-searches them with
  `CompareStrings`, which was the UTF-16 `wasm:js-string` `compare`.
- **What breaks:** a match over `"a"`, `"｡"`, `"😀"`, ... can miss an arm whose literal
  is outside the Basic Multilingual Plane. A test of nine such literals passes natively
  and fails in wasm on 1.4.2.

Round 7's wasm versions of `size`, `take`, `drop`, `uncons`, `unsnoc` and `reverse`
had kept the UTF-16 semantics on purpose, to match the JS they replaced.

**The fix**, `@dfreeman/warp/offer-3-text`, is on 1.4.2 and stands alone:
- **The builtins:** `size`, `take`, `drop`, `uncons`, `unsnoc`, `reverse`, `toCharList`
  and `indexOf` work in code points.
- **Patterns:** the engine steps over a whole code point for a character class and a
  lookbehind.
- **`CompareStrings`:** now a wasm loop over `charCodeAt`. At the first difference it
  moves surrogates above U+E000–U+FFFF, which gives code point order. `Text.<` and its
  siblings call it, so a text `match` finds its arm.
- **`Universal.compare`:** its JS orders `Text` and `Char` by code point.

The fuzz and warp's full suite pass on it. On `perf-r7-142`, the same fix comes with round
7's wasm builtins rewritten as code point loops over `charCodeAt`. The text fuzz, the list
fuzz and warp's suite pass there too. Proscenium `perf-r7-142`, upgraded to it, still
matches Leptos on rows and meals, and its cards markup is unchanged at every step. The
time to the DOM is unchanged too (`results/round7-text-rows.json`,
`round7-text-meals.json`, interleaved, load 2–3), before and after:
- update every 10th: 7.2 and 5.5 ms;
- create 1,000: 82.6 and 83.4;
- planning the week: 9.6 and 10.0.

Two things found on the way, in warp's test harness, which waits forever instead of
reporting:
- the native side of a `wasmTestWithChannel` test failing;
- a JS exception thrown inside wasm, such as the `TypeError` from a JS builtin that
  returns a JS list where the module expects round 4's wasm list.

A Unison failure inside wasm is reported. So the fuzz compares on the native side and
sends the first difference back for the wasm side to fail on.

#### Every builtin moved, in one table

What each change to warp's builtins bought, from the measurements above. The rows app's
"create 1,000" is the common yardstick. A round that made several changes is credited as
a whole, since they were timed together.

| Builtins | Now | Branch | Measured |
| --- | --- | --- | --- |
| `Universal.compare`, `Universal.==` | wasm, with the JS as fallback | `perf` (round 1) | With ink's keyed fix, 2–4 times faster on every rows operation than the ink fix alone |
| `List`, all 14 primitives | wasm GC tree of 32-element arrays | `perf-r4` (round 4) | Round 4 as a whole: create 1,000 from 223.6 to 148.5 ms; a 9,000-operation differential fuzz passes |
| `List.:+` in place | wasm | `perf-r5` | No measurable change; not offered |
| 13 `JSValue` interop functions | JS, unboxed (`jsUnboxed`) | `perf-r7` | Crossings for create 1,000 from 197,231 to 32,046 (Leptos 33,007); create 1,000 91.5 to 86.5 ms, append 59.1 to 45.8 |
| `==` of a function against a closure | wasm | `perf-r7` | 4,011 JS calls removed from create 1,000 |
| results of `compare`, `==`, Boolean intrinsics, `()` | shared boxes | `perf-r7` | With the interop: allocations 4,572 to 4,356 a row |
| `Nat.toText` | JS, unboxed | `perf-r7` | 80 to 40 ms a million calls (DSL 196, Unison 338) |
| `Text.indexOf` | JS, unboxed, `Optional` in wasm | `perf-r7` | The meals search's 240 calls a run need no glue |
| `Text.size`, `take`, `drop`, `uncons`, `unsnoc`, `repeat`, `reverse`; `Char.toText`, `toNat`, `fromNat` | wasm over `wasm:js-string` | `perf-r7` | Not hot in these apps; no change in time |
| the same `Text` builtins, by code point; `CompareStrings`; `Text.<` and siblings | wasm loops over `charCodeAt` | `offer-3-text`, `perf-r7-142` | Correctness (the text fuzz passes); time to the DOM unchanged |
| `hnd`'s completion (runtime, not a builtin) | one shared global | `perf-r7` | Allocations 4,356 to 4,198 a row |

**Closed-world mode, before and after the boundary moved** ("Closed-world mode on a
narrower boundary"):
- **On the full boundary:** 0.2% smaller.
- **With the exports only JS builtins used stripped:** 2.6% smaller under brotli, with 50
  fewer types and 87 fewer functions.
- **Speed:** unchanged either way.

The boundary was not what held wasm-opt back: values stay boxed in generic arrays and are
called through `call_ref`.

### A floor for a tree without ink

`docs/ProsceniumTree.md` proposes a tree of Proscenium's own in place of ink. Before
building that behind Proscenium's API, we measured the floor: how fast a UI on warp can
be with no ink and no handler per element. `bench.mini`, on Proscenium `perf-r7-mini`
(from `perf-r7`, on warp r7f), is a keyed virtual DOM in about 200 lines of plain Unison:

- **The view:** plain data. An element is a tag, a key, attributes, listeners (an event and
  a message) and children. A node can also be a text node or a memo. A memo is a key, an
  input and a view, and it is redrawn only when its input differs, as Elm's `Html.Lazy`
  is.
- **The update:** Elm's. A listener sends its message, `update` makes a new model, and
  the new view is patched onto the DOM at once.
- **Children:**
  - matched by position when no keys changed;
  - otherwise, the common prefix and suffix are patched in place;
  - what is left goes through a keyed reconcile, with ink's longest-increasing-run
    `stableIndices` deciding the moves.
- **The app:** the rows app is written twice on the same renderer, as data (`mini`) and
  through an `Html` ability whose one handler collects the nodes (`mini-h`). The second
  has the shape of Proscenium's `Render`, with one handler where Proscenium today has its
  own and ink's.

Both pass `consistency.mjs` against Leptos over 100 random steps.

Timed with `BENCH_INTERLEAVE=1`, medians of 11, until the frame after the DOM shows the
end state (`results/round7-mini-rows.json`). The load was 15–23 from another session's
build, so the absolute times are higher than in other tables. The ratios are what to
read.

| Operation (ms) | Leptos | Round 7 | Floor, data | Floor, one handler |
| --- | --- | --- | --- | --- |
| create 1,000 rows | 76.2 | 150.1 | **93.8** | 106.1 |
| replace 1,000 rows | 79.3 | 158.7 | **72.0** | 81.5 |
| append 1,000 rows | 89.5 | 131.0 | **98.3** | 109.2 |
| update every 10th row | 14.2 | 22.0 | **16.8** | 21.5 |
| select a row | 10.9 | 7.5 | **10.5** | 11.6 |
| swap two rows | 20.3 | 17.1 | **24.6** | 19.2 |
| remove a row | 21.3 | 21.1 | **17.4** | 18.9 |
| clear 2,000 rows | 24.7 | 46.7 | **18.7** | 21.2 |
| create 10,000 rows | 812.3 | 1,177.0 | **756.0** | 940.2 |
| clear 10,000 rows | 111.2 | 144.7 | **80.9** | 86.7 |
| JS heap at 10,000 rows (MB) | 9.6, plus 21.8 linear | 151.9 | **43.8** | 43.7 |

The counters, for creating 1,000 rows (`results/sites-rows-mini.json`,
`results/boundary-rows-mini.json`):

| | Round 7 | Floor, data | Floor, one handler |
| --- | --- | --- | --- |
| allocations a row | 4,198 | 1,041 | 1,431 |
| handler operations a row | 41 | 0 | 11 |
| generic applications a row | 421 | 61 | 138 |
| boundary crossings | 32,046 | 33,003 | 33,003 |

And for the build:

| | Round 7 | Floor, data | Floor, one handler | Leptos |
| --- | --- | --- | --- | --- |
| module, brotli | 43 KB | 18 KB | 19 KB | 47 KB |
| loader, brotli | 11.6 KB | 11.6 KB | 11.6 KB | 5.4 KB |
| terms warp emits | 526 | 179 | 193 | |
| warp's build | 0.77 s | 0.24 s | 0.27 s | |

What this says:

- **Most of round 7's remaining cost is the libraries.** On the same warp, the same
  runtime and the same DOM calls, dropping ink and Proscenium cuts allocations by three
  quarters and creation time by about 37%. That puts creation at 1.2 times Leptos, and
  replacing, clearing and creating 10,000 rows ahead of it.
- **An ability-based API costs something, but not most of it.** One handler, one
  operation per element: 11 operations and 390 allocations a row more than plain data,
  13–24% more time to create rows. That is the shape a tree of Proscenium's own behind
  the current API would have. It is still well ahead of round 7's 41 operations a row.
  Phase 4's tail-resumptive path would narrow it further: these 11 operations are exactly
  the shape it targets.
- **Most of the size is Proscenium's and ink's code.** Without them, the module is
  18 KB brotli against round 7's 43 KB, and warp emits 179 terms instead of 526, in a
  third of the time. (An earlier version of this section said 139 KB and 2,884 terms;
  those were the cards app's figures, read from the wrong line of the build log.)
- **A virtual DOM still pays for the whole view on every message.** A click rebuilds all
  1,000 memo nodes and compares their inputs:
  - **select a row:** 70,000 allocations against round 7's 2,900, since round 7's
    `Selector` touches two rows;
  - **swap two rows:** the general keyed path, at 768,000 allocations against 362,000.

  The times stay close because paint dominates both, but a Proscenium tree should keep
  `Keyed` and `Selector`'s targeted updates rather than diff a whole view.
- **Three things the floor needed:**
  - **The memo.** Without it, every interaction took 45–70 ms (`results/round7-mini-first-rows.json`,
    load 9–11).
  - **The two fast paths for children.** Without the prefix and suffix trim, removing a
    row allocated 829,000; with it, 76,000.
  - **One lookup of `document`.** `global "document"` goes through the boxed glue, and
    looking it up per node made 30,000 extra crossings for 1,000 rows.

### A first prototype behind Proscenium's API

`bench.tree`, on Proscenium `perf-r7-tree` (from `perf-r7-mini`), puts the floor's lessons
behind Proscenium's own `Render` API. `docs/ProsceniumTree.md`, "A first prototype behind
the API", has the design:
- **Handlers:** one, where Proscenium and ink have two.
- **Skipping:** a memo per element of its name, modifiers and body closure, which is
  Proscenium's skip.
- **Cells:** kept by path, and reached through `Update.send`.
- **Reconcile:** the floor's, with a swap fast path.

**The plain rows app, `bench.rows.ui`, runs on it unchanged.** It matches Leptos over 200
random steps on two seeds. Its source is the same as on Proscenium with ink, so the
comparison is the renderer alone. Round 7's fine-grained rows app needs `Keyed` and
`Selector`, which the prototype does not have yet.

Timed interleaved, medians of 9, load 4–6, until the DOM shows the result
(`results/round7-tree-rows.json`):

| Operation (ms) | Leptos | Round 7 (fine-grained) | Plain rows on ink | **Plain rows on the tree** |
| --- | --- | --- | --- | --- |
| create 1,000 rows | 26.3 | 84.8 | 81.0 | **55.2** |
| replace 1,000 rows | 27.7 | 87.7 | 76.6 | **47.1** |
| append 1,000 rows | 21.1 | 52.1 | 47.2 | 47.7 |
| update every 10th row | 0.9 | 6.4 | 9.3 | **5.8** |
| select a row | 0.6 | 1.3 | 7.7 | 6.2 |
| swap two rows | 0.6 | 5.1 | 5.8 | **3.0** |
| remove a row | 0.9 | 5.0 | 6.6 | **2.3** |
| clear 2,000 rows | 16.3 | 34.6 | 21.0 | **15.1** |
| create 10,000 rows | 167.1 | 571.0 | 511.9 | **317.8** |
| clear 10,000 rows | 84.3 | 114.5 | 69.5 | **60.0** |
| JS heap at 10,000 rows (MB) | 9.6, plus 21.8 linear | 153.2 | 123.4 | **93.6** |

The counters, for creating 1,000 rows (`results/sites-rows-tree.json`,
`results/boundary-rows-tree.json`):

| | Plain rows on ink | Plain rows on the tree |
| --- | --- | --- |
| allocations a row | 3,511 | 2,344 |
| handler operations a row | 31 | 11 |
| boundary crossings | 32,026 | 32,003 |
| update every 10th, allocations | 617,630 | 336,614 |
| swap, allocations | 398,543 | 194,431 |
| module, brotli | 40 KB | 24 KB |
| terms warp emits, and its build | 484, 0.54 s | 267, 0.32 s |

What this says:
- **Keeping the API keeps most of the floor's gain.** Against ink on the same source,
  creating rows takes 32–39% less time and small interactions 38–65% less.
- **The gap to the floor is the API's cost:** a handler operation per element, a memo
  input per element, and cells looked up by path. The floor creates 1,000 rows in 38.7 ms
  (in the first run of this comparison, `round7-tree-first-rows.json`) against the
  tree's 54.4.
- **Select is not better,** because this app keeps the selection in its model and every
  click re-runs the table's body. Round 7's `Selector` store is what makes it cheap, so
  the stores are the next part to bring over.
- **Without the swap fast path,** the general keyed reconcile over 998 rows, with keys
  that are paths of `Any` segments, made swap slower than ink (14.0 against 8.1 ms in the
  first run).

#### The fine-grained rows app, with its provider

Round 7's own rows app, `bench.rowsfg.ui`, keeps each row's label in a `Keyed` store and
the selection in a `Selector`, both provided by a `Provider`. To run it, the tree gained
three things:
- **Abilities:** it is polymorphic in the UI's abilities.
- **A coroutine:** render and event handling run inside `Provider.run`, paused with
  Proscenium's own `Yield` between events, as a `Session` is. The provider's state lives
  on between events.
- **Redraw by owner:** a message to a cell redraws only the element that owns it. Each
  element that uses a cell is registered with a cell holding what it drew, so its view
  can run again on its own. ink does the same with the computation that owns a cell. A
  cell at the root still draws the whole UI.

`bench.rowsfg.ui` runs on it unchanged, with its provider, and matches Leptos over 200
steps on two seeds. Interleaved, medians of 9, load 9–17, to the DOM
(`results/round7-treefg-registered-rows.json`):

| Operation (ms) | Leptos | Fine-grained rows on ink (round 7) | **Fine-grained rows on the tree** |
| --- | --- | --- | --- |
| create 1,000 rows | 26.6 | 80.5 | **70.9** |
| replace 1,000 rows | 28.4 | 89.8 | **57.1** |
| append 1,000 rows | 22.1 | 57.1 | 59.1 |
| update every 10th row | 0.9 | 5.8 | 9.0 |
| select a row | 0.6 | 0.6 | 0.6 |
| swap two rows | 0.6 | 6.1 | **1.9** |
| remove a row | 1.0 | 5.6 | **1.7** |
| clear 2,000 rows | 16.6 | 34.5 | **19.9** |
| create 10,000 rows | 169.7 | 593.4 | **460.2** |
| clear 10,000 rows | 82.8 | 122.1 | **65.0** |
| JS heap at 10,000 rows (MB) | 9.6, plus 21.8 linear | 152.3 | 144.4 |

What this says:
- **Selection is as cheap as on ink,** 0.6 ms. Before owners were redrawn on their own,
  a selection redrew the table from the root and took 15 ms
  (`round7-treefg-first-rows.json`).
- **Most operations are faster than round 7 on ink.** The exceptions are append, which
  is level, and update every 10th.
- **Update every 10th is slower,** 9.0 against 5.8 ms. It allocates less than ink
  (260,688 against 349,244, `results/sites-rows-tree.json`), but it calls warp's
  `compareValues` 148,679 times. The cells, the dirty marks and the registry are maps and
  sets keyed by paths, and each lookup compares lists of `Any` segments.

  A filter that compared the 100 changed owners in pairs was one part of the cost. It
  now looks owners' prefixes up in a set, which took the ratio to ink from 1.55 to 1.35
  at load 19–30 (`round7-treefg-rows.json`).

  The next change is to intern each path as a number when it is first seen, so those
  maps compare integers.
- **The cost of registering owners** is a map entry per row, which the build of 10,000
  rows pays: its heap is 144 MB here against 94 MB for the plain app on the tree.

### One-shot continuations: what resumes twice

The author hopes native wasm stack switching will let warp drop its CPS paths, at the
cost of multi-shot continuations. So the question for these libraries is whether anything
resumes a continuation twice.

**The guard** (`@dfreeman/warp/guard-one-shot`, from `perf-r7`) makes every continuation
warp captures one-shot. `shift::continue`, which runs on every resume, overwrites its
first data slot once it has read it. A second resume of the same continuation then
fails a cast and traps. It catches every handler in the program: Proscenium's, ink's,
base's and the app's.
- **A handler that resumes twice** (`tests.guard.twice`) traps under the guard, and
  passes without it.
- **Proscenium and ink resume nothing twice.** Proscenium `perf-r7-guard` is `perf-r7` on
  the guarded warp. Under it:
  - the rows table matches Leptos over 200 random steps on two seeds;
  - the meals page matches over 120 steps on two seeds, with no page errors;
  - the cards page matches round 7's markup at every step;
  - every operation of the rows, meals and cards timing suites completes.
- **`app.Session`,** the one candidate found by reading, stores `Yield.run`'s
  continuation and resumes it once. Its three callers each thread the session through
  once, and the browser's `flush` is never re-entered, since an action schedules a
  microtask.
- **What does resume twice is base's `Each`,** nondeterminism, multi-shot by design.
  warp's own suite traps under the guard in `Each.count.tests` and in `Random` tests built
  on `test.prop`, which samples with `Each.rangeClosed`, each time after 36 passing tests.
  The harness stops at the first trap, so the rest of the suite was not inventoried.
- **Proscenium's and ink's own tests** run natively in UCM, not on warp, so the guard does
  not reach them.

So one-shot stack switching is enough for these UI libraries. A program using `Each`
would keep a CPS fallback for that handler. The handlers that are safe can be told
apart syntactically, as `docs/TailResumptive.md` marks tail-resumptive ones: each
clause uses `resume` at most once and never stores it. `Yield.run` fails that check
because its `resume` escapes into data, although it is resumed once.

### Next experiments, by expected payoff

Re-ranked on 2026-10-30. Two earlier items are dropped: ahead-of-time unboxing, which
wasm-opt already does where it is easy, and direct calls for ability-free functions,
which warp already makes. Two are done: the attribution ("Measured attribution") and the
boundary (round 7).

1. **Proscenium: a tree of its own instead of ink,** the author's preferred direction,
   behind the current API (`docs/ProsceniumTree.md`). Each element is two ability
   operations today, one Proscenium's and one ink's, plus ink's records, keys and `Delta`
   values. The floor ("A floor for a tree without ink") says this is where most of the
   remaining cost is: a quarter of the allocations, and 37% less time to create rows.
2. **warp: continuation handling.**
   - Compile a handler that resumes once, in tail position, as a direct call.
     ink's `reconcile.handler`, which every element goes through, has that shape: it
     resumes once and re-handles with new state. Each operation now costs a frame-list
     walk, 4 allocations to capture, a copy of the frames on resume, and 5 to re-handle.
   - A cheaper entry for calls in from JS than `callDirect`'s root continuation is
     not worth it in these apps. Every operation makes 7 calls in, and an animated move
     makes 100 over 31 frames, against thousands of allocations per operation.
   - Native stack switching later. One-shot continuations are enough for Proscenium
     and ink ("One-shot continuations: what resumes twice").
3. **warp: the rest of the builtins in wasm,** `Text`'s operations over the
   `wasm:js-string` builtins first, then closed-world mode measured again on the narrower
   boundary.
4. **ink: an index of children by segment** in each record, so that delivering a message
   costs `O(log n)` instead of a walk of all the siblings. This is for update every 10th
   and select, and is superseded if Proscenium stops using ink.
5. **The dev loop.** Build a `CodeCache` base module that exposes an async `hotSwap`,
   then on every edit:
   1. On the host, build a delta with `warp.incremental`, from the build record kept on
      disk between runs.
   2. Serialise the new UI value.
   3. In the page, `loadCompiledTerms` the delta, `loadValue` the UI, and call
      `Root.render`.

   The pieces are all measured. A one-card delta takes 20–39 ms and is 10–25 KB; an
   edit's typecheck and `update` take about 1.5 s plus 0.3–1.2 s; UCM adds 2.5 s per
   `run`. That puts edit-to-page at about 4–5 s, whatever the app's size, against 7 s
   at 400 cards and 40 s at 1,600 for a Leptos dev build.

## Where things are

- `bench/frontend-wasm/` holds:
  - `bench.nu`: builds and size measurement.
  - `round3.nu`, `round4.nu`, `round4/`: generators of the scratch files other agents
    wrote in rounds 3 and 4 (`gen-warp-list.nu`, `gen-ink-r4.nu`, `gen-warp-js.nu`,
    `gen-proscenium-r4.nu`), with their UCM transcripts `round3.md` and `round4.md`.
  - `round5.nu`: writes the flush that times reconcile against DOM sync, and the
    transcript that builds a timed rows app (self-test: `nu bench/frontend-wasm/round5.nu self-test`).
  - `phases.mjs`: reconcile and DOM-sync time per rows operation, from such a build.
  - `cards-check.mjs`: the card page's markup after each step of a toggle script, per
    build.
  - `gen-cards.nu`: the scaling app, in both languages.
  - `runtime.mjs`: the browser timings.
  - `profile.mjs`: CPU profiles.
  - `consistency.mjs`: the table-for-table check.
  - `meals-check.mjs`: the same check for the meals page.
  - `boundary.nu`: summarises `BENCH_COUNT=1` runs of `runtime.mjs`, which count every
    call between wasm and JS.
  - `instrument.nu` and `sites.nu`: put counters into a copy of a module (function entries,
    allocations, indirect calls, runtime helpers) and summarise them.
  - `totext.mjs`: times a builtin's implementations against each other in Node
    (`Nat.toText`: JS, unboxed JS, Unison, instruction DSL).
- `bench/js-framework-benchmark/`: the Proscenium entry for js-framework-benchmark
  (`keyed-proscenium/`), `install.nu` to put it into a checkout, and `summary.nu` to
  tabulate a run.
- `docs/ProsceniumTree.md`: the design note for a tree of Proscenium's own in place of ink.
- `docs/ReviewResponse.md`: the summary of the work since the author's review.
  - `leptos/`: the Rust copies.
  - `results/*.jsonl`: every measurement, with its load average.
  - `results/round*-*.json` and `.log`: per-round runs and consistency checks.
    `round5-final-rows.json` is the summary's table, `round5i-runtime-rows-15.json` the
    15-run comparison, and `round5-final2-rows.json` the run with `perf-r5k`.
    `runtime.jsonl` has them all.
- `unison/scratch/`: the Unison changes and apps, one file per branch step, named
  `<project>--<branch>.u`. Rounds 3 and 4 are generated by `round3.nu` and `round4.nu`
  into `target/unison/frontend-bench/`.
- `docs/UnisonSteps.md`: the order in which to load them, and which branches to push.
- Unison, in the benchmark codebase (`target/unison-bench-codebase`, a copy of a UCM
  codebase made on 2026-10-28; open it with `ucm -c`), whose branches the README links
  to:
  - the bench code on `proscenium/bench`, and the generated card apps
    (`bench.cards.s25`, `s100`, `s400`, `s1600`)
  - `ink/perf` (2.0.1 plus both ink changes), `ink/perf-mount-compute`, `ink/perf-r4`
    (its junk `>` removed in round 5) and `ink/perf-r5`
  - `warp/perf` (1.3.0 plus `compare` and `==` in wasm), `warp/perf-r4` and
    `warp/perf-r5` (appends in place, with the fuzz and sharing tests)
  - the Proscenium chain `perf` → `perf-compare` → `perf-eq` → `perf-keys` →
    `perf-targeted` → `perf-fine` → `perf-mount-compute` → `perf-r4` → `perf-r5` →
    `perf-r5i` (round 5's sync on ink `perf-r5`: the "Round 5" column) → `perf-r5k`
    (single-pass key counts) → `perf-r6` (on warp `perf-r5`, appends in place); the
    rows app is `bench.rowsfg` and the 400 stateful cards `bench.cards.s400i`

  The report writes branch names as `@dfreeman/<project>/<branch>`, as they were named in
  the benchmark codebase, where the projects are clones of the upstream ones. The
  published branches have the same names under another owner; see the README.

## How to rerun

From the repository root, with `nu`, `cargo`, `wasm-pack`, binaryen, esbuild, `ucm` and Chromium available (the author used a Nix dev shell):

```sh
nu bench/frontend-wasm/gen-cards.nu 400            # Rust and Unison card apps
nu bench/frontend-wasm/bench.nu leptos cards --name cards-400
nu bench/frontend-wasm/bench.nu warp cards-400      # needs the compiled .uc entry
nu bench/frontend-wasm/bench.nu warp rows --variant r4           # Round 4 full app
nu bench/frontend-wasm/bench.nu warp-incremental 400
BENCH_VARIANTS=mount,r4-list,r4-ink,r4 BENCH_IMPLS=leptos,warp-mount,warp-r4-list,warp-r4-ink,warp-r4 node bench/frontend-wasm/runtime.mjs rows 5
node bench/frontend-wasm/consistency.mjs leptos/rows-release warp/rows-bare-r4 60 11
node bench/frontend-wasm/consistency.mjs leptos/rows-release warp/rows-bare-r4 80 23
node bench/frontend-wasm/profile.mjs warp warp/rows-named-perf create1k
# Round 5
nu bench/frontend-wasm/bench.nu warp rows --variant r5i         # needs rows-build-r5i.uc
nu bench/frontend-wasm/bench.nu warp cards-400 --variant r5i    # needs cards-400-build-r5i.uc
BENCH_VARIANTS=r4,r5i BENCH_IMPLS=leptos,warp-r4,warp-r5i node bench/frontend-wasm/runtime.mjs rows 10
BENCH_VARIANTS=fine,mount,r4,r5 BENCH_IMPLS=leptos,warp-fine,warp-mount,warp-r4,warp-r5 node bench/frontend-wasm/runtime.mjs rows 5
BENCH_VARIANTS=fine,r4,r5 BENCH_IMPLS=leptos,warp-fine,warp-r4,warp-r5 node bench/frontend-wasm/runtime.mjs cards-400 5
# Round 5 with the meals page (perf-r5m; see docs/UnisonSteps.md for its compile line)
nu bench/frontend-wasm/bench.nu leptos meals
nu bench/frontend-wasm/bench.nu warp meals --variant r5i       # needs meals-build-r5i.uc
node bench/frontend-wasm/meals-check.mjs leptos/meals-release warp/meals-bare-r5i 120 7
BENCH_VARIANTS=r5i BENCH_IMPLS=leptos,warp-r5i node bench/frontend-wasm/runtime.mjs meals 10
nu bench/frontend-wasm/round5.nu perf-r5 r5   # then run the printed transcript with transcript.fork
node bench/frontend-wasm/phases.mjs warp/rows-bare-r5t 5
node bench/frontend-wasm/cards-check.mjs leptos/cards-400-release warp/cards-400-bare-r4 warp/cards-400-bare-r5
# Measured attribution (2026-10-30): boundary counts, then site counts on instrumented copies
BENCH_COUNT=1 BENCH_VARIANTS=r5i BENCH_IMPLS=leptos,warp-r5i node bench/frontend-wasm/runtime.mjs rows 1
nu bench/frontend-wasm/boundary.nu rows
ucm run.compiled target/unison/frontend-bench/rows-build-r5i.uc -- debug target/frontend-bench/warp/rows-debug-r5i
wasm-opt -g target/frontend-bench/warp/rows-debug-r5i/rows-debug.wasm -o target/frontend-bench/warp/rows-debug-r5i/rows-debug.opt.wasm <warp's flags, as in bench.nu>
nu bench/frontend-wasm/instrument.nu target/frontend-bench/warp/rows-debug-r5i/rows-debug.wasm target/frontend-bench/warp/rows-bare-r5iraw/rows-bare.opt.wasm
nu bench/frontend-wasm/instrument.nu target/frontend-bench/warp/rows-debug-r5i/rows-debug.opt.wasm target/frontend-bench/warp/rows-bare-r5iopt/rows-bare.opt.wasm
# (copy rows-debug.loader.js, minified, to both as rows-bare.loader.min.js)
BENCH_COUNT=1 BENCH_VARIANTS=r5iraw,r5iopt BENCH_IMPLS=warp-r5iraw,warp-r5iopt node bench/frontend-wasm/runtime.mjs rows 1
mv bench/frontend-wasm/results/boundary-rows.json bench/frontend-wasm/results/sites-rows.json
nu bench/frontend-wasm/sites.nu rows
nu bench/frontend-wasm/sites.nu rows --by-function --operation "create 1k" --top 20
```

The round 5 build entries were compiled in the bench codebase with
`@dfreeman/proscenium/perf-r5i> compile bench.rowsfg.build target/unison/frontend-bench/rows-build-r5i`
and `compile bench.cards.s400i.build target/unison/frontend-bench/cards-400-build-r5i`
(the same on `perf-r5` for `-r5` and `perf-r4` for `-r4`); `round5.nu perf-r5i r5i`
writes the timed build's transcript. The `List` fuzz test runs as
`@dfreeman/warp/perf-r4> load unison/scratch/warp--perf-r4.u`, `add`,
`run tests.builtins.listFuzz.suite`, with binaryen 133 first on the PATH.

The warp entries are compiled in the bench codebase. Load
`target/unison/frontend-bench/cards-<N>.u` there, split into files of about 400 cards
above that size, then `compile bench.cards.s<N>.build` (see `load-cards.md` and
`load-1600.md` for the exact transcripts). A Leptos build of more than about 1,000
cards needs `RUSTFLAGS="-C link-arg=-zstack-size=8388608"` to mount.
