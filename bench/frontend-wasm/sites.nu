# Summarises the site counters of modules rewritten by instrument.nu, from
# results/sites-<suite>.json (a BENCH_COUNT=1 run of runtime.mjs over the
# `warp-<variant>` implementations whose module is instrumented). Per operation:
#   entries     function entries, split into `cps` (frame-and-continuation code,
#               including the pieces after each call) and `direct`
#   call_ref    indirect calls (closures, continuations)
#   continue    returns through a continuation (`return_call $continue`)
#   apply       generic applications (`apply*`, `apply0`-`apply8`, `applyMany`)
#   handlers    `shift` and `hnd` (effect handling)
#   allocs      `struct.new*` and `array.new*`, with the types allocated most
#
#   nu bench/frontend-wasm/sites.nu rows [--top 4]
#   nu bench/frontend-wasm/sites.nu rows --by-function [--top 15] [--operation "create 1k"]   # hot functions
#   nu bench/frontend-wasm/sites.nu self-test

const HERE = path self | path dirname

def site-map [suite: string, impl: string] {
    let variant = $impl | str replace "warp-" ""
    let app = if ($suite starts-with "cards") { $suite } else { $suite }
    $HERE | path join ".." ".." "target" "frontend-bench" "warp" $"($app)-bare-($variant)" $"($app)-bare.opt.sites.json" | open
}

# One operation's counters joined to their sites.
def counted [counters: record, sites: list] {
    $counters | transpose id calls | update id {|row| $row.id | into int } | each {|row|
        $sites | get $row.id | insert calls $row.calls
    }
}

def total [rows: list] { $rows | reduce --fold 0 {|row, sum| $sum + $row.calls } }

def summarise [rows: list, top: int] {
    let of = {|kind| $rows | where kind == $kind }
    let entries = do $of "entry"
    let helpers = do $of "helper"
    let allocs = do $of "alloc"
    let by_type = $allocs | group-by detail | transpose type rows
        | each {|group| { type: $group.type, calls: (total $group.rows) } } | sort-by calls --reverse
    {
        entries: (total $entries)
        cps: (total ($entries | where detail == "cps"))
        direct: (total ($entries | where detail == "direct"))
        call_ref: (total (do $of "call_ref"))
        continue: (total ($helpers | where detail == "continue"))
        apply: (total ($helpers | where {|row| $row.detail starts-with "apply" }))
        handlers: (total ($helpers | where detail in [shift hnd]))
        allocs: (total $allocs)
        largest: ($by_type | first $top | each {|row| $"($row.calls) ($row.type)" } | str join ", ")
    }
}

def "main self-test" [] {
    use std assert
    let sites = [
        { id: 0, kind: "entry", func: "f", detail: "cps" }
        { id: 1, kind: "alloc", func: "f", detail: "Data" }
        { id: 2, kind: "helper", func: "f", detail: "continue" }
        { id: 3, kind: "entry", func: "g", detail: "direct" }
        { id: 4, kind: "helper", func: "g", detail: "apply1" }
    ]
    let rows = counted { "0": 2, "1": 6, "2": 2, "3": 5, "4": 1 } $sites
    let summary = summarise $rows 1
    assert equal ($summary | reject largest) { entries: 7, cps: 2, direct: 5, call_ref: 0, continue: 2, apply: 1, handlers: 0, allocs: 6 }
    assert equal $summary.largest "6 Data"
    print "sites.nu self-test passed"
}

def main [suite: string, --top: int = 4, --by-function, --operation: string = ""] {
    let results = $HERE | path join "results" $"sites-($suite).json" | open | get results
    $results | transpose impl data | where {|row| ($row.data | get --optional sites) != null } | each {|impl|
        let sites = site-map $suite $impl.impl
        let operations = $impl.data.sites | transpose operation counters
        if $by_function {
            $operations | where {|op| $operation == "" or $op.operation == $operation } | each {|op| counted $op.counters $sites } | flatten
                | group-by func | transpose func rows
                | each {|group| {
                    impl: $impl.impl, func: $group.func
                    entries: (total ($group.rows | where kind == "entry"))
                    allocs: (total ($group.rows | where kind == "alloc"))
                    style: ($group.rows | where kind == "entry" | get detail.0? | default "")
                } }
                | sort-by entries --reverse | first $top
        } else {
            $operations | each {|op| { impl: $impl.impl, operation: $op.operation, ...(summarise (counted $op.counters $sites) $top) } }
        }
    } | flatten
}
