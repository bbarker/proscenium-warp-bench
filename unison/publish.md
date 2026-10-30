# Push every benchmark branch to Share

Run from the repo root with no UCM open on the codebase, since an in-place transcript takes its lock:

    ucm -c <codebase> transcript.in-place unison/publish.md

Here `<codebase>` is the one holding the `@dfreeman/*` branches (see `docs/PublishingBranches.md`). UCM writes its output to `unison/publish.output.md`, which git ignores.

Each line is `push <remote> <local>`. A branch that is already pushed and unchanged is a no-op, so the whole file is safe to rerun. A transcript stops at the first failure, and the error names the line.

```ucm
@dfreeman/proscenium/bench> push @nusentry/ink/perf @dfreeman/ink/perf
@dfreeman/proscenium/bench> push @nusentry/ink/perf-mount-compute @dfreeman/ink/perf-mount-compute
@dfreeman/proscenium/bench> push @nusentry/ink/perf-r4 @dfreeman/ink/perf-r4
@dfreeman/proscenium/bench> push @nusentry/ink/perf-r5 @dfreeman/ink/perf-r5
@dfreeman/proscenium/bench> push @nusentry/warp/perf @dfreeman/warp/perf
@dfreeman/proscenium/bench> push @nusentry/warp/perf-r4 @dfreeman/warp/perf-r4
@dfreeman/proscenium/bench> push @nusentry/warp/perf-r5 @dfreeman/warp/perf-r5
@dfreeman/proscenium/bench> push @nusentry/warp/perf-r7 @dfreeman/warp/perf-r7
@dfreeman/proscenium/bench> push @nusentry/warp/perf-r7u @dfreeman/warp/perf-r7u
@dfreeman/proscenium/bench> push @nusentry/warp/perf-r7w @dfreeman/warp/perf-r7w
@dfreeman/proscenium/bench> push @nusentry/warp/offer-1-compare-eq @dfreeman/warp/offer-1-compare-eq
@dfreeman/proscenium/bench> push @nusentry/warp/offer-2-list @dfreeman/warp/offer-2-list
@dfreeman/proscenium/bench> push @nusentry/warp/perf-r7-142 @dfreeman/warp/perf-r7-142
@dfreeman/proscenium/bench> push @nusentry/proscenium/bench @dfreeman/proscenium/bench
@dfreeman/proscenium/bench> push @nusentry/proscenium/perf @dfreeman/proscenium/perf
@dfreeman/proscenium/bench> push @nusentry/proscenium/perf-compare @dfreeman/proscenium/perf-compare
@dfreeman/proscenium/bench> push @nusentry/proscenium/perf-eq @dfreeman/proscenium/perf-eq
@dfreeman/proscenium/bench> push @nusentry/proscenium/perf-keys @dfreeman/proscenium/perf-keys
@dfreeman/proscenium/bench> push @nusentry/proscenium/perf-targeted @dfreeman/proscenium/perf-targeted
@dfreeman/proscenium/bench> push @nusentry/proscenium/perf-fine @dfreeman/proscenium/perf-fine
@dfreeman/proscenium/bench> push @nusentry/proscenium/perf-mount-compute @dfreeman/proscenium/perf-mount-compute
@dfreeman/proscenium/bench> push @nusentry/proscenium/perf-r4 @dfreeman/proscenium/perf-r4
@dfreeman/proscenium/bench> push @nusentry/proscenium/perf-r5 @dfreeman/proscenium/perf-r5
@dfreeman/proscenium/bench> push @nusentry/proscenium/perf-r5i @dfreeman/proscenium/perf-r5i
@dfreeman/proscenium/bench> push @nusentry/proscenium/perf-r5k @dfreeman/proscenium/perf-r5k
@dfreeman/proscenium/bench> push @nusentry/proscenium/perf-r6 @dfreeman/proscenium/perf-r6
@dfreeman/proscenium/bench> push @nusentry/proscenium/perf-r5m @dfreeman/proscenium/perf-r5m
@dfreeman/proscenium/bench> push @nusentry/proscenium/perf-r7 @dfreeman/proscenium/perf-r7
@dfreeman/proscenium/bench> push @nusentry/proscenium/bench-jfb @dfreeman/proscenium/bench-jfb
@dfreeman/proscenium/bench> push @nusentry/proscenium/perf-r7u @dfreeman/proscenium/perf-r7u
@dfreeman/proscenium/bench> push @nusentry/proscenium/perf-r7w @dfreeman/proscenium/perf-r7w
@dfreeman/proscenium/bench> push @nusentry/proscenium/perf-r7-142 @dfreeman/proscenium/perf-r7-142
@dfreeman/proscenium/bench> push @nusentry/proscenium/perf-r7-mini @dfreeman/proscenium/perf-r7-mini
```
