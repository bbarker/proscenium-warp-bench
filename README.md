# Proscenium and warp against Leptos

Can a web front end written in Unison ([Proscenium](https://share.unison-lang.org/@dfreeman/proscenium),
compiled to WebAssembly by [warp](https://share.unison-lang.org/@dfreeman/warp)) match one written in
Rust with [Leptos](https://leptos.dev)? This repository holds the benchmark, its raw results, the
living report, and the changes made to ink, warp and Proscenium to narrow the gap.

Start with [`docs/REPORT.md`](docs/REPORT.md); its executive summary has the numbers.

## Findings, in short

- **Release builds:** 10–25 times faster than Leptos (about 8 s against 83 s at 400 stateful
  cards; about 26 s against 634 s at 1,600), and the gap grows with size.
- **Code size:** about half of Leptos's raw wasm, but larger under brotli.
- **Runtime:** stock Proscenium was 50–300 times slower than Leptos on a
  js-framework-benchmark table. After five rounds of changes, an interaction (swap, remove, select,
  update) takes 1–6.5 ms, 5.5–7 times Leptos's work but in the same frame; building a list is
  2.7–3.8 times Leptos's work. What is left is in warp's compiler (allocation, call dispatch).
- **On a page modelled on a real app** (a meal planner's week, grocery list, search and FLIP animation),
  editing one meal is as fast as Leptos or faster, animation frames cost the same, and only creating
  many elements at once is still 2–4.5 times Leptos. Its shipped code is 62 KB against 86 KB brotli.
- **Bugs found on the way:** an ordering bug in ink's keyed diff (stock Proscenium puts a row in the
  wrong place after a move and an insert), and an ink test that never ran because a doc comment
  sat in front of `test>`.

## Layout

| Path | What |
| --- | --- |
| `docs/REPORT.md` | The report, with an executive summary at the top |
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

### warp ([`@nusentry/warp`](https://share.unison-lang.org/@nusentry/warp), from `@dfreeman/warp` 1.3.0)

| Branch | What it adds | Round |
| --- | --- | --- |
| [`perf`](https://share.unison-lang.org/@nusentry/warp/code/perf) | `Universal.compare` and `Universal.==` in wasm. From warp 1.3.0. | round 1 |
| [`perf-r4`](https://share.unison-lang.org/@nusentry/warp/code/perf-r4) | `List` as a wasm tree of arrays, direct typed JS calls, a list fuzz test. | round 4–5 |
| [`perf-r5`](https://share.unison-lang.org/@nusentry/warp/code/perf-r5) | `List.:+` appends in place; sharing tests. | round 5 |

A note on 1.3.0: Proscenium 0.4.3, which the benchmark builds on, uses warp 1.3.0. The warp changes
replace whole definitions as they were in 1.3.0, so apply them to a 1.3.0 clone and not to a newer
warp, where they would undo that version's changes to those definitions.

### Proscenium ([`@nusentry/proscenium`](https://share.unison-lang.org/@nusentry/proscenium), from `@dfreeman/proscenium` 0.4.3)

Each branch is built on the one before it, and carries the ink and warp versions it uses as libraries.

| Branch | What it adds | Round |
| --- | --- | --- |
| [`bench`](https://share.unison-lang.org/@nusentry/proscenium/code/bench) | The benchmark apps (counter, rows, cards) and timed build entries. | setup |
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
| [`perf-r6`](https://share.unison-lang.org/@nusentry/proscenium/code/perf-r6) | + warp `perf-r5` (in-place append). No measurable change. | round 5 |
| [`perf-r5m`](https://share.unison-lang.org/@nusentry/proscenium/code/perf-r5m) | `perf-r5i` + the meal-planner benchmark page (`bench.meals`). | round 5, meals |

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
