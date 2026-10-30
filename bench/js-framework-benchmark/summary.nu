# Tabulates a js-framework-benchmark run: the median of each benchmark for each
# framework, from the checkout's webdriver-ts/results/*.json. CPU benchmarks give
# the median total time (ms, the suite's measure: from the click to the end of the
# frame that paints it) and the script part of it; memory benchmarks give MB.
#
#   nu bench/js-framework-benchmark/summary.nu [--checkout target/js-framework-benchmark] [--copy-to <dir>]
#   nu bench/js-framework-benchmark/summary.nu self-test

const HERE = path self | path dirname

# One result file as a row: framework, benchmark and its medians.
def row-of [result: record] {
    let values = $result.values
    let total = $values | get --optional total.median | default ($values | get --optional DEFAULT.median)
    {
        framework: ($result.framework | str replace --regex '-keyed$' '')
        benchmark: $result.benchmark
        type: $result.type
        median: $total
        script: ($values | get --optional script.median)
    }
}

def "main self-test" [] {
    use std assert
    let cpu = { framework: "x-keyed", benchmark: "01_run1k", type: "cpu", values: { total: { median: 30.5 }, script: { median: 9 } } }
    assert equal (row-of $cpu) { framework: "x", benchmark: "01_run1k", type: "cpu", median: 30.5, script: 9 }
    let memory = { framework: "x-keyed", benchmark: "21_ready-memory", type: "memory", values: { DEFAULT: { median: 0.6 } } }
    assert equal (row-of $memory).median 0.6
    print "summary.nu self-test passed"
}

def main [--checkout: string = "target/js-framework-benchmark", --copy-to: string = ""] {
    let root = $HERE | path dirname | path dirname
    let results = $root | path join $checkout "webdriver-ts" "results"
    let rows = glob ($results | path join "*.json") | each {|file| open $file | row-of $in }
    if $copy_to != "" {
        mkdir $copy_to
        glob ($results | path join "*.json") | each {|file| cp $file $copy_to } | ignore
    }
    $rows | group-by benchmark | transpose benchmark entries | each {|group|
        $group.entries | reduce --fold { benchmark: $group.benchmark } {|entry, acc|
            $acc | insert $entry.framework $entry.median
        }
    } | sort-by benchmark
}
