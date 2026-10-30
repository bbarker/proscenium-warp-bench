# Installs the Proscenium entry into a js-framework-benchmark checkout as
# frameworks/keyed/proscenium (or keyed/proscenium-<variant>), with the bundle
# bench.nu built for that variant: `nu bench/frontend-wasm/bench.nu warp jfb
# --variant <variant>` writes target/frontend-bench/warp/jfb-bare-<variant>/.
#
#   nu bench/js-framework-benchmark/install.nu [--variant r7] [--name proscenium] [--checkout target/js-framework-benchmark]
#   nu bench/js-framework-benchmark/install.nu self-test

const HERE = path self | path dirname

def root-dir [] { $HERE | path dirname | path dirname }

# Where the entry for `name` goes, and its framework version.
def entry-of [name: string, variant: string] {
    { dir: $"frameworks/keyed/($name)", version: $"0.4.3-($variant)" }
}

def "main self-test" [] {
    use std assert
    assert equal (entry-of "proscenium" "r7") { dir: "frameworks/keyed/proscenium", version: "0.4.3-r7" }
    print "install.nu self-test passed"
}

def main [
    --variant: string = "r7"
    --name: string = "proscenium"
    --checkout: string = "target/js-framework-benchmark"
] {
    let root = root-dir
    let entry = entry-of $name $variant
    let built = $root | path join "target" "frontend-bench" "warp" $"jfb-bare-($variant)"
    let dest = $root | path join $checkout $entry.dir
    let dist = $dest | path join "bundled-dist"
    mkdir $dist
    let source = $HERE | path join "keyed-proscenium"
    cp ($source | path join "index.html") ($source | path join "README.md") $dest
    open ($source | path join "package.json")
        | update name $"js-framework-benchmark-keyed-($name)"
        | update js-framework-benchmark.frameworkVersion $entry.version
        | to json --indent 2 | save --force ($dest | path join "package.json")
    cp ($built | path join "jfb-bare.opt.wasm") ($dist | path join "jfb.opt.wasm")
    cp ($built | path join "jfb-bare.loader.min.js") ($dist | path join "jfb.loader.min.js")
    print $"installed ($entry.dir) from ($built)"
}
