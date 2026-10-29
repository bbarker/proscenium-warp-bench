#!/usr/bin/env nu

use std/assert

# Generates Round 4 Unison scratch files (Warp pure Wasm List + JSValue direct FFI,
# Ink Reconciler overhaul, and Proscenium direct DOM/HintPath/Trie optimizations).
#
# Outputs are generated outside versioned sources into target/unison/frontend-bench/
# (git-ignored) and loaded into the isolated benchmark codebase.

def root-dir [] {
    $env.FILE_PWD | path join ".." ".." | path expand
}

def out-dir [] {
    root-dir | path join "target" "unison" "frontend-bench"
}

def round4-generators [] {
    $env.FILE_PWD | path join "round4"
}

export def "main self-test" [] {
    let dest = out-dir
    mkdir $dest
    main
    assert ($dest | path join "scratch-warp--perf-list.u" | path exists)
    assert ($dest | path join "scratch-warp--perf-js.u" | path exists)
    assert ($dest | path join "scratch-ink--perf-r4.u" | path exists)
    assert ($dest | path join "scratch-proscenium--perf-r4.u" | path exists)
    assert ((ls ($dest | path join "scratch-warp--perf-list.u") | get 0.size) > 50kb)
    assert ((ls ($dest | path join "scratch-warp--perf-js.u") | get 0.size) > 10kb)
    assert ((ls ($dest | path join "scratch-ink--perf-r4.u") | get 0.size) > 10kb)
    assert ((ls ($dest | path join "scratch-proscenium--perf-r4.u") | get 0.size) > 10kb)
    print "round4 self-test: ok"
}

def main [] {
    let gens = round4-generators
    let dest = out-dir
    mkdir $dest
    ^nu ($gens | path join "gen-warp-list.nu")
    ^nu ($gens | path join "gen-warp-js.nu")
    ^nu ($gens | path join "gen-ink-r4.nu")
    ^nu ($gens | path join "gen-proscenium-r4.nu")
    print $"Generated all Round 4 scratch files in ($dest)"
}
