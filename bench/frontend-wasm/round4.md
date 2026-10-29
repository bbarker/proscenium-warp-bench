Run `nu bench/frontend-wasm/round4.nu` first, then run this transcript with
`ucm -c target/unison-bench-codebase transcript.in-place bench/frontend-wasm/round4.md`.
These branch names must be unused. This operates only on the isolated benchmark copy.

```ucm
@dfreeman/warp/perf> branch perf-r4
@dfreeman/warp/perf-r4> load target/unison/frontend-bench/scratch-warp--perf-list.u
@dfreeman/warp/perf-r4> update
@dfreeman/warp/perf-r4> load target/unison/frontend-bench/scratch-warp--perf-js.u
@dfreeman/warp/perf-r4> update
@dfreeman/warp/perf-r4> run tests
@dfreeman/ink/perf> branch perf-r4
@dfreeman/ink/perf-r4> load target/unison/frontend-bench/scratch-ink--perf-r4.u
@dfreeman/ink/perf-r4> update
@dfreeman/ink/perf-r4> test
@dfreeman/proscenium/perf-mount-compute> branch perf-r4
@dfreeman/proscenium/perf-r4> fork @dfreeman/warp/perf-r4: lib.dfreeman_warp_r4
@dfreeman/proscenium/perf-r4> upgrade dfreeman_warp_perf3 dfreeman_warp_r4
@dfreeman/proscenium/perf-r4> fork @dfreeman/ink/perf-r4: lib.dfreeman_ink_r4
@dfreeman/proscenium/perf-r4> upgrade dfreeman_ink_mount dfreeman_ink_r4
@dfreeman/proscenium/perf-r4> load target/unison/frontend-bench/scratch-proscenium--perf-r4.u
@dfreeman/proscenium/perf-r4> update
@dfreeman/proscenium/perf-r4> test
@dfreeman/proscenium/perf-r4> compile bench.rowsfg.build target/unison/frontend-bench/rows-build-r4
```
