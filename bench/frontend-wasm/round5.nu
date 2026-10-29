#!/usr/bin/env nu

use std/assert

# Round 5 of the frontend benchmark (docs/reports/FrontendWasmLeptosVsProscenium.md):
# writes, under target/unison/frontend-bench/ (git-ignored), the flush that times
# ink's reconcile against Proscenium's DOM sync, and a transcript that builds a
# timed rows app from a Proscenium branch in a fork of the bench codebase. The
# Unison changes themselves are scratch files in ../unison-scratch/:
# scratch-claude-proscenium--perf-r5.u and scratch-claude-warp--perf-r4.u.

const TIMING_FLUSH = r#'app.Root.internal.JSState.flush : Ref JS (JSState g) ->{JS} ()
app.Root.internal.JSState.flush state =
  use JS.ref modify
  actions =
    app.Root.internal.JSState.modifyQueue
      state (actions -> ([], actions))
  modify state (isScheduled.set false)
  match JSState.session (Ref.read state) with
    None         -> ()
    Some session ->
      now _ = JSValue.global "performance" :: "now" :$ []
      t0 = now ()
      session' = Session.resume actions session
      t1 = now ()
      modify state (session.set (Some session'))
      app.Root.internal.synchronize state (deltas session')
      t2 = now ()
      timings = JSValue.global "__benchTimings"
      timings :: "push" :$> [t0, t1, t2]
'#

def root-dir [] { $env.FILE_PWD | path join ".." ".." | path expand }

def out-dir [] { root-dir | path join "target" "unison" "frontend-bench" }

# Writes the timing flush and the transcript that builds `rows-bare-<variant>t` from
# `@dfreeman/proscenium/<branch>`; run the transcript with
# `ucm -c target/unison-bench-codebase transcript.fork <printed path>`, then
# `node bench/frontend-wasm/phases.mjs warp/rows-bare-<variant>t 5`.
def main [branch: string = "perf-r5", variant: string = "r5"] {
    let dest = out-dir
    mkdir $dest
    let flush = $dest | path join "timing-flush.u"
    $TIMING_FLUSH | save --force $flush
    let build = root-dir | path join "target" "frontend-bench" "warp" $"rows-bare-($variant)t"
    mkdir $build
    let transcript = $dest | path join $"phases-($variant).md"
    [
        "```ucm"
        $"@dfreeman/proscenium/($branch)> load ($flush)"
        $"@dfreeman/proscenium/($branch)> update"
        $"@dfreeman/proscenium/($branch)> run bench.rowsfg.build bare ($build)"
        "```"
    ] | str join "\n" | save --force $transcript
    $transcript
}

def "main self-test" [] {
    let transcript = main "perf-r5" "selftest"
    assert ($transcript | path exists)
    assert (open --raw $transcript | str contains "@dfreeman/proscenium/perf-r5> run bench.rowsfg.build bare")
    assert (open --raw (out-dir | path join "timing-flush.u") | str contains "__benchTimings")
    rm --recursive (root-dir | path join "target" "frontend-bench" "warp" "rows-bare-selftestt")
    rm $transcript
    print "round5 self-test: ok"
}
