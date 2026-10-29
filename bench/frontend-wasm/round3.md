Run `nu bench/frontend-wasm/round3.nu` first, then run this transcript with
`ucm -c target/unison-bench-codebase transcript.in-place bench/frontend-wasm/round3.md`.
These branch names must be unused. This operates only on the isolated benchmark copy.

```ucm
@dfreeman/ink/perf> branch perf-mount-compute
@dfreeman/ink/perf-mount-compute> load target/unison/frontend-bench/scratch-codex-ink--perf-mount-compute.u
@dfreeman/ink/perf-mount-compute> update
@dfreeman/ink/perf-mount-compute> test
@dfreeman/proscenium/perf-fine> branch perf-mount-compute
@dfreeman/proscenium/perf-mount-compute> fork @dfreeman/ink/perf-mount-compute: lib.dfreeman_ink_mount
@dfreeman/proscenium/perf-mount-compute> upgrade dfreeman_ink_perf3 dfreeman_ink_mount
@dfreeman/proscenium/perf-mount-compute> test
@dfreeman/proscenium/perf-mount-compute> compile bench.rowsfg.build target/unison/frontend-bench/rows-build-mount
```