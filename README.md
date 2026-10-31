# Proscenium and warp against Leptos

Can a web front end written in Unison ([Proscenium](https://share.unison-lang.org/@dfreeman/proscenium),
compiled to WebAssembly by [warp](https://share.unison-lang.org/@dfreeman/warp)) match one written in
Rust with [Leptos](https://leptos.dev)? This repository holds the benchmark, its raw results, the
living report, and the changes made to ink, warp and Proscenium to narrow the gap.

Start with [`docs/REPORT.md`](docs/REPORT.md). Its executive summary has the numbers and
a line on each round, and each round's section has the details.

## Findings, in short

- **Build time:** release builds are 10–25 times faster than Leptos's, and the gap grows
  with app size.
- **Edit loop:** with warp's codegen cache wired up, an edit reaches the running page in
  3.4 s at 400 cards and 5.4 s at 1,600, and the page keeps its state. Leptos's dev builds
  take 7.5–10.6 s and 36–48 s, with a reload. Most of what is left is UCM's work.
- **Size:** about half of Leptos's raw wasm, but larger under brotli on repetitive code.
- **Runtime:** rounds of changes to ink, warp and Proscenium took a js-framework-benchmark
  table from 50–300 times Leptos's time to 1.4–7 times. A minimal signals library on the
  same warp runs it at about Leptos's speed ([`docs/Signals.md`](docs/Signals.md)).
- **Bugs:** the work found bugs in ink, warp and UCM; the report's summary lists them.

## Layout

| Path | What |
| --- | --- |
| `docs/REPORT.md` | The report, with an executive summary at the top |
| `docs/ReviewResponse.md` | For the author: the work done since their review, and what it showed |
| `docs/ProsceniumTree.md` | A tree of Proscenium's own in place of ink: the design note |
| `docs/Signals.md` | A signals core without implicits, against the tree and Leptos |
| `docs/TailResumptive.md` | Handlers that resume once: the design note for warp, and the ceiling measured |
| `docs/UnisonSteps.md` | How to recreate the Unison branches from the scratch files |
| `docs/PublishingBranches.md` | How the branches below were published |
| `bench/frontend-wasm/` | Build, size and browser-timing scripts; the Rust (Leptos) apps; raw results |
| `unison/scratch/` | The Unison changes and apps, as UCM scratch files |
| `unison/publish.md` | A UCM transcript that pushes the branches |

## Unison branches

These branches are on Unison Share under [`@nusentry`](https://share.unison-lang.org/@nusentry). Each is a branch of a
clone of the upstream project named in the first row, and the report writes them as
`@dfreeman/<project>/<branch>`.

### ink ([`@nusentry/ink`](https://share.unison-lang.org/@nusentry/ink), from `@dfreeman/ink` 2.0.1)

| Branch | What it adds | Round |
| --- | --- | --- |
| [`perf`](https://share.unison-lang.org/@nusentry/ink/code/perf) | Keyed reconcile in O(n log n) (fixes a child-ordering bug), `compute_` with targeted reconciliation. From ink 2.0.1. | round 1–2 |
| [`perf-mount-compute`](https://share.unison-lang.org/@nusentry/ink/code/perf-mount-compute) | Skips the diff when a computation first mounts. | round 3 |
| [`perf-r4`](https://share.unison-lang.org/@nusentry/ink/code/perf-r4) | Fast paths for prefixes, suffixes, swaps, appends, clears. | round 4 |
| [`perf-r5`](https://share.unison-lang.org/@nusentry/ink/code/perf-r5) | Previous children found by position; single-pass key counts. | round 5 |
| [`offer-1-ordering`](https://share.unison-lang.org/@nusentry/ink/code/offer-1-ordering) | **To offer, standalone on 2.0.1:** `perf`'s keyed reconcile and ordering fix alone, without `compute_`, with two regression tests that fail on 2.0.1 (`tests.relocateAndInsert`, `tests.swapAndInsert`) and release notes. All 41 tests pass. | to offer |

### warp ([`@nusentry/warp`](https://share.unison-lang.org/@nusentry/warp), from `@dfreeman/warp` 1.3.0)

| Branch | What it adds | Round |
| --- | --- | --- |
| [`perf`](https://share.unison-lang.org/@nusentry/warp/code/perf) | `Universal.compare` and `Universal.==` in wasm. From warp 1.3.0. | round 1 |
| [`perf-r4`](https://share.unison-lang.org/@nusentry/warp/code/perf-r4) | `List` as a wasm tree of arrays, direct typed JS calls, a list fuzz test. | round 4–5 |
| [`perf-r5`](https://share.unison-lang.org/@nusentry/warp/code/perf-r5) | `List.:+` appends in place; sharing tests. No measurable change. | round 6 |
| [`perf-r7`](https://share.unison-lang.org/@nusentry/warp/code/perf-r7) | From `perf-r4`: JS interop, `Nat.toText` and `Text.indexOf` take unboxed arguments (`jsUnboxed`); `==` compares a function with a closure by id in wasm; `compare`, `==` and Boolean intrinsics return shared boxes; `Text.size`/`take`/`drop`/`uncons`/`unsnoc`/`repeat`/`reverse` and three `Char` builtins over `wasm:js-string`. | round 7 |
| [`perf-r7u`](https://share.unison-lang.org/@nusentry/warp/code/perf-r7u) | `perf-r7` with `Nat.toText` written in Unison (an experiment: 8 times slower than unboxed JS). | round 7 |
| [`perf-r7w`](https://share.unison-lang.org/@nusentry/warp/code/perf-r7w) | `perf-r7` with `Nat.toText` in the instruction DSL (an experiment: 5 times slower than unboxed JS). | round 7 |
| [`guard-one-shot`](https://share.unison-lang.org/@nusentry/warp/code/guard-one-shot) | `perf-r7` with every captured continuation made one-shot: a second resume traps. An experiment, to find what resumes twice. | round 7 |
| [`detect-tail-resumptive`](https://share.unison-lang.org/@nusentry/warp/code/detect-tail-resumptive) | `perf-r7` with a classifier in `anfToOps` that reports, as it compiles, whether each handler arm resumes once in tail position (`internal.build.Op.tailShape`). A measurement, not a change to the output. | round 7 |
| [`handler-cost`](https://share.unison-lang.org/@nusentry/warp/code/handler-cost) | `perf-r7` with `bench.handlerCost`: a million ability operations through a handler written as UI handlers are, under 0, 4 and 16 other handlers, against the same work as plain calls (`bench/handler-cost/`). | round 7 |
| [`offer-1-compare-eq`](https://share.unison-lang.org/@nusentry/warp/code/offer-1-compare-eq) | On warp 1.4.2: round 1 only, `compare` and `==` in wasm with 1.4.2's JS as the fallback. Passes warp's tests. | to offer |
| [`offer-2-list`](https://share.unison-lang.org/@nusentry/warp/code/offer-2-list) | `offer-1` + round 4's wasm `List` and its fuzz test. Passes warp's tests and the fuzz test. | to offer |
| [`offer-3-text`](https://share.unison-lang.org/@nusentry/warp/code/offer-3-text) | On warp 1.4.2, standalone: `Text` by code point, as Unison counts and orders it. Stock warp counts UTF-16 units, splits emoji, and can miss a text `match` arm. Includes `tests.builtins.textFuzz`, a differential test of 1,800 text operations. Passes warp's tests and the fuzz. | to offer |
| [`perf-r7-142`](https://share.unison-lang.org/@nusentry/warp/code/perf-r7-142) | **All of the above that is worth taking, rebased onto warp 1.4.2:** rounds 1, 4 and 7, with 1.4.2's `Universal.compare` as the JS fallback, and `offer-3-text`'s `Text` by code point (round 7's wasm `Text` builtins rewritten as code point loops). warp's tests, the list fuzz and the text fuzz pass. | round 7 |

A note on 1.3.0: Proscenium 0.4.3, which the benchmark builds on, uses warp 1.3.0. The warp changes
replace whole definitions as they were in 1.3.0, so apply them to a 1.3.0 clone and not to a newer
warp, where they would undo that version's changes to those definitions.

### Proscenium ([`@nusentry/proscenium`](https://share.unison-lang.org/@nusentry/proscenium), from `@dfreeman/proscenium` 0.4.3)

Each branch is built on the one before it, and carries the ink and warp versions it uses as libraries.

| Branch | What it adds | Round |
| --- | --- | --- |
| [`bench`](https://share.unison-lang.org/@nusentry/proscenium/code/bench) | The benchmark apps (counter, rows, cards) and timed build entries. | setup |
| [`offer-stores`](https://share.unison-lang.org/@nusentry/proscenium/code/offer-stores) | **To offer, standalone on 0.4.3:** the `Keyed` and `Selector` provider stores, with `tests.testKeyed` and `tests.testSelector` (a select that notifies no one fails the second) and release notes. | to offer |
| [`perf`](https://share.unison-lang.org/@nusentry/proscenium/code/perf) | ink's keyed diff. | round 1 |
| [`perf-compare`](https://share.unison-lang.org/@nusentry/proscenium/code/perf-compare) | + warp's compare in wasm. | round 1 |
| [`perf-eq`](https://share.unison-lang.org/@nusentry/proscenium/code/perf-eq) | + warp's `==` in wasm. | round 1 |
| [`perf-keys`](https://share.unison-lang.org/@nusentry/proscenium/code/perf-keys) | + key hints as data. | round 1 |
| [`perf-targeted`](https://share.unison-lang.org/@nusentry/proscenium/code/perf-targeted) | + ink's `compute_` in every element. | round 2 |
| [`perf-fine`](https://share.unison-lang.org/@nusentry/proscenium/code/perf-fine) | + `elementWith`, `Keyed`, `Selector`, the fine-grained rows app (`bench.rowsfg`). | round 2 |
| [`perf-mount-compute`](https://share.unison-lang.org/@nusentry/proscenium/code/perf-mount-compute) | + ink without the first-mount diff. | round 3 |
| [`perf-r4`](https://share.unison-lang.org/@nusentry/proscenium/code/perf-r4) | + wasm `List`, direct JS calls, DOM fast paths. | round 4 |
| [`perf-r5`](https://share.unison-lang.org/@nusentry/proscenium/code/perf-r5) | + DOM sync built bottom-up. | round 5 |
| [`perf-r5i`](https://share.unison-lang.org/@nusentry/proscenium/code/perf-r5i) | + ink `perf-r5`. The report's "Round 5" column. | round 5 |
| [`perf-r5k`](https://share.unison-lang.org/@nusentry/proscenium/code/perf-r5k) | + single-pass key counts. | round 5 |
| [`perf-r6`](https://share.unison-lang.org/@nusentry/proscenium/code/perf-r6) | + warp `perf-r5` (in-place append). No measurable change. | round 6 |
| [`perf-r5m`](https://share.unison-lang.org/@nusentry/proscenium/code/perf-r5m) | `perf-r5i` + the meal-planner benchmark page (`bench.meals`). | round 5, meals |
| [`perf-r7`](https://share.unison-lang.org/@nusentry/proscenium/code/perf-r7) | `perf-r5m` on warp `perf-r7`, + the js-framework-benchmark app (`bench.jfb`). | round 7 |
| [`bench-jfb`](https://share.unison-lang.org/@nusentry/proscenium/code/bench-jfb) | `bench` + the js-framework-benchmark app for stock Proscenium (`bench.jfbstock`). | round 7 |
| [`perf-r7u`](https://share.unison-lang.org/@nusentry/proscenium/code/perf-r7u), [`perf-r7w`](https://share.unison-lang.org/@nusentry/proscenium/code/perf-r7w) | `perf-r7` on warp `perf-r7u` and `perf-r7w`, for timing `Nat.toText` (`bench.totext`). | round 7 |
| [`perf-r7-142`](https://share.unison-lang.org/@nusentry/proscenium/code/perf-r7-142) | `perf-r7` on warp `perf-r7-142`. All apps match Leptos and round 5, and rows times the same as on 1.3.0. | round 7 |
| [`perf-r7-guard`](https://share.unison-lang.org/@nusentry/proscenium/code/perf-r7-guard) | `perf-r7` on warp `guard-one-shot`. The rows, meals and cards apps pass every check and timing suite: nothing in Proscenium or ink resumes a continuation twice. | round 7 |
| [`perf-r7-tree`](https://share.unison-lang.org/@nusentry/proscenium/code/perf-r7-tree) | `perf-r7-mini` + `bench.tree`, a first prototype of a tree of Proscenium's own behind its `Render` API: one handler, cells by path, a memo per element. `bench.rows.ui` runs on it unchanged, 32–39% faster than on ink for creating rows, and so does round 7's fine-grained `bench.rowsfg.ui` with its provider, `Keyed` and `Selector`: faster than on ink in every operation but append (5% slower). The 400-card page, the meals page and the js-framework-benchmark app run on it too. | round 7 |
| [`perf-r7-signals`](https://share.unison-lang.org/@nusentry/proscenium/code/perf-r7-signals) | `perf-r7-tree` + `bench.sig`, a minimal signals core in Leptos's model, with the rows app on it (the reactive context passed explicitly, and carried by an ability) and the meals page. At about Leptos's speed on the rows suite with a fifth of the tree's heap, and a meal's edit is the fastest of the four builds (`docs/Signals.md`). | round 7 |
| [`perf-r7-mini`](https://share.unison-lang.org/@nusentry/proscenium/code/perf-r7-mini) | `perf-r7` + `bench.mini`, a keyed virtual DOM with no ink and no Proscenium, with the rows app as data and through an `Html` ability with one handler: the floor for a tree without ink. | round 7 |
| [`devloop`](https://share.unison-lang.org/@nusentry/proscenium/code/devloop) | `perf-r7` + `bench.dev`, warp's codegen cache wired to a running page, with the 1,600-card app (`bench.cards.s1600`). The pieces are a `CodeCache` base, the build record kept on disk, a page that loads each delta and renders it on the same root (keeping state), and a warm build server that UCM pushes new code to. An edit reaches the page in 3.4 s at 400 cards and 5.4 s at 1,600 (`docs/REPORT.md`, "The dev loop, wired up"). | dev loop |

## Reproducing

You need `nu`, `cargo` (with the `wasm32-unknown-unknown` target), `wasm-pack`, `binaryen` (a recent
version for warp's output), `esbuild`, `ucm` and Chromium, and `npm install` at the root for
`playwright-core`. A Nix dev shell supplied them for the original runs.

```sh
npm install
nu bench/frontend-wasm/bench.nu leptos rows
BENCH_IMPLS=leptos node bench/frontend-wasm/runtime.mjs rows 5
```

The warp side needs a compiled build entry from one of the Proscenium branches above; the report's
"How to rerun" section gives the commands, and `docs/UnisonSteps.md` the steps to rebuild the branches.

## Method and caveats

- All numbers are from one machine (24 threads, shared with other work) with Chromium 149; every
  result records the load average when it was taken.
- The Leptos side uses Leptos 0.8 patched to the public [AlygnHealth/leptos](https://github.com/AlygnHealth/leptos)
  fork, pinned in `bench/frontend-wasm/leptos/Cargo.toml`. Plain Leptos 0.8.22 from crates.io was re-timed on
  the rows app and agrees within noise.
- Rounds 3 and 4 were written by other agents and reviewed in round 5; the report says what the review
  found.
- Round 5's review also found that the timing harness had counted layout and paint against some
  operations; the numbers for rounds 1–4 were measured before that fix, and the report says which
  are affected.
