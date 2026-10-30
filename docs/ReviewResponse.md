# After the review: what was tried, and what it showed

This is for the author of warp and Proscenium. It follows his review of 2026-10-30 and
summarises the work done since. The details are in `docs/REPORT.md` ("Review from the
author", "Measured attribution", "Round 7") and `docs/ProsceniumTree.md`. Every change is
on its own branch, against warp 1.3.0, Proscenium 0.4.3 and ink 2.0.1, the versions the
benchmark started from. Nothing here assumes it will be taken.

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

The results of a local run are in the report.

## The branches

| Branch | What it is | Worth taking? |
| --- | --- | --- |
| ink `perf` | O(n log n) keyed reconcile, which fixes the ordering bug after a move and an insert | Yes: the bug affects every Proscenium user |
| ink `perf`, `perf-mount-compute`, `perf-r4`, `perf-r5` | `compute_`, no diff on first mount, fast paths, children by position | If ink stays |
| warp `perf` | `Universal.compare` and `==` in wasm | Yes |
| warp `perf-r4` | `List` as a wasm tree of arrays (with a 9,000-operation differential test); typed JS calls | Yes |
| warp `perf-r5` | in-place `List.:+` | No: no measurable change |
| warp `perf-r7` | unboxed JS builtins, `==` for functions, shared result boxes | Yes |
| Proscenium `perf-fine` … `perf-r5` | key hints as data, `elementWith`, `Keyed`, `Selector`, DOM sync bottom-up | If ink stays; `Keyed` and `Selector` either way |
