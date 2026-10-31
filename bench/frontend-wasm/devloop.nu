#!/usr/bin/env nu

use std/assert
use gen-cards.nu [card-body unison-card]

# The dev loop, timed (docs/REPORT.md, "The dev loop, wired up"): a run of
# edits to the cards app, each loaded and `update`d in UCM and then built as a
# warp delta, in a fork of the bench codebase on @dfreeman/proscenium/devloop.
#
#   nu bench/frontend-wasm/devloop.nu run <count> [--ns <namespace>] [--edits <n>]
#   nu bench/frontend-wasm/devloop.nu warm <count> [--ns <namespace>] [--edits <n>]
#   nu bench/frontend-wasm/devloop.nu page <count> <mode> [--iterations <n>] [--edits <n>]
#   nu bench/frontend-wasm/devloop.nu self-test
#
# - `run`: each edit's delta is a UCM `run` of `<ns>.dev.delta`, a process that
#   reads the build record from disk and writes it back. The session starts
#   with `<ns>.dev.base`, and ends with a full build of the edited app
#   (`<ns>.build`) for comparison.
# - `warm`: a compiled `<ns>.dev.server` runs beside UCM with warp and the
#   build record in memory, and each edit is a UCM `run` of `<ns>.dev.push`,
#   which ships the new code to it and waits for the delta.
# - `page`: the browser half for a finished `run` or `warm`: devloop.mjs loads
#   the base page and applies each edit's delta to it.
#
# Every UCM step is timed between `bench.build.stamp` runs, less the cost of a
# stamp itself (the median of three back to back). Each result goes to
# `results/devloop-builds.jsonl` with the machine's load average. The edit
# files and transcripts go to `target/unison/frontend-bench/devloop/`, the
# builds to `target/frontend-bench/warp/cards-<count>-dev-<mode>/`.

const BRANCH = "@dfreeman/proscenium/devloop"

def bench-dir [] { $env.FILE_PWD }
def root-dir [] { bench-dir | path dirname | path dirname }
def codebase [] { root-dir | path join "target" "unison-bench-codebase" }
def work-dir [] { root-dir | path join "target" "unison" "frontend-bench" "devloop" }
def build-dir [count: int, mode: string] { root-dir | path join "target" "frontend-bench" "warp" $"cards-($count)-dev-($mode)" }
def server-entry [count: int] { root-dir | path join "target" "unison" "frontend-bench" $"cards-($count)-devserver.uc" }

def load-average [] {
    open /proc/loadavg | split row " " | first 3 | into float
}

# The cards the edits change, in order: `first`, the last card, `first` again,
# one in the middle, and `first`'s neighbour, then round again. `first` must be
# a card no other app shares: the generated cards are alike, so the 1,600-card
# app's cards 0-99 are the same terms as the 25- and 100-card apps', and UCM
# 1.5's `update` of a name whose term has other names leaves its dependents be.
export def edited-cards [count: int, edits: int, first: int] {
    let cycle = [$first ($count - 1) $first ($count // 2) ($first + 1)]
    0..<$edits | each {|step| $cycle | get ($step mod ($cycle | length)) }
}

# The paragraph a card reads after edit `step`.
export def edit-text [step: int, card: int] {
    $"Edit ($step): (card-body $card false)"
}

# The edits as records: step (from 1), card, the paragraph after it, and the
# Unison file that makes it.
export def edits [count: int, ns: string, edits: int, first: int] {
    edited-cards $count $edits $first | enumerate | each {|edit|
        let step = $edit.index + 1
        let text = edit-text $step $edit.item
        { step: $step, card: $edit.item, text: $text, source: (unison-card $ns $edit.item $text) }
    }
}

# The transcript that times the edits, run from `BRANCH`.
export def transcript [mode: string, ns: string, out: string, edit_files: list<string>, full_out: string] {
    let prompt = $"($BRANCH)>"
    let stamp = {|label| $"($prompt) run bench.build.stamp ($label)" }
    let opening = [(do $stamp "s0") (do $stamp "s1") (do $stamp "s2")]
    let base = if $mode == "run" { [$"($prompt) run ($ns).dev.base ($out)" (do $stamp "base")] } else { [] }
    let steps = $edit_files | enumerate | each {|edit|
        let step = $edit.index + 1
        let build = if $mode == "run" { $"($prompt) run ($ns).dev.delta ($out) ($step)" } else { $"($prompt) run ($ns).dev.push ($out) ($step)" }
        [
            $"($prompt) load ($edit.item)" (do $stamp $"loaded-($step)")
            $"($prompt) update" (do $stamp $"updated-($step)")
            $build (do $stamp $"built-($step)")
        ]
    } | flatten
    let full = if $mode == "run" { [$"($prompt) run ($ns).build bare ($full_out)" (do $stamp "full")] } else { [] }
    ["```ucm" ...$opening ...$base ...$steps ...$full "```" ""] | str join "\n"
}

# `STAMP <label> <ms>` lines as a table.
export def stamps [log: string] {
    $log | lines | where {|line| $line =~ 'STAMP \S+ \S+' }
        | each {|line| $line | parse --regex 'STAMP (?<label>\S+) (?<at>\S+)' | first }
        | update at {|row| $row.at | into float }
}

# Milliseconds between consecutive stamps, less a stamp's own cost, keyed by
# the later stamp's label.
export def intervals [marks: table] {
    let cost = $marks | where label in [s0 s1 s2] | window 2 | each {|pair| $pair.1.at - $pair.0.at } | math median
    let spans = $marks | window 2 | each {|pair| { label: $pair.1.label, ms: ($pair.1.at - $pair.0.at - $cost | math round --precision 1) } }
    { stamp_ms: ($cost | math round --precision 1), spans: ($spans | reduce --fold {} {|span, all| $all | insert $span.label $span.ms }) }
}

# JSON lines in a log, the build and push reports.
export def reports [log: string] {
    $log | lines | each {|line| $line | str replace --regex '^.*?(\{")' '{"' } | where {|line| $line starts-with '{"' } | each { from json }
}

# Removes what an earlier loop wrote to `dir`, and nothing else, so that a
# warm server never sees an old push.
def clear-build [dir: string] {
    mkdir $dir
    ls $dir | where {|file| ($file.name | path basename) =~ '^(base\.|delta-|ui-|push-|done-|record\.bin|known\.bin|ready\.json|.*\.partial$)' }
        | each {|file| rm $file.name }
    ignore
}

def write-inputs [count: int, ns: string, mode: string, edit_count: int, first: int] {
    let work = work-dir
    mkdir $work
    let planned = edits $count $ns $edit_count $first
    let files = $planned | each {|edit|
        let file = $work | path join $"cards-($count)-edit($edit.step).u"
        $edit.source | save --force $file
        $file
    }
    let out = build-dir $count $mode
    clear-build $out
    let full_out = build-dir $count "full"
    mkdir $full_out
    let script = $work | path join $"cards-($count)-($mode).md"
    transcript $mode $ns $out $files $full_out | save --force $script
    { planned: $planned, out: $out, script: $script }
}

def run-transcript [script: string] {
    let started = date now
    let result = do { ^ucm -c (codebase) transcript.fork $script } | complete
    $result.stdout | save --force ($script | str replace --regex '\.md$' '.log')
    if $result.exit_code != 0 {
        print $result.stdout
        error make { msg: $"the transcript failed: see ($script | str replace '.md' '.output.md')" }
    }
    { seconds: (((date now) - $started) / 1sec | math round --precision 1), log: $result.stdout }
}

def summarise [mode: string, count: int, planned: list, timed: record, server: record, load_before: list] {
    let marks = stamps $timed.log
    let spans = intervals $marks
    let found = reports $timed.log
    let steps = $planned | each {|edit|
        let inner = $found | where {|line| ($line.build? == $"delta-($edit.step)") or ($line.push? == ($edit.step | into string)) } | get 0?
        let at = {|label| $spans.spans | get --optional $"($label)-($edit.step)" }
        { step: $edit.step, card: $edit.card, load_ms: (do $at "loaded"), update_ms: (do $at "updated"), build_ms: (do $at "built"), inner: $inner }
    }
    {
        kind: "devloop", mode: $mode, cards: $count, at: (date now | format date "%+")
        load: $load_before, load_after: (load-average), stamp_ms: $spans.stamp_ms, transcript_s: $timed.seconds
        base: ($found | where {|line| $line.build? == "base" } | get 0?), base_ms: ($spans.spans | get --optional base)
        full: ($found | where {|line| $line.build? | default "" | str ends-with "-bare" } | get 0?)
        full_ms: ($spans.spans | get --optional full)
        server: $server, steps: $steps
    }
}

def save-result [result: record] {
    $result | to json --raw | $in + "\n" | save --append (bench-dir | path join "results" "devloop-builds.jsonl")
    print ($result.steps | select step card load_ms update_ms build_ms | table)
    $result
}

def default-ns [count: int, ns: string] {
    if ($ns | is-empty) { $"bench.cards.s($count)" } else { $ns }
}

# The dev loop with a UCM `run` of the delta entry per edit.
def "main run" [
    count: int
    --ns: string = ""     # the app's namespace (bench.cards.s400i for 400 cards)
    --edits: int = 5      # how many edits
    --first: int = 7      # the first card edited (see edited-cards)
] {
    let ns = default-ns $count $ns
    let inputs = write-inputs $count $ns "run" $edits $first
    let load_before = load-average
    let timed = run-transcript $inputs.script
    save-result (summarise "run" $count $inputs.planned $timed {} $load_before)
}

# The dev loop with a warm build server beside UCM and a push per edit.
def "main warm" [
    count: int
    --ns: string = ""     # the app's namespace (bench.cards.s400i for 400 cards)
    --edits: int = 5      # how many edits
    --first: int = 7      # the first card edited (see edited-cards)
] {
    let ns = default-ns $count $ns
    let inputs = write-inputs $count $ns "warm" $edits $first
    let load_before = load-average
    let log = work-dir | path join $"cards-($count)-server.log"
    let started = date now
    let pid = ^bash -c $"ucm run.compiled '(server-entry $count)' -- '($inputs.out)' > '($log)' 2>&1 & echo $!" | str trim | into int
    let ready_file = $inputs.out | path join "ready.json"
    mut polls = 0
    while not ($ready_file | path exists) and $polls < 1200 and (ps | any {|process| $process.pid == $pid }) {
        sleep 100ms
        $polls += 1
    }
    if not ($ready_file | path exists) {
        error make { msg: $"the server (pid ($pid)) did not start: see ($log)" }
    }
    let server = open $ready_file | insert startup_s (((date now) - $started) / 1sec | math round --precision 1)
    let timed = try { run-transcript $inputs.script } catch {|failure| kill $pid; error make { msg: $failure.msg } }
    kill $pid
    save-result (summarise "warm" $count $inputs.planned $timed $server $load_before)
}

# Splits a generated `cards-<count>.u` into files UCM can load one at a time:
# its definitions are separated by blank lines, and a file of 400 cards
# already peaks near 10 GB in `load`. The cards go 400 to a file, and the
# pages, UI and build entries into the last.
export def split-source [source: string, per_file: int] {
    let definitions = $source | split row "\n\n" | where {|chunk| $chunk =~ ' : ' }
    let cards = $definitions | where {|chunk| $chunk =~ '^\S+\.card\d+ :' }
    let rest = $definitions | where {|chunk| $chunk !~ '^\S+\.card\d+ :' }
    [...($cards | chunks $per_file) $rest] | each {|chunk| ($chunk | str join "\n\n") + "\n" }
}

def "main split" [
    count: int
    --per-file: int = 400
] {
    let dir = root-dir | path join "target" "unison" "frontend-bench"
    let parts = split-source (open --raw ($dir | path join $"cards-($count).u")) $per_file
    $parts | enumerate | each {|part|
        let file = $dir | path join $"cards-($count)-part($part.index + 1).u"
        $part.item | save --force $file
        $file
    }
}

# The browser half: devloop.mjs on a finished loop's build.
def "main page" [
    count: int
    mode: string          # run or warm
    --ns: string = ""
    --edits: int = 5
    --first: int = 7
    --iterations: int = 10
] {
    let ns = default-ns $count $ns
    let steps = edits $count $ns $edits $first | each {|edit| $"($edit.step)=($edit.card):($edit.text)" }
    ^node (bench-dir | path join "devloop.mjs") $"warp/cards-($count)-dev-($mode)" $iterations ...$steps
}

def "main self-test" [] {
    assert equal (edited-cards 400 6 7) [7 399 7 200 8 7]
    assert equal (edit-text 2 9) "Edit 2: Body text for card 9: juliet alpha bravo charlie delta."
    let planned = edits 400 "bench.cards.s400i" 2 7
    assert equal ($planned | get card) [7 399]
    assert ($planned.0.source | str contains "bench.cards.s400i.card7 : '{Render {}} ()")
    assert ($planned.0.source | str contains '"Edit 1: Body text for card 7: hotel india juliet alpha bravo."')
    let script = transcript "warm" "bench.cards.s400i" "/out" ["/e1.u"] "/full"
    assert ($script | str contains $"($BRANCH)> run bench.cards.s400i.dev.push /out 1")
    assert not ($script | str contains "dev.base")
    assert ((transcript "run" "ns" "/out" ["/e1.u"] "/full") | str contains "run ns.build bare /full")
    let log = "STAMP s0 100.0\nSTAMP s1 110.0\nSTAMP s2 122.0\n{\"build\":\"delta-1\",\"emitted\":7}\nSTAMP loaded-1 1000.0"
    let spans = intervals (stamps $log)
    assert equal $spans.stamp_ms 11.0
    assert equal ($spans.spans | get loaded-1) 867.0
    assert equal (reports $log | first | get emitted) 7
    let source = "-- header\n\nns.card0 : T\nns.card0 = 0\n\nns.card1 : T\nns.card1 = 1\n\nns.card2 : T\nns.card2 = 2\n\nns.page0 : T\nns.page0 = 3\n"
    let parts = split-source $source 2
    assert equal ($parts | length) 3
    assert ($parts.0 | str contains "ns.card1 =")
    assert ($parts.2 | str starts-with "ns.page0 : T")
    print "devloop self-test: ok"
}

def main [] {
    print "usage: nu bench/frontend-wasm/devloop.nu (run|warm|page|self-test) ..."
}
