# After the review: what was tried, and what it showed

This is for the author of warp and Proscenium. It follows their review of 2026-10-30 and
summarises the work done since. The details are in `docs/REPORT.md` ("Review from the
author", "Measured attribution", "Round 7" and the sections after it),
`docs/ProsceniumTree.md` and `docs/TailResumptive.md`. Nothing here assumes it will be
taken.

## What to take, if you want it

Each of these is one branch on the current release, with its tests and release notes in
the library's own terms. Each stands alone unless it says otherwise.

- **ink `offer-1-ordering`** (on 2.0.1): the keyed reconcile in `O(n log n)`, and the fix
  for a new child left behind when its predecessor moves. Its two regression tests fail
  on 2.0.1. This is the one that affects every Proscenium user today.
- **warp `offer-3-text`** (on 1.4.2): `Text` counted and ordered by code point, as Unison
  does. On 1.4.2 an emoji is two characters, and a text `match` can miss its arm. It
  comes with a differential text fuzz.
- **warp `offer-1-compare-eq`, then `offer-2-list`** (on 1.4.2, stacked): `compare` and
  `==` in wasm, then `List` as a wasm tree of arrays.
- **warp `perf-r7-142`** (on 1.4.2): all of the warp work, with the unboxed JS builtins
  and shared result boxes on top of the two above, and the text fix.
- **Proscenium `offer-stores`** (on 0.4.3): the `Keyed` and `Selector` stores, which make
  a selection or a row's label update re-render only the rows involved.

And two directions to decide on, with the measurements below:
- **A tree of Proscenium's own in place of ink.** A first prototype runs both rows apps
  unchanged, and the 400-card page. It beats ink on every operation of the fine-grained
  rows app except append, where it is 5% slower.
- **One-shot stack switching.** It would be enough for ink and Proscenium: nothing in
  them resumes a continuation twice.

The branches the benchmark started from are against warp 1.3.0, Proscenium 0.4.3 and ink
2.0.1. The table at the end lists them all.

## Two corrections

The review was right on both points, and the report now says so:

- **Unboxing.** wasm-opt already unboxes the easy cases. Measured: it removes 39% of number
  boxes. But that is 8% of all allocations, because most allocations are argument arrays,
  data and continuations.
- **Calls.** warp already calls a known ability-free function directly; continuation-passing
  code is 37% of function entries. The profile's "`callDirect`, `apply*`" time was calls
  in from JS and closures applied generically, not every call. `callDirect` is the entry
  from JS.

## Measuring before changing

Chromium's profilers can't see allocation inside wasm, so two counters were added. Neither
changes warp.

- **At the boundary** (`BENCH_COUNT=1` in the harness): every import and export is wrapped
  at instantiation, and each call back into wasm is labelled with the JS import that made it.
- **Inside the module** (`bench/frontend-wasm/instrument.nu`): a copy of the module is
  rewritten through `wasm-tools`, with a counter before every function entry, allocation,
  `call_ref` and runtime-helper call.

Creating 1,000 rows on round 5 made:

- **Boundary crossings:** 197,231, against Leptos's 33,007. 161,186 of them were the JS
  glue calling back into wasm for `Text_getValue`, `Foreign_getValue`, `Foreign` and `Unit`.
- **`==` in JS:** 4,011 calls, each a function compared with a closure. Round 1's wasm
  equality handled only same-kind values.
- **Per row:** 4,572 allocations, 41 ability operations and 421 generic applications.

## Round 7: the boundary

On `@dfreeman/warp/perf-r7` (from `perf-r4`):

- **`internal.Replacement.jsUnboxed`:** a JS builtin whose function receives strings,
  `JSValue` wrappers and numbers unboxed, with the result boxed in wasm. The 13 interop
  functions, `Nat.toText` and `Text.indexOf` use it.
- **`==`:** compares a function with a closure by id in wasm.
- **`internal.Replacement.sharedValues`:** `compare`, `==` and the Boolean intrinsics
  return shared boxes, and so do interop calls that return nothing.

Results:
- **Checks:** warp's tests pass and all three consistency checks pass.
- **Boundary:** creating 1,000 rows now crosses 32,046 times, against Leptos's 33,007.
- **Speed:** lists build 5–23% faster. Interactions are unchanged.

## What is left, and the direction you suggested

At 4,356 allocations and 41 ability operations a row, the rest is structural.
`docs/ProsceniumTree.md` takes your suggestion of replacing ink:

- **Where ink sits today:** all of Proscenium's use of ink goes through `dom.internal.render`.
- **What that costs:** each element is two ability operations, Proscenium's `Render.node`
  and then ink's `compute_`. On top of those come ink's keys, records and `Delta` values.
- **The note:** a tree of Proscenium's own, behind the current API, with one handler.

In warp, nothing special-cases a handler that resumes once in tail position. Every
operation is:
- `shift`: a walk of the frame list and 4 allocations;
- a copy of the frames on resume;
- `hnd`: 5 allocations to re-handle.

ink's handler, which every element goes through, has that tail-resumptive shape. As far as
we could find, nothing in ink or Proscenium resumes a continuation twice. The one place it
could happen is a `Session`, which holds its continuation as a value.

## js-framework-benchmark

`bench/js-framework-benchmark/` is a `frameworks/keyed/proscenium` entry:
- **App:** `bench.jfb`, with the reference markup.
- **Bundle:** prebuilt, as the Rust entries do.
- **Stock variant:** `keyed/proscenium-stock`, on `bench-jfb`.
- **Checks:** both pass the suite's keyed check. Like Leptos, the entries are flagged with
  issue 1139 for the suite's CSP.

A local run (10 iterations, Chromium 149) puts round 7 against Leptos 0.7.0's entry at:

- **Lists:** 1.3–2.3 times Leptos on the suite's totals, which include paint.
- **Select:** 8.6 against 18.0 ms, faster than Leptos.
- **First paint:** 353 against 365 ms.
- **Memory:** 0.85 against 1.79 MB when ready, and 15.3 against 5.4 MB with 1,000 rows.
- **Size:** 54 against 49 KB compressed.
- **Stock, for scale:** stock Proscenium 0.4.3 in the same suite takes 2.0 s to create
  1,000 rows and 40 s to swap two.

On the meals page, a meal edit now takes about half Leptos's time. Part of that came from
an app change the counts pointed to. A `region` is a key, not a skip boundary: its body
runs with its parent's render, and only elements are skipped. So the search's filter
moved inside its element.

The report's "In js-framework-benchmark" section has the full table and how it relates to
the harness's numbers.

## Writing builtins: four ways, timed

Your reason for leaving builtins in JS was the work of writing them by hand. `Nat.toText`
was written four ways and timed on a million calls:

| Version | Time |
| --- | --- |
| unboxed JS (`jsUnboxed`) | 40 ms |
| the old JS glue | 80 ms |
| your DSL, one `fromCharCode` per digit and `concat` | 196 ms |
| plain Unison, aliased in with `termAlias` | 338 ms |

- **Unison** is the easiest to write and to test, but slow until warp keeps local
  arithmetic unboxed.
- **The DSL** would need an `i16` array and `fromCharCodeArray` to compete.

So for builtins whose work is a JS primitive, unboxed JS is the fast path today. Pure wasm
paid off for `compare`, `==` and `List`.

## The branches

| Branch | What it is | Worth taking? |
| --- | --- | --- |
| ink `perf` | O(n log n) keyed reconcile, which fixes the ordering bug after a move and an insert | Yes: the bug affects every Proscenium user |
| ink `offer-1-ordering` | the same reconcile and fix alone on 2.0.1, without `compute_`, with two regression tests that fail on 2.0.1 | Yes: the way to take the fix |
| ink `perf`, `perf-mount-compute`, `perf-r4`, `perf-r5` | `compute_`, no diff on first mount, fast paths, children by position | If ink stays |
| warp `perf` | `Universal.compare` and `==` in wasm | Yes |
| warp `perf-r4` | `List` as a wasm tree of arrays (with a 9,000-operation differential test); typed JS calls | Yes |
| warp `perf-r5` | in-place `List.:+` | No: no measurable change |
| warp `perf-r7` | unboxed JS builtins (`jsUnboxed`), `==` for functions, shared result boxes (`sharedValues`), `Text.size`/`take`/`drop` over `wasm:js-string` | Yes |
| warp `perf-r7u`, `perf-r7w` | `Nat.toText` in Unison and in the DSL, for the comparison above | No: experiments |
| Proscenium `perf-fine` … `perf-r5` | key hints as data, `elementWith`, `Keyed`, `Selector`, DOM sync bottom-up | If ink stays; `Keyed` and `Selector` either way |
| Proscenium `offer-stores` | `Keyed` and `Selector` alone on 0.4.3, with tests in the style of `testSingleton` | Yes: they work on stock ink, and on the tree |
| Proscenium `perf-r7`, `bench-jfb` | the benchmark apps, including `bench.jfb` and `bench.jfbstock` for js-framework-benchmark | Bench code only |
| warp `offer-3-text` | on 1.4.2, standalone: `Text` by code point, which fixes emoji splitting and missed text `match` arms; the differential text fuzz | Yes |
| warp `guard-one-shot`, Proscenium `perf-r7-guard` | every continuation one-shot, to show that nothing in Proscenium or ink resumes twice | No: an experiment |
| Proscenium `perf-r7-mini` | `bench.mini`, the floor for a tree without ink | Bench code only |

The branches above are against 1.3.0. **`@dfreeman/warp/perf-r7-142` is all of the warp
work worth taking, rebased onto 1.4.2.**
- **The merge:** four of the definitions we replace changed upstream, and are merged in
  `unison/scratch/warp--perf-r7-142.u`. Your hardened `Universal.compare` is kept as the
  JS fallback, and wasm handles only two values of the same kind, so the ordering of a
  function against a closure is yours.
- **Tests:** your tests (with 1.4.2's `Integer` and `Natural` ones) and our list fuzz
  test pass.
- **Proscenium:** `perf-r7-142` on it matches Leptos and round 5, and times the same.
- **To take it in parts,** two smaller branches on 1.4.2 stack under it:
  - `offer-1-compare-eq`: `compare` and `==` in wasm;
  - `offer-2-list`: plus the wasm `List`.

  Each passes your tests; the second also passes the list fuzz test.

## `Text` by code point: a bug in stock warp

A differential text fuzz (`tests.builtins.textFuzz`) runs 1,800 text operations natively
and in wasm, over emoji, astral letters and U+FF61. Stock 1.4.2 fails it within 24
operations on every seed:

- **Counting:** `Text.size "a😀b"` is 4 in wasm and 3 in UCM. `take`, `drop`, `uncons`,
  `unsnoc`, `reverse` and `toCharList` split an emoji into two lone surrogates, and
  `indexOf` returns a UTF-16 index.
- **Ordering:** `Universal.compare` and `Text.<` order by UTF-16 unit, which sorts 😀
  below ｡.
- **A text `match` can miss its arm.** `BText.emit` sorts a match's literals by
  Unison's order at build time, then binary-searches them at run time with
  `CompareStrings`, the UTF-16 `compare`.

`offer-3-text` fixes all three, standalone on 1.4.2:
- the eight builtins and the pattern engine's steps work in code points;
- `CompareStrings` is a code point loop over `charCodeAt`, which `Text.<` and its
  siblings call;
- `Universal.compare`'s JS orders `Text` and `Char` by code point.

The fuzz and your suite pass on it. Two harness issues, found on the way: the harness
waits forever instead of reporting a failure on the native side of a
`wasmTestWithChannel` test, or a JS exception inside wasm.

## A first prototype behind your API

`bench.tree` on Proscenium `perf-r7-tree` runs Proscenium's `Render` API on a tree of its
own:
- **One handler:** a single `Render` handler, with no ink.
- **Cells:** `useCell` cells kept by path.
- **The skip:** your own, a memo per element of its name, modifiers and body closure.
- **Reconcile:** the floor's, with a swap fast path.

`bench.rows.ui` runs on it unchanged and matches Leptos. Against the same source on ink:

| | On ink | On the tree |
| --- | --- | --- |
| create 1,000 rows | 81.0 ms | 55.2 ms |
| create 10,000 rows | 512 ms | 318 ms |
| update every 10th | 9.3 ms | 5.8 ms |
| allocations a row | 3,511 | 2,344 |
| handler operations a row | 31 | 11 |
| module, brotli | 40 KB | 24 KB |

It now also runs round 7's fine-grained rows app unchanged, with its provider, `Keyed`
and `Selector`:
- **The session:** render and events run inside `Provider.run`, paused with `Yield`.
- **Redraws:** a message redraws only the element that owns the cell.

Against that app on ink:
- **Select:** costs the same, 0.6 ms.
- **Swap and remove:** a third of ink's time.
- **Creating rows:** 12–36% less.
- **Update every 10th:** at first slower, 9.0 against 5.8 ms, because every update looked
  paths up in maps. Two fixes followed:
  - each cell now holds its value in a cell of its own and names its owner;
  - each changed owner is redrawn directly, with no dirty set.

  Now, at load 3–4, interleaved, it is faster on the tree in every operation but append,
  which is 5% slower:
  - update every 10th: 4.8 against 6.0 ms;
  - select: 0.6 on both;
  - swap: 1.7 against 5.4;
  - create 10,000 rows: 389 against 571.

The 400-card page runs on it too, unchanged. Its markup matches round 7's at every step,
and it is ready in 82 ms against ink's 88.

So does js-framework-benchmark's app, as `keyed/proscenium-tree`. Its first run found
a leak, removed rows' cells kept alive. With cleanup, each element's cells now live in its
mounted node. The suite, against round 7 on ink:
- **Faster on the tree** on everything but select (level) and clearing (twice as slow,
  from the per-row unsubscribes): create 1,000 136 against 151 ms, create 10,000 1,329
  against 1,481.
- **Memory after create and clear:** 0.96 MB against 1.58.
- **Size:** 42 KB against 54, smaller than Leptos's 49.

Effects aren't in it yet, so the meals page doesn't run on it.

## One-shot continuations

You hoped stack switching would let warp drop CPS, at the cost of multi-shot
continuations.
- **The test:** warp `guard-one-shot` makes every captured continuation one-shot, so a
  second resume traps.
- **The UI libraries:** under it, the rows, meals and cards apps pass every consistency
  check and every timing suite, so nothing in Proscenium or ink resumes twice.
  `app.Session` stores a continuation, but resumes it once.
- **What does trap is base's `Each`,** directly and through `test.prop`.

So one-shot stack switching is enough for these libraries, with CPS kept for a handler
that resumes twice.

## A floor for a tree without ink

Before building a tree behind Proscenium's API, we measured how fast one could be with no
ink at all. `bench.mini` on Proscenium `perf-r7-mini` is a keyed virtual DOM in about 200
lines of Unison:
- **Skipping:** a memo node, skipped while its input is equal.
- **Children:** matched by position when no keys changed, with the common prefix and
  suffix trimmed, and ink's `stableIndices` for the moves.

The rows app runs on it twice, as plain data and through an `Html` ability with one
handler. Against round 7, on the same warp:

| Creating 1,000 rows | Round 7 | Data | One handler | Leptos |
| --- | --- | --- | --- | --- |
| allocations a row | 4,198 | 1,041 | 1,431 | |
| handler operations a row | 41 | 0 | 11 | |
| time (interleaved, loaded machine) | 150 ms | 94 ms | 106 ms | 76 ms |

- **Larger lists:** creating 10,000 rows takes 756 ms against 1,177 (Leptos 812), and the
  heap at 10,000 rows is 44 MB against 152.
- **Interactions:** within a few ms of both.
- **Size:** the module is 18 KB brotli, built in 0.24 s.

So most of what is left after round 7 is the two libraries, not warp. An ability-based
API with one handler keeps most of the gain. A whole-view diff is the wrong model for
select, though: 70,000 allocations against `Selector`'s 2,900. So a tree of Proscenium's
own should keep targeted updates. The report's "A floor for a tree without ink" has the
full tables.

## Design notes, not built

- `docs/ProsceniumTree.md`: a tree of Proscenium's own in place of ink, one handler,
  behind the current API.
- `docs/TailResumptive.md`: compiling a handler that resumes once, at the end, as a
  direct call. Neither hot clause is pure: ink's performs `Stream`, and Proscenium's
  performs `Incremental`. So the direct path is conditioned on no frame in between
  handling what the clause performs, which `shift`'s walk can check.
