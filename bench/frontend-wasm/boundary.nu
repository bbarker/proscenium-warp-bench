# Summarises the boundary counts `BENCH_COUNT=1 node bench/frontend-wasm/runtime.mjs
# <suite> 1` writes to results/boundary-<suite>.json: for each implementation and
# operation, how many calls crossed between wasm and JS, split into
#   imports   - wasm calling a JS function (a DOM call, a JS builtin, FFI glue)
#   callbacks - exports JS called from a JS import that was running, which is the
#               glue reading its arguments back out of wasm (Text_getValue, ...)
#   entries   - exports JS called with no import running (callDirect from a
#               listener or a microtask, `main`)
# and the largest single entries.
#
#   nu bench/frontend-wasm/boundary.nu rows [--top 5]
#   nu bench/frontend-wasm/boundary.nu self-test

const HERE = path self | path dirname

def kind-of [key: string] {
    if ($key starts-with "import ") {
        "imports"
    } else if ($key | str contains " <- import ") {
        "callbacks"
    } else {
        "entries"
    }
}

# One operation's counts as a row of totals.
def summarise [counts: record] {
    let rows = $counts | transpose key calls | each {|entry| $entry | insert kind (kind-of $entry.key) }
    let sum = {|entries| $entries | reduce --fold 0 {|entry, total| $total + $entry.calls } }
    let total_of = {|kind| do $sum ($rows | where kind == $kind) }
    {
        total: (do $sum $rows)
        imports: (do $total_of "imports")
        callbacks: (do $total_of "callbacks")
        entries: (do $total_of "entries")
    }
}

def "main self-test" [] {
    use std assert
    let counts = {
        "import js:##Nat.toText": 3
        "export Text_getValue <- import js:ffi x": 5
        "export callDirect <- JS": 2
    }
    assert equal (summarise $counts) { total: 10, imports: 3, callbacks: 5, entries: 2 }
    assert equal (summarise {}) { total: 0, imports: 0, callbacks: 0, entries: 0 }
    assert equal (kind-of "export Foreign <- import js:ffi y") "callbacks"
    print "boundary.nu self-test passed"
}

def main [suite: string, --top: int = 4] {
    let file = $HERE | path join "results" $"boundary-($suite).json"
    let results = open $file | get results
    $results | transpose impl operations | each {|impl|
        $impl.operations | reject --optional sites | transpose operation counts | each {|op|
            let sums = summarise $op.counts
            let largest = $op.counts | transpose key calls | sort-by calls --reverse | first $top
                | each {|entry| $"($entry.calls) ($entry.key | str substring 0..90)" } | str join "; "
            { impl: $impl.impl, operation: $op.operation, ...$sums, largest: $largest }
        }
    } | flatten
}
