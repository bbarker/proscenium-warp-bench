# Publishing the Unison branches

The branches live in a UCM codebase (the benchmark codebase, kept untracked at
`target/unison-bench-codebase` in the working copy where the benchmarks were run, or any codebase where `docs/UnisonSteps.md` has been followed), in local
projects named `@dfreeman/ink`, `@dfreeman/warp` and `@dfreeman/proscenium`, because they are clones of
those upstream projects. You cannot push to another user's namespace, so each branch is pushed to a
project of the same name under your own handle (below, `@nusentry`; change it with
`sed -i 's/@nusentry/@yourhandle/g' unison/publish.md README.md docs/PublishingBranches.md`).

- [ ] Log in: `ucm` then `auth.login`.
- [ ] Give each project a local branch `base` holding the upstream release the benchmark starts
      from. It becomes the project's `main` on Share, which Share needs before the project's
      settings work ("No default branch"). In the benchmark codebase this was done on 2026-10-31:

```ucm
scratch/main> clone @dfreeman/ink/releases/2.0.1
scratch/main> clone @dfreeman/proscenium/releases/0.4.3
@dfreeman/ink/releases/2.0.1> branch base
@dfreeman/warp/releases/1.3.0> branch base
@dfreeman/proscenium/releases/0.4.3> branch base
```

- [ ] Push a single branch first, to see that the form of the command works and that the project is
      created under your handle:

```ucm
push @nusentry/ink/perf @dfreeman/ink/perf
```

- [ ] Check it at `https://share.unison-lang.org/@nusentry/ink/code/perf`.
- [ ] Push the rest. `unison/publish.md` has one `push` line per branch, run from any project, in dependency order (ink and
      warp before Proscenium), and can be run as `ucm -c <codebase> transcript.in-place unison/publish.md`
      or pasted into UCM.
- [ ] For each project on Share, set a description and make it public (`@nusentry/ink`, `@nusentry/warp`,
      `@nusentry/proscenium`), and say in each that the project is a benchmark fork of the upstream one.
- [ ] Check that the README's links resolve.

Things to know first:
- `push <remote> <local>` publishes a local branch to a remote one from any project, so there is
  no need to switch projects; each line is `push @nusentry/<project>/<branch> @dfreeman/<project>/<branch>`.
  All the lines are also in `/tmp/unison-bench-pushes.txt` (as originally generated).
- Pushing sends each branch's whole history, including the libraries it depends on. The Proscenium
  branches hold copies of ink and warp as libraries (`lib.dfreeman_ink_r5` and so on), and warp is large
  (over 300,000 terms), so the first Proscenium push is slow.
- The branches `perf-empty*`, `perf-mount`, `perf-mount-clean` and `perf-mount-safe` are rejected experiments
  and are not published. The report mentions them only as rejected.
- The branches' namespaces contain only the code in the scratch files, but they were made in a copy of
  a larger codebase; check `ls` and `ls lib` in each project, and `history` of the branch, for anything
  unrelated before publishing.
