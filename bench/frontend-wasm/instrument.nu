# Counts what a warp module does at run time: every function entry, every
# allocation (`struct.new*`, `array.new*`), every indirect call (`call_ref`) and
# every call to warp's runtime helpers (`apply*`, `continue`, `shift`, `hnd`,
# `force`, `dispatch`, `callDirect`). Each site gets a counter: a call to an added
# function `$__count` with the site's number, placed before the instruction (or
# at the top of the function body, for entries). The counters live in an added,
# exported memory `__counts`, one u32 per site; runtime.mjs reads and clears
# them after each operation when BENCH_COUNT=1. The sites are written beside the
# module as JSON: [{id, kind, func, detail}].
#
# The module is rewritten as text through `wasm-tools print` and `parse`, so it
# keeps its own numbering: the added function, type and memory come after
# everything that was there. It must have no memory of its own.
#
#   nu bench/frontend-wasm/instrument.nu <in.wasm> <out.wasm>
#   nu bench/frontend-wasm/instrument.nu self-test

const HELPERS = [continue apply* applyMany apply0 apply1 apply2 apply3 apply4 apply5 apply6 apply7 apply8
    force shift hnd dispatch callDirect]

def wasm-tools [] {
    let store = ^nix build --no-link --print-out-paths "nixpkgs#wasm-tools" | lines | first
    $store | path join "bin" "wasm-tools"
}

# The function's readable name: its `@name` annotation when it has one, else its `$id`.
def func-name [header: string] {
    let annotated = $header | parse --regex '\(@name "(?<name>[^"]*)"\)'
    if ($annotated | is-not-empty) {
        $annotated.0.name
    } else {
        $header | parse --regex '^\s*\(func \$(?<name>[^ ]+)' | get 0?.name | default "?"
    }
}

# How warp compiled a function, from its header: `cps` takes a frame and a
# continuation (code that may perform abilities, and the pieces after each of its
# calls, named `[n]`), `direct` takes plain arguments and returns a value.
def style-of [header: string] {
    if ($header | str contains '(param $frame') or ($header | str contains '(param (ref $Frame)') { "cps" } else { "direct" }
}

# What a body line counts as, if anything: {kind, detail}.
def site-of [line: string] {
    let op = $line | str trim | split row " "
    let head = $op | first
    let arg = $op | get 1? | default ""
    let callee = $arg | str replace --regex '^\$' ''
    if ($head starts-with "struct.new") or ($head starts-with "array.new") {
        { kind: "alloc", detail: ($arg | str replace --regex '^\$' '') }
    } else if $head in [call_ref return_call_ref] {
        { kind: "call_ref", detail: $head }
    } else if ($head in [call return_call]) and ($callee in $HELPERS) {
        { kind: "helper", detail: $callee }
    } else {
        null
    }
}

def counter [indent: string, id: int] {
    [$"($indent)i32.const ($id)" $"($indent)call $__count"]
}

# The rewritten lines and the sites, from the printed module's lines.
def rewrite [lines: list<string>] {
    let steps = $lines | generate {|line, state|
        let top_level = ($line starts-with "  (") or ($line starts-with "  )") or ($line == ")")
        if ($line starts-with "  (func ") {
            { out: { lines: [$line], sites: [] }, next: ($state | merge { in_func: true, func: (func-name $line), style: (style-of $line), pending: true }) }
        } else if $top_level {
            # Leaving a function: an entry counter still pending goes before its close.
            let entry = if $state.in_func and $state.pending {
                { lines: (counter "    " $state.id), sites: [{ id: $state.id, kind: "entry", func: $state.func, detail: $state.style }] }
            } else {
                { lines: [], sites: [] }
            }
            let next_id = $state.id + ($entry.sites | length)
            { out: { lines: ($entry.lines | append $line), sites: $entry.sites }, next: ($state | merge { in_func: false, pending: false, id: $next_id }) }
        } else if not $state.in_func {
            { out: { lines: [$line], sites: [] }, next: $state }
        } else if $state.pending and ($line | str trim | str starts-with "(local") {
            { out: { lines: [$line], sites: [] }, next: $state }
        } else {
            let indent = $line | parse --regex '^(?<indent>\s*)' | get 0.indent
            let entry = if $state.pending {
                { lines: (counter $indent $state.id), sites: [{ id: $state.id, kind: "entry", func: $state.func, detail: $state.style }] }
            } else {
                { lines: [], sites: [] }
            }
            let id = $state.id + ($entry.sites | length)
            let site = site-of $line
            let counted = if $site == null {
                { lines: [], sites: [] }
            } else {
                { lines: (counter $indent $id), sites: [{ id: $id, kind: $site.kind, func: $state.func, detail: $site.detail }] }
            }
            let next_id = $id + ($counted.sites | length)
            {
                out: { lines: ($entry.lines | append $counted.lines | append $line), sites: ($entry.sites | append $counted.sites) }
                next: ($state | merge { pending: false, id: $next_id })
            }
        }
    } { in_func: false, func: "", style: "", pending: false, id: 0 }
    { lines: ($steps | each { get lines } | flatten), sites: ($steps | each { get sites } | flatten) }
}

# The counter function and its memory, as module fields.
def additions [site_count: int] {
    let pages = ($site_count * 4) // 65536 + 1
    [
        $"  \(memory $__counts ($pages)\)"
        '  (export "__counts" (memory $__counts))'
        '  (func $__count (param $site i32)'
        '    local.get $site'
        '    i32.const 2'
        '    i32.shl'
        '    local.get $site'
        '    i32.const 2'
        '    i32.shl'
        '    i32.load $__counts'
        '    i32.const 1'
        '    i32.add'
        '    i32.store $__counts'
        '  )'
    ]
}

def "main self-test" [] {
    use std assert
    let module = [
        '(module'
        '  (type $T (struct (field i32)))'
        '  (func $f (@name "f") (result (ref $T))'
        '    (local $x i32)'
        '    i32.const 1'
        '    struct.new $T'
        '  )'
        '  (func $g'
        '  )'
        ')'
    ]
    let result = rewrite $module
    assert equal ($result.sites | get kind) [entry alloc entry]
    assert equal ($result.sites | get func) [f f g]
    assert equal ($result.sites | get detail) [direct T direct]
    assert equal ($result.sites | get id) [0 1 2]
    # The entry counter comes after the locals, and each counter before its instruction.
    assert equal ($result.lines | skip 3 | first 6) [
        '    (local $x i32)' '    i32.const 0' '    call $__count' '    i32.const 1' '    i32.const 1' '    call $__count'
    ]
    assert equal (site-of "      return_call $apply1") { kind: "helper", detail: "apply1" }
    assert equal (site-of "      call $name") null
    assert equal (style-of '  (func $k (param $frame (ref $Frame)) (param $k (ref $Continuation))') "cps"
    assert equal (style-of '  (func (;9;) (type 50) (param (ref $Frame) (ref $Continuation) (ref $Value))') "cps"
    assert equal (site-of "    call_ref 19") { kind: "call_ref", detail: "call_ref" }
    print "instrument.nu self-test passed"
}

def main [input: path, output: path] {
    let tools = wasm-tools
    let printed = ^$tools print $input | lines
    if ($printed | any {|line| $line starts-with "  (memory" }) {
        error make { msg: $"($input) has a memory of its own; the counters need the first one" }
    }
    let result = rewrite ($printed | drop 1)
    let text = $result.lines | append (additions ($result.sites | length)) | append ")" | str join "\n"
    let wat = $output | path parse | update extension "wat" | path join
    $text | save --force $wat
    ^$tools parse $wat -o $output
    ^$tools validate $output
    let sites = $output | path parse | update extension "sites.json" | path join
    $result.sites | to json | save --force $sites
    print $"($result.sites | length) sites; ($output), ($sites)"
}
