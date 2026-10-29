Run `nu bench/frontend-wasm/round3.nu` first, then run this transcript with
`ucm -c target/unison-bench-codebase transcript.in-place bench/frontend-wasm/round3.md`.
These branch names must be unused. This operates only on the isolated benchmark copy.

``` ucm
@dfreeman/ink/perf> branch perf-mount-compute

  Done. I've created the perf-mount-compute branch based off of
  perf.

  Tip: To merge your work back into the perf branch, first
       `switch /perf` then `merge /perf-mount-compute`.

@dfreeman/ink/perf-mount-compute> load target/unison/frontend-bench/scratch-codex-ink--perf-mount-compute.u

  Loading changes detected in
  target/unison/frontend-bench/scratch-codex-ink--perf-mount-compute.u.

  ~ Incremental.reconcile.reconcileCompute : Location
                                             -> Key
                                             -> [Message]
                                             -> Optional
                                               (ComputeRecord
                                                 a g)
                                             -> '{g,
                                             Incremental a g} a
                                             ->{g,
                                             Stream (Delta a)} ComputeRecord
                                               a g

  ~ (modified)

  Run `update` to apply these changes to your codebase.

@dfreeman/ink/perf-mount-compute> update

  Done.

@dfreeman/ink/perf-mount-compute> test

    
    Cached test results (`help testcache` to learn more)
    
      1. Incremental.reconcile.stableIndices.tests.empty          ◉ Passed
      2. Incremental.reconcile.stableIndices.tests.newAndSorted   ◉ Passed
      3. Incremental.reconcile.stableIndices.tests.reversed       ◉ Passed
      4. Incremental.reconcile.stableIndices.tests.swap           ◉ Passed
    
    ✅ 4 test(s) passing
    
    ✅  















    New test results:

    1. tests.attachedReconcile     ◉ the body reading the result ran again
    2. tests.cellLifecycle         ◉ Ok
                                   ◉ Ok
                                   ◉ Ok
                                   ◉ Ok
                                   ◉ Ok
                                   ◉ Ok
                                   ◉ Ok
                                   ◉ Ok
                                   ◉ Ok
    3. tests.detachedReconcile     ◉ only the computation owning the cell ran again
    4. tests.indexReconciliation   ◉ Ok
                                   ◉ Ok
                                   ◉ Ok
                                   ◉ Ok
                                   ◉ Ok
                                   ◉ Ok
                                   ◉ Ok
    5. tests.statePersistence      ◉ Ok
                                   ◉ Ok
                                   ◉ Ok
                                   ◉ Ok
                                   ◉ Ok
                                   ◉ Ok
                                   ◉ Ok
                                   ◉ Ok
                                   ◉ Ok
                                   ◉ Ok
    6. tests.structureUpdates      ◉ Ok
                                   ◉ Ok
                                   ◉ Ok
                                   ◉ Ok
                                   ◉ Ok
                                   ◉ Ok
                                   ◉ Ok
                                   ◉ Ok
    7. tests.subtreeRemoval        ◉ Ok
                                   ◉ Ok
                                   ◉ Ok
                                   ◉ Ok

  ✅ 40 test(s) passing

  Tip: Use view 1 to view the source of a test.

@dfreeman/proscenium/perf-fine> branch perf-mount-compute

  Done. I've created the perf-mount-compute branch based off of
  perf-fine.

  Tip: To merge your work back into the perf-fine branch, first
       `switch /perf-fine` then `merge /perf-mount-compute`.

@dfreeman/proscenium/perf-mount-compute> fork @dfreeman/ink/perf-mount-compute: lib.dfreeman_ink_mount

  Done.

@dfreeman/proscenium/perf-mount-compute> upgrade dfreeman_ink_perf3 dfreeman_ink_mount

  I upgraded dfreeman_ink_perf3 to dfreeman_ink_mount.

@dfreeman/proscenium/perf-mount-compute> test

  ✅  









    New test results:

    1. tests.testRender           ◉ Passed
    2. tests.testScheduling       ◉ Passed
    3. tests.testSingleton        ◉ Passed
    4. tests.testStatefulRender   ◉ Passed

  ✅ 4 test(s) passing

  Tip: Use view 1 to view the source of a test.

@dfreeman/proscenium/perf-mount-compute> compile bench.rowsfg.build target/unison/frontend-bench/rows-build-mount
```
