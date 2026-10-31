#!/usr/bin/env nu

use std/assert

# Builds and measures the frontend benchmark's two halves
# (docs/reports/FrontendWasmLeptosVsProscenium.md):
#
#   nu bench/frontend-wasm/bench.nu leptos <app> [--dev] [--cold]
#   nu bench/frontend-wasm/bench.nu warp <app> [--config bare|debug]
#   nu bench/frontend-wasm/bench.nu warp-incremental <cards-count>
#   nu bench/frontend-wasm/bench.nu self-test
#
# `<app>` is counter, rows or cards (the Leptos crate) / counter, rows or
# cards-<count> (the Unison entry). Every step is timed on its own -
# compile, wasm-bindgen, wasm-opt, esbuild - and each result is appended,
# with the machine's load average, to `results/builds.jsonl`, because the
# machine is shared and a number without its load is half a number.
#
# The Leptos half builds the way `cargo xtask web` does (release profile,
# fat LTO, wasm-bindgen 0.2.129 `--target web`, wasm-pack's wasm-opt 117 at
# `-O`). The Unison half runs a compiled warp build entry from
# `target/unison/frontend-bench/` (made in the bench codebase, see the
# report), then wasm-opt 133 with warp's own production flags and esbuild
# `--minify`, which is what warp's `prodDefaults` would run.

const WASM_BINDGEN = "~/.cache/.wasm-pack/wasm-bindgen-9411bdb1a3e2bbb9/wasm-bindgen"
const WASM_OPT_SHIPPED = "~/.cache/.wasm-pack/wasm-opt-1ceaaea8b7b5f7e0/bin/wasm-opt"

# warp's `wasmOpt` optimizer flags with reflection off (`Optimizer.wasmOpt`).
const WARP_WASM_OPT_FLAGS = [
    --enable-gc --enable-multivalue --enable-reference-types --enable-tail-call
    --enable-exception-handling --closed-world -O3 --gufa --converge
]

def bench-dir [] { $env.FILE_PWD }
def root-dir [] { bench-dir | path dirname | path dirname }
def out-dir [] { root-dir | path join "target" "frontend-bench" }
def results-file [] { bench-dir | path join "results" "builds.jsonl" }
# Cargo's target directory for the bench workspace (set explicitly: the
# devShell's cargo shim would otherwise pick one per checkout).
def cargo-target [] { out-dir | path join "cargo" }

# A tool from nixpkgs, built (or found in the store) on first use.
def nix-tool [package: string, binary: string] {
    let store = ^nix build --no-link --print-out-paths $"nixpkgs#($package)" | lines | first
    $store | path join "bin" $binary
}

def load-average [] {
    open /proc/loadavg | split row " " | first 3 | into float
}

# Seconds a closure takes, with its result.
def timed [step: closure] {
    let started = date now
    let result = do $step
    { seconds: (((date now) - $started) / 1sec | math round --precision 2), result: $result }
}

# Raw, gzip -9 and brotli -q 11 sizes of a file.
export def sizes [file: path] {
    {
        raw: (ls $file | get 0.size | into int)
        gzip: (^gzip -9 -c $file | bytes length)
        brotli: (^brotli -q 11 -c $file | bytes length)
    }
}

def record [entry: record] {
    let line = $entry | merge { at: (date now | format date "%Y-%m-%dT%H:%M:%S"), load: (load-average) }
    mkdir (results-file | path dirname)
    $line | to json --raw | $"($in)\n" | save --append (results-file)
    $line
}

def run-or-fail [what: string, step: closure] {
    let done = do $step | complete
    if $done.exit_code != 0 {
        print -e $done.stdout $done.stderr
        error make { msg: $"($what) failed with exit code ($done.exit_code)" }
    }
    $done
}

# Builds one Leptos app and measures every step.
def "main leptos" [
    app: string   # counter, rows or cards
    --dev         # cargo's dev profile and no wasm-opt: the styling loop
    --cold        # without sccache, so dependencies really compile
    --touch       # touch the crate's source first, so its own compile is timed
    --label: string = ""  # a note kept with the result (e.g. "edit", "cards-200")
    --name: string        # the output directory's name (default: the app); cards-<count> for the scaling app
    --stack-mb: int = 0   # the wasm stack in MiB (0: the linker's default), which a dev build of 400 cards needs to mount
] {
    let rustflags = if $stack_mb > 0 { $"-C link-arg=-zstack-size=($stack_mb * 1024 * 1024)" } else { "" }
    let crate = $"bench-($app)"
    let profile = if $dev { "dev" } else { "release" }
    let profile_dir = if $dev { "debug" } else { "release" }
    let workspace = bench-dir | path join "leptos"
    let wrapper = if $cold { "" } else { $env.RUSTC_WRAPPER? | default "" }
    if $touch { ^touch ($workspace | path join $app "src" "lib.rs") }
    let compile = timed {
        run-or-fail "cargo build" {
            cd $workspace
            with-env { RUSTC_WRAPPER: $wrapper, RUSTFLAGS: $rustflags, CARGO_TARGET_DIR: (cargo-target) } {
                ^cargo build --profile $profile --target wasm32-unknown-unknown -p $crate
            }
        }
    }
    let wasm_in = cargo-target | path join "wasm32-unknown-unknown" $profile_dir $"($crate | str replace --all '-' '_').wasm"
    let dest = out-dir | path join "leptos" $"($name | default $app)-($profile)"
    mkdir $dest
    let bindgen = timed {
        run-or-fail "wasm-bindgen" { ^($WASM_BINDGEN | path expand) --target web --out-dir $dest --no-typescript $wasm_in }
    }
    let wasm_out = $dest | path join $"($crate | str replace --all '-' '_')_bg.wasm"
    let js_out = $dest | path join $"($crate | str replace --all '-' '_').js"
    let before_opt = sizes $wasm_out
    let opt = if $dev { { seconds: 0, result: null } } else {
        timed { run-or-fail "wasm-opt" { ^($WASM_OPT_SHIPPED | path expand) -O $wasm_out -o $wasm_out } }
    }
    record {
        kind: "leptos", app: ($name | default $app), profile: $profile, cold: $cold, label: $label
        compile_s: $compile.seconds, bindgen_s: $bindgen.seconds, wasm_opt_s: $opt.seconds
        total_s: ($compile.seconds + $bindgen.seconds + $opt.seconds)
        wasm_unoptimized: $before_opt, wasm: (sizes $wasm_out), js: (sizes $js_out)
    }
}

# The compiled warp build entry for `app`, from the branch `variant` names
# (`""` for the bench branch, `perf` for the branch with the library experiments).
def warp-entry [app: string, variant: string] {
    let suffix = if $variant == "" { "" } else { $"-($variant)" }
    root-dir | path join "target" "unison" "frontend-bench" $"($app)-build($suffix).uc"
}

# Builds one Unison app with warp and measures every step.
def "main warp" [
    app: string                 # counter, rows or cards-<count>
    --config: string = "bare"   # bare (no debug names) or debug
    --variant: string = ""      # the build entry's branch: "" (bench) or perf
    --label: string = ""
] {
    let suffix = if $variant == "" { "" } else { $"-($variant)" }
    let dest = out-dir | path join "warp" $"($app)-($config)($suffix)"
    mkdir $dest
    let entry = warp-entry $app $variant
    let build = timed { run-or-fail "warp build" { ^ucm run.compiled $entry -- $config $dest } }
    let phases = $build.result.stdout | lines | where {|line| $line starts-with "{" } | last | from json
    let stem = $phases.build
    let wasm = $dest | path join $"($stem).wasm"
    let loader = $dest | path join $"($stem).loader.js"
    let raw = sizes $wasm
    let raw_loader = sizes $loader
    let wasm_opt = nix-tool "binaryen" "wasm-opt"
    let opt_out = $dest | path join $"($stem).opt.wasm"
    let opt = timed { run-or-fail "wasm-opt" { ^$wasm_opt $wasm -o $opt_out ...$WARP_WASM_OPT_FLAGS } }
    let esbuild = nix-tool "esbuild" "esbuild"
    let min_out = $dest | path join $"($stem).loader.min.js"
    let minify = timed { run-or-fail "esbuild" { ^$esbuild --minify $"--outfile=($min_out)" $loader } }
    record {
        kind: "warp", app: $app, config: $config, variant: $variant, label: $label
        process_s: $build.seconds, warp_ms: $phases.done, phases: $phases
        wasm_opt_s: $opt.seconds, esbuild_s: $minify.seconds
        total_s: ($build.seconds + $opt.seconds + $minify.seconds)
        wasm_unoptimized: $raw, wasm: (sizes $opt_out), js_unminified: $raw_loader, js: (sizes $min_out)
    }
}

# warp's in-process rebuilds for the cards app: a full build, a full build
# of the edited UI, and the edited UI as a delta, in one process.
def "main warp-incremental" [
    count: int
    --config: string = "bare"
] {
    let dest = out-dir | path join "warp" $"cards-($count)-incremental"
    mkdir $dest
    let entry = root-dir | path join "target" "unison" "frontend-bench" $"cards-($count)-incremental.uc"
    let build = timed { run-or-fail "warp incremental build" { ^ucm run.compiled $entry -- $config $dest } }
    let runs = $build.result.stdout | lines | where {|line| $line starts-with "{" } | each { from json }
    $runs | each {|run|
        record {
            kind: "warp-incremental", app: $"cards-($count)", config: $config, build: $run.build
            warp_ms: $run.done, emitted: $run.emitted, phases: $run
            wasm: (sizes ($dest | path join $"($run.build).wasm"))
        }
    }
}

def "main self-test" [] {
    let file = mktemp --tmpdir
    "hello hello hello hello" | save --force $file
    let measured = sizes $file
    assert equal $measured.raw 23
    assert ($measured.gzip > 0)
    assert ($measured.brotli > 0)
    rm $file
    assert equal ($WARP_WASM_OPT_FLAGS | where {|flag| $flag == "--closed-world" } | length) 1
    print "bench self-test: ok"
}

def main [] {
    print "usage: nu bench/frontend-wasm/bench.nu (leptos|warp|warp-incremental|self-test) ..."
}
