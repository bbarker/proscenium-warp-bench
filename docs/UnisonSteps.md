# Recreating the benchmark's Unison branches

These steps rebuild, in a UCM codebase of your own, the branches the report measures.
Run them from the repository root, so that the relative paths below resolve. The
published branches (README) are the result of these steps; use them instead if you only
want to read or run the code.

The commands name the projects `@dfreeman/proscenium`, `@dfreeman/ink` and
`@dfreeman/warp`, the upstream projects the branches were made from, and
`unison/scratch/` holds the files they load. Nothing here touches `main` of any project.

- [ ] Bench code on a `@dfreeman/proscenium/bench` branch (create it with `branch.empty /bench`)
      (typechecks there):

```ucm
@dfreeman/proscenium/bench> load unison/scratch/proscenium--bench.u
@dfreeman/proscenium/bench> update
```

- [ ] ink: the `O(n log n)` keyed reconcile (with the ordering bug fixed), and
      `compute_` with targeted reconciliation. The file is in two parts that were applied
      in order; loading it whole on a fresh 2.0.1 clone applies both:

```ucm
scratch/main> clone @dfreeman/ink/releases/2.0.1 @dfreeman/ink/perf
@dfreeman/ink/perf> load unison/scratch/ink--perf.u
@dfreeman/ink/perf> update
@dfreeman/ink/perf> test
```

- [ ] warp: `Universal.compare` and `Universal.==` in wasm, list elements through them.
      Typechecks on the `@dfreeman/warp/perf`, from main
      (1.4.2). Proscenium 0.4.3 is on warp 1.3.0, so the bench codebase applied the same
      file to a `releases/1.3.0` clone instead.

```ucm
@dfreeman/warp/perf> load unison/scratch/warp--perf.u
@dfreeman/warp/perf> update
```

- [ ] The Proscenium chain, each branch on the one before (the bench codebase has every
      intermediate step as its own branch; this goes straight to the end):

```ucm
@dfreeman/proscenium/bench> branch /perf-fine
@dfreeman/proscenium/perf-fine> fork @dfreeman/ink/perf: lib.dfreeman_ink_perf
@dfreeman/proscenium/perf-fine> upgrade dfreeman_ink_2_0_1 dfreeman_ink_perf
@dfreeman/proscenium/perf-fine> fork @dfreeman/warp/perf: lib.dfreeman_warp_perf
@dfreeman/proscenium/perf-fine> upgrade dfreeman_warp_1_3_0 dfreeman_warp_perf
@dfreeman/proscenium/perf-fine> load unison/scratch/proscenium--perf-keys.u
@dfreeman/proscenium/perf-fine> update
@dfreeman/proscenium/perf-fine> load unison/scratch/proscenium--perf-targeted.u
@dfreeman/proscenium/perf-fine> update
@dfreeman/proscenium/perf-fine> load unison/scratch/proscenium--perf-fine.u
@dfreeman/proscenium/perf-fine> update
@dfreeman/proscenium/perf-fine> test
```

      `unison/scratch/proscenium--perf-fine.u` adds a `Render` operation, so its app half
      (`bench.rowsfg.*`, after the library half) can only typecheck once the library half
      is in: load it with the `---` fold moved above `type bench.rowsfg.Model` first,
      `update`, then move the fold back to the end and load again (that is how it was
      applied). `--perf-targeted.u` is the one that teaches `TestUI.traverse` the new `DetachedChild` node.

- [ ] Run warp's tests with a recent binaryen first on the PATH (its harness cannot parse
      its own output with the wasm-opt 117 in `~/.local/bin`):
      `PATH=$(dirname $(nix build --no-link --print-out-paths nixpkgs#binaryen)/bin/wasm-opt):$PATH ucm`,
      then `@dfreeman/warp/perf> run tests` (92 pass in the bench codebase).

## Rounds 3 to 5 (2026-10-28 and 2026-10-29)

Round 3 (ink, mount without a diff) is superseded by round 4's ink file, which was applied
to `ink/perf` directly. Rounds 3 and 4 were written by other agents and are generated into
`target/unison/frontend-bench/` by `nu bench/frontend-wasm/round4.nu`; round 5 is in
`unison/scratch/`.

- [ ] Regenerate the round 4 files (they are git-ignored): `nu bench/frontend-wasm/round4.nu`
- [ ] ink round 4, on the `perf` branch from the steps above:

```ucm
@dfreeman/ink/perf> branch /perf-r4
@dfreeman/ink/perf-r4> load target/unison/frontend-bench/scratch-ink--perf-r4.u
@dfreeman/ink/perf-r4> update
@dfreeman/ink/perf-r4> test
```

      45 tests should pass, `tests.reconcileFastPaths` among them. (The file as round 4
      first generated it defined a junk operator `>` instead of that test; the
      generator is fixed, so check that `view >` finds nothing.)

- [ ] ink round 5: previous children looked up by position:

```ucm
@dfreeman/ink/perf-r4> branch /perf-r5
@dfreeman/ink/perf-r5> load unison/scratch/ink--perf-r5.u
@dfreeman/ink/perf-r5> update
@dfreeman/ink/perf-r5> test
```

      46 tests should pass.

- [ ] warp round 4: **apply it to a 1.3.0 clone, not to `perf` from main.** The two files
      replace whole definitions (`Runtime.defineTypes`, the support JS, the replacement
      table) as they were in 1.3.0, so on 1.4.2 they would undo whatever 1.4.2 changed in
      them. Proscenium 0.4.3 is on 1.3.0 anyway:

```ucm
scratch/main> clone @dfreeman/warp/releases/1.3.0 @dfreeman/warp/perf-r4
@dfreeman/warp/perf-r4> load unison/scratch/warp--perf.u
@dfreeman/warp/perf-r4> update
@dfreeman/warp/perf-r4> load target/unison/frontend-bench/scratch-warp--perf-list.u
@dfreeman/warp/perf-r4> update
@dfreeman/warp/perf-r4> load target/unison/frontend-bench/scratch-warp--perf-js.u
@dfreeman/warp/perf-r4> update
@dfreeman/warp/perf-r4> run tests
@dfreeman/warp/perf-r4> load unison/scratch/warp--perf-r4.u
@dfreeman/warp/perf-r4> update
@dfreeman/warp/perf-r4> run tests.builtins.listFuzz.suite
```

- [ ] Optional, warp round 5 (appends in place; no measurable speed-up, kept for its
      tests). It redefines `tests.builtins` to add its sharing test:

```ucm
@dfreeman/warp/perf-r4> branch /perf-r5
@dfreeman/warp/perf-r5> load unison/scratch/warp--perf-r5.u
@dfreeman/warp/perf-r5> update
@dfreeman/warp/perf-r5> run tests
```

      (binaryen 133 first on the PATH, as above.) The last file is round 5's
      differential test of the wasm `List`; on a mismatch it hangs instead of failing,
      so a run that takes more than a minute or two is a failure.

- [ ] Proscenium rounds 4 and 5, on `perf-fine` from the steps above:

```ucm
@dfreeman/proscenium/perf-fine> branch /perf-r5
@dfreeman/proscenium/perf-r5> fork @dfreeman/warp/perf-r4: lib.dfreeman_warp_r4
@dfreeman/proscenium/perf-r5> upgrade dfreeman_warp_perf dfreeman_warp_r4
@dfreeman/proscenium/perf-r5> fork @dfreeman/ink/perf-r5: lib.dfreeman_ink_r5
@dfreeman/proscenium/perf-r5> upgrade dfreeman_ink_perf dfreeman_ink_r5
@dfreeman/proscenium/perf-r5> load target/unison/frontend-bench/scratch-proscenium--perf-r4.u
@dfreeman/proscenium/perf-r5> update
@dfreeman/proscenium/perf-r5> load unison/scratch/proscenium--perf-r5.u
@dfreeman/proscenium/perf-r5> update
@dfreeman/proscenium/perf-r5> test
```

      (The lib names in the `upgrade` lines are whatever `ls lib` shows for warp and
      ink on that branch.) Four tests should pass.

- [ ] The meals page (the realistic benchmark added after round 5), on `perf-r5i`. It
      adds only `bench.meals`, so `add` is enough:

```ucm
@dfreeman/proscenium/perf-r5i> branch /perf-r5m
@dfreeman/proscenium/perf-r5m> load unison/scratch/proscenium--perf-r5m.u
@dfreeman/proscenium/perf-r5m> add
@dfreeman/proscenium/perf-r5m> compile bench.meals.build target/unison/frontend-bench/meals-build-r5i
```

## Round 7, after the author's review (2026-10-30)

- [ ] warp, from `perf-r4` (the warp under round 5): the JS interop functions take their
      arguments unboxed (`internal.Replacement.jsUnboxed`), and `==` compares a function
      with a closure by id in wasm. Run `tests` with binaryen 133 first on the PATH.

```ucm
@dfreeman/warp/perf-r4> branch /perf-r7
@dfreeman/warp/perf-r7> load unison/scratch/warp--perf-r7.u
@dfreeman/warp/perf-r7> update
@dfreeman/warp/perf-r7> run tests
```

- [ ] Proscenium, from `perf-r5m` (round 5 and the meals page), with that warp:

```ucm
@dfreeman/proscenium/perf-r5m> branch /perf-r7
@dfreeman/proscenium/perf-r7> fork @dfreeman/warp/perf-r7: lib.dfreeman_warp_r7
@dfreeman/proscenium/perf-r7> upgrade dfreeman_warp_r4 dfreeman_warp_r7
@dfreeman/proscenium/perf-r7> compile bench.rowsfg.build target/unison/frontend-bench/rows-build-r7
@dfreeman/proscenium/perf-r7> compile bench.cards.s400i.build target/unison/frontend-bench/cards-400-build-r7
@dfreeman/proscenium/perf-r7> compile bench.meals.build target/unison/frontend-bench/meals-build-r7
```

Each later change to warp `perf-r7` was picked up the same way, with
`fork @dfreeman/warp/perf-r7: lib.dfreeman_warp_r7<x>` and
`upgrade <previous> dfreeman_warp_r7<x>`. In the benchmark codebase the lib is
`dfreeman_warp_r7e`, after five forks:
1. the boundary change;
2. the equality fix redone on round 4's version;
3. shared results;
4. `Nat.toText`, `Text.indexOf` and a shared `()`;
5. `Text.size`, `take` and `drop` over `wasm:js-string`, with the release notes.

The `perf-r7u` and `perf-r7w` branches were made from Proscenium `perf-r7` while its lib
was `dfreeman_warp_r7d`.

`perf-r7` also redefines `bench.meals.searchView`, with the filter inside the `#search`
element so that it sits behind a skip boundary. That is the last definition in
`proscenium--perf-r7.u`, and it is loaded with `update`, not `add`, since it replaces a
term. Its build is `compile bench.meals.build target/unison/frontend-bench/meals-build-r7s`,
built with `nu bench/frontend-wasm/bench.nu warp meals --variant r7s`. The `meals-r7`
build in the report predates it.

The js-framework-benchmark app is on `perf-r7` too (`bench.jfb`):

```ucm
@dfreeman/proscenium/perf-r7> load unison/scratch/proscenium--perf-r7.u
@dfreeman/proscenium/perf-r7> add
@dfreeman/proscenium/perf-r7> compile bench.jfb.build target/unison/frontend-bench/jfb-build-r7
```

- [ ] A builtin written in Unison instead of JS: `Nat.toText` (`Nat_toText.impl`, with a
      test against UCM's own), on `@dfreeman/warp/perf-r7u`. It takes two loads, because
      a `termLink` to a term defined in the same file does not parse. The alias is below
      the fold of `warp--perf-r7u.u`, so load the file, `add`, then load a file holding
      only the alias, and `update`. The timing app `bench.totext` is on Proscenium
      `perf-r7`, and `perf-r7u` is `perf-r7` with that warp:

```ucm
@dfreeman/warp/perf-r7> branch /perf-r7u
@dfreeman/warp/perf-r7u> load unison/scratch/warp--perf-r7u.u
@dfreeman/warp/perf-r7u> add
@dfreeman/warp/perf-r7u> test internal.runtime.replacements.unison_base.Nat_toText.impl
@dfreeman/warp/perf-r7u> load <a file with the alias from below the fold>
@dfreeman/warp/perf-r7u> update
@dfreeman/proscenium/perf-r7> branch /perf-r7u
@dfreeman/proscenium/perf-r7u> fork @dfreeman/warp/perf-r7u: lib.dfreeman_warp_r7u
@dfreeman/proscenium/perf-r7u> upgrade dfreeman_warp_r7d dfreeman_warp_r7u
@dfreeman/proscenium/perf-r7u> compile bench.totext.build target/unison/frontend-bench/totext-build-r7u
```

- [ ] The same builtin in warp's instruction DSL, on `@dfreeman/warp/perf-r7w`:

```ucm
@dfreeman/warp/perf-r7> branch /perf-r7w
@dfreeman/warp/perf-r7w> load unison/scratch/warp--perf-r7w.u
@dfreeman/warp/perf-r7w> update
@dfreeman/proscenium/perf-r7> branch /perf-r7w
@dfreeman/proscenium/perf-r7w> fork @dfreeman/warp/perf-r7w: lib.dfreeman_warp_r7w
@dfreeman/proscenium/perf-r7w> upgrade dfreeman_warp_r7d dfreeman_warp_r7w
@dfreeman/proscenium/perf-r7w> compile bench.totext.build target/unison/frontend-bench/totext-build-r7w
```

Then `nu bench/frontend-wasm/bench.nu warp totext --variant <r5i|r7|r7u|r7w>` for each, and
`node bench/frontend-wasm/totext.mjs warp/totext-bare-r5i warp/totext-bare-r7 warp/totext-bare-r7u warp/totext-bare-r7w`.

- [ ] All of warp's changes, rebased onto warp 1.4.2, the current release on Share
      (`@dfreeman/warp/perf-r7-142`).
  - Our scratch files replace 104 definitions, and four of them changed between 1.3.0 and
    1.4.2: the builtin map, `Universal_compare`, `tests.builtins` and `ReleaseNotes`.
  - `unison/scratch/warp--perf-r7-142.u` holds those four merged:
    - the map is 1.4.2's plus round 4's 13 interop entries;
    - `Universal_compare.jsSource` is 1.4.2's JS, now the fallback of the wasm
      comparison;
    - the test list is 1.4.2's plus `builtins.list`;
    - the release notes are 1.4.2's line plus ours.
  - Everything else is replayed as it was. warp's tests and the list fuzz test pass, and
    so do the rows, meals and cards checks on Proscenium `perf-r7-142`.

```ucm
@dfreeman/warp/perf-r7> clone @dfreeman/warp/releases/1.4.2
@dfreeman/warp/releases/1.4.2> branch /perf-r7-142
@dfreeman/warp/perf-r7-142> load unison/scratch/warp--perf.u
@dfreeman/warp/perf-r7-142> update
@dfreeman/warp/perf-r7-142> load target/unison/frontend-bench/scratch-warp--perf-list.u
@dfreeman/warp/perf-r7-142> update
@dfreeman/warp/perf-r7-142> load target/unison/frontend-bench/scratch-warp--perf-js.u
@dfreeman/warp/perf-r7-142> update
@dfreeman/warp/perf-r7-142> load unison/scratch/warp--perf-r4.u
@dfreeman/warp/perf-r7-142> update
@dfreeman/warp/perf-r7-142> load unison/scratch/warp--perf-r7.u
@dfreeman/warp/perf-r7-142> update
@dfreeman/warp/perf-r7-142> load unison/scratch/warp--perf-r7-142.u
@dfreeman/warp/perf-r7-142> update
@dfreeman/warp/perf-r7-142> run tests
@dfreeman/warp/perf-r7-142> run tests.builtins.listFuzz.suite
@dfreeman/proscenium/perf-r7> branch /perf-r7-142
@dfreeman/proscenium/perf-r7-142> fork @dfreeman/warp/perf-r7-142: lib.dfreeman_warp_r7_142
@dfreeman/proscenium/perf-r7-142> upgrade dfreeman_warp_r7e dfreeman_warp_r7_142
```

- [ ] The same work as a stack of branches on 1.4.2, so that it can be taken a level at a
      time:
  - `offer-1-compare-eq`: round 1, `compare` and `==` in wasm, with 1.4.2's JS as their
    fallback. Lists are still JS here, so the fallback is what compares them.
  - `offer-2-list`: plus round 4's wasm `List` and its fuzz test.
  - `perf-r7-142`: plus round 4's interop functions and all of round 7.

  The parts are not independent: round 4's `compare` and `==` contain round 1's, and round
  7 builds on round 4's interop functions. So each branch contains the one before it. The
  small merge files are cut from `warp--perf-r7-142.u`:
  - `warp--offer-1-compare-eq.u`: the JS fallback and the release notes;
  - `warp--offer-2-list.u`: the JS fallback again, the test list and the release notes.

  **The fallback has to be loaded after the round 4 list file,** which redefines
  `Universal_compare.jsSource` with 1.3.0's JS. That version has no `BigInt` case, so a
  `Natural` compare panics in JS, and warp's test runner then waits forever (1.4.2's
  `Natural` test hung that way until the order was fixed). Both branches pass warp's full
  suite, and `offer-2-list` also passes the list fuzz test.

```ucm
@dfreeman/warp/releases/1.4.2> branch /offer-1-compare-eq
@dfreeman/warp/offer-1-compare-eq> load unison/scratch/warp--perf.u
@dfreeman/warp/offer-1-compare-eq> update
@dfreeman/warp/offer-1-compare-eq> load unison/scratch/warp--offer-1-compare-eq.u
@dfreeman/warp/offer-1-compare-eq> update
@dfreeman/warp/offer-1-compare-eq> branch /offer-2-list
@dfreeman/warp/offer-2-list> load target/unison/frontend-bench/scratch-warp--perf-list.u
@dfreeman/warp/offer-2-list> update
@dfreeman/warp/offer-2-list> load unison/scratch/warp--perf-r4.u
@dfreeman/warp/offer-2-list> update
@dfreeman/warp/offer-2-list> load unison/scratch/warp--offer-2-list.u
@dfreeman/warp/offer-2-list> update
```

- [ ] `Text` by code point, standalone on 1.4.2 (`offer-3-text`): the eight builtins
      that counted UTF-16 units, the pattern engine's steps, `CompareStrings` as a code
      point loop (which `Text.<` and its siblings now call, and which a text `match`
      binary-searches with), `Universal.compare`'s JS order for `Text` and `Char`, and the
      differential `tests.builtins.textFuzz`. The same changes, with round 7's wasm
      `Text` builtins rewritten as code point loops, are in `warp--perf-r7-142.u`.

```ucm
@dfreeman/warp/releases/1.4.2> branch /offer-3-text
@dfreeman/warp/offer-3-text> load unison/scratch/warp--offer-3-text.u
@dfreeman/warp/offer-3-text> update
@dfreeman/warp/offer-3-text> run tests.builtins.textFuzz.suite
@dfreeman/warp/offer-3-text> run tests
```

  On `perf-r7-142` the merge file carries the same fix. A second load of it brings an
  existing branch up to date, and Proscenium `perf-r7-142` then moves to it:

```ucm
@dfreeman/warp/perf-r7-142> load unison/scratch/warp--perf-r7-142.u
@dfreeman/warp/perf-r7-142> update
@dfreeman/warp/perf-r7-142> run tests.builtins.textFuzz.suite
@dfreeman/proscenium/perf-r7-142> fork @dfreeman/warp/perf-r7-142: lib.dfreeman_warp_r7_142t
@dfreeman/proscenium/perf-r7-142> upgrade dfreeman_warp_r7_142 dfreeman_warp_r7_142t
```

- [ ] The same app for stock Proscenium (`bench.jfbstock`, plain `useState` and a region
      per row), on a branch of `bench`:

```ucm
@dfreeman/proscenium/bench> branch /bench-jfb
@dfreeman/proscenium/bench-jfb> load unison/scratch/proscenium--bench-jfb.u
@dfreeman/proscenium/bench-jfb> add
@dfreeman/proscenium/bench-jfb> compile bench.jfbstock.build target/unison/frontend-bench/jfb-build-stock
```

- [ ] The floor for a tree without ink (`bench.mini`: a keyed virtual DOM, the rows app as
      data and through an `Html` ability), on a branch of `perf-r7`:

```ucm
@dfreeman/proscenium/perf-r7> branch /perf-r7-mini
@dfreeman/proscenium/perf-r7-mini> load unison/scratch/proscenium--perf-r7-mini.u
@dfreeman/proscenium/perf-r7-mini> add
@dfreeman/proscenium/perf-r7-mini> compile bench.mini.rows.build target/unison/frontend-bench/rows-build-mini4
@dfreeman/proscenium/perf-r7-mini> compile bench.mini.rowsh.build target/unison/frontend-bench/rows-build-minih4
```

- [ ] Handlers that resume once, measured: warp `detect-tail-resumptive` reports each
      handler arm's shape as it compiles (run any build on it, such as Proscenium's
      `bench.rowsfg.build`, with the classifier's library in place of `dfreeman_warp_r7f`),
      and warp `handler-cost` times a million operations (`bench/handler-cost/run.mjs`):

```ucm
@dfreeman/warp/perf-r7> branch /detect-tail-resumptive
@dfreeman/warp/detect-tail-resumptive> load unison/scratch/warp--detect-tail-resumptive.u
@dfreeman/warp/detect-tail-resumptive> update
@dfreeman/warp/perf-r7> branch /handler-cost
@dfreeman/warp/handler-cost> load unison/scratch/warp--handler-cost.u
@dfreeman/warp/handler-cost> add
@dfreeman/warp/handler-cost> test bench.handlerCost
@dfreeman/warp/handler-cost> run bench.handlerCost.build target/unison/handler-cost
```

- [ ] One-shot continuations, an experiment: warp `guard-one-shot` makes a second resume
      of any captured continuation trap, and Proscenium `perf-r7-guard` runs the apps on it:

```ucm
@dfreeman/warp/perf-r7> branch /guard-one-shot
@dfreeman/warp/guard-one-shot> load unison/scratch/warp--guard-one-shot.u
@dfreeman/warp/guard-one-shot> update
@dfreeman/proscenium/perf-r7> branch /perf-r7-guard
@dfreeman/proscenium/perf-r7-guard> fork @dfreeman/warp/guard-one-shot: lib.dfreeman_warp_guard
@dfreeman/proscenium/perf-r7-guard> upgrade dfreeman_warp_r7f dfreeman_warp_guard
@dfreeman/proscenium/perf-r7-guard> compile bench.rowsfg.build target/unison/frontend-bench/rows-build-guard
@dfreeman/proscenium/perf-r7-guard> compile bench.meals.build target/unison/frontend-bench/meals-build-guard
@dfreeman/proscenium/perf-r7-guard> compile bench.cards.s400i.build target/unison/frontend-bench/cards-400-build-guard
```

- [ ] A first prototype of the tree behind Proscenium's API (`bench.tree`), on a branch of
      `perf-r7-mini`, with the rows app built on it and, for comparison, on ink:

```ucm
@dfreeman/proscenium/perf-r7-mini> branch /perf-r7-tree
@dfreeman/proscenium/perf-r7-tree> load unison/scratch/proscenium--perf-r7-tree.u
@dfreeman/proscenium/perf-r7-tree> add
@dfreeman/proscenium/perf-r7-tree> compile bench.tree.rows.build target/unison/frontend-bench/rows-build-tree2
@dfreeman/proscenium/perf-r7-tree> compile bench.rows.build target/unison/frontend-bench/rows-build-plain
@dfreeman/proscenium/perf-r7-tree> compile bench.tree.rowsfg.build target/unison/frontend-bench/rows-build-treefg4
@dfreeman/proscenium/perf-r7-tree> compile bench.tree.cards.build target/unison/frontend-bench/cards-400-build-tree5
@dfreeman/proscenium/perf-r7-tree> compile bench.tree.jfb.build target/unison/frontend-bench/jfb-build-tree5
@dfreeman/proscenium/perf-r7-tree> compile bench.tree.meals.build target/unison/frontend-bench/meals-build-tree
```

- [ ] Signals (phase 6): `bench.sig`, a minimal signals core, and the rows app on it with
      the reactive context passed explicitly and carried by an ability, on a branch of
      `perf-r7-tree`:

```ucm
@dfreeman/proscenium/perf-r7-tree> branch /perf-r7-signals
@dfreeman/proscenium/perf-r7-signals> load unison/scratch/proscenium--perf-r7-signals.u
@dfreeman/proscenium/perf-r7-signals> add
@dfreeman/proscenium/perf-r7-signals> compile bench.sig.rows.build target/unison/frontend-bench/rows-build-sig3
@dfreeman/proscenium/perf-r7-signals> compile bench.sig.rowsA.build target/unison/frontend-bench/rows-build-siga3
@dfreeman/proscenium/perf-r7-signals> compile bench.sig.meals.build target/unison/frontend-bench/meals-build-sig2
```

- [ ] The two library offers that stand alone: ink's ordering fix on 2.0.1 (`perf`'s first
      step, `#7tptpse51l`, plus its regression tests and release notes), and Proscenium's
      `Keyed` and `Selector` on 0.4.3 (`main`):

```ucm
@dfreeman/ink/perf> branch /offer-1-ordering
@dfreeman/ink/offer-1-ordering> reset #7tptpse51l
@dfreeman/ink/offer-1-ordering> load unison/scratch/ink--offer-1-ordering.u
@dfreeman/ink/offer-1-ordering> update
@dfreeman/ink/offer-1-ordering> test
@dfreeman/proscenium/main> branch /offer-stores
@dfreeman/proscenium/offer-stores> load unison/scratch/proscenium--offer-stores.u
@dfreeman/proscenium/offer-stores> update
@dfreeman/proscenium/offer-stores> test
```

Suggested `history.comment` lines:

- ink/perf: `keyed reconcile in O(n log n) by longest increasing run, new children move with a moved predecessor; compute_ lets a message re-run only the computation owning its cell`
- warp/perf: `Universal.compare and Universal.== walk values in wasm, falling back to JS; list elements compared through them`
- proscenium/perf-fine: `key hints as data, every element a compute_, elementWith, Keyed and Selector stores; bench.rowsfg fine-grained rows app`
- proscenium/bench: `bench: counter, rows and generated card apps with timed warp build entries`
- ink/perf-r4: `reconcile fast paths for prefixes, suffixes, swaps, appends and clears; mount without a diff`
- ink/perf-r5: `previous children looked up by position first, indexed only after a few misses; new tags counted in one map pass`
- warp/perf-r4: `List as a balanced tree of 32-element arrays in wasm; direct typed JSValue calls; a differential List fuzz test against the native runtime`
- proscenium/perf-r5: `DOM sync builds new subtrees bottom-up, by identity of the keys ink places children under, and batches removals under one parent`
- warp/perf-r5: `List.:+ appends in place into a leaf's spare capacity, marked by a hole value`
- proscenium/perf-r5m: `bench.meals: a meal planner page (week of day cards with totals, grocery list, recipe search, FLIP-animated day move, CSS-animated SVG mascot) and its timed build entry`
- warp/perf-r7: `JS interop, Nat.toText and Text.indexOf take unboxed arguments and box their results in wasm (jsUnboxed); == compares a function with a closure by id in wasm; compare, == and Boolean intrinsics return shared boxes`
- proscenium/perf-r7: `perf-r5m on warp perf-r7; bench.jfb, the js-framework-benchmark app`
- proscenium/bench-jfb: `bench.jfbstock, the js-framework-benchmark app for stock Proscenium`
- proscenium/perf-r7-mini: `bench.mini, a keyed virtual DOM in plain Unison with memo nodes and prefix/suffix trimming; the rows app as data and through a one-handler Html ability`
- warp/offer-3-text: `Text by code point, as Unison counts and orders it: size, take, drop, uncons, unsnoc, reverse, toCharList, indexOf and pattern steps; CompareStrings as a code point loop, fixing text matches; tests.builtins.textFuzz`
- warp/perf-r7-142: `Text by code point, as on offer-3-text, with the wasm Text builtins of round 7 rewritten as code point loops`
- proscenium/perf-r7-142: `on warp perf-r7-142 with Text by code point`
- warp/guard-one-shot: `experiment: shift::continue poisons its data after the first resume, so a second resume of any continuation traps`
- warp/detect-tail-resumptive: `measurement: anfToOps reports through Debug.trace whether each request-match arm resumes once in tail position (internal.build.Op.tailShape)`
- warp/handler-cost: `bench.handlerCost: a million ability operations through a recursive state-carrying handler, under 0, 4 and 16 other handlers, against plain calls`
- proscenium/perf-r7-guard: `perf-r7 on warp guard-one-shot, to show that nothing resumes a continuation twice`
- proscenium/perf-r7-tree: `bench.tree: Proscenium's Render API on a tree of its own with one handler, cells by path and a memo per element; bench.rows.ui runs on it unchanged`
- proscenium/perf-r7-tree (meals): `bench.tree: properties, and listeners that read the real event; bench.tree.meals.build runs the meals page unchanged`
- proscenium/perf-r7-signals: `bench.sig: a minimal signals core (signals, effects, memos, owners, a keyed selector, a keyed list, conditional content) with subscriptions stamped by run; the rows app on it with the reactive context passed explicitly and carried by an ability, and the meals page`
- ink/offer-1-ordering: `keyed reconcile in O(n log n); a new child moves with a moved predecessor; regression tests for a rotate and insert and a swap and insert`
- proscenium/offer-stores: `Keyed and Selector provider stores for fine-grained updates, with tests`
