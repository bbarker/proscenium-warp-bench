# Proscenium (keyed)

[Proscenium](https://share.unison-lang.org/@dfreeman/proscenium) is a UI library written in
[Unison](https://www.unison-lang.org), compiled to WebAssembly (with the GC proposal) by
[warp](https://share.unison-lang.org/@dfreeman/warp).

The app is `bench.jfb.ui`, on the benchmark branches of the Proscenium project (see the
README of the repository this entry comes from). It keeps each row's label in a keyed store
and the selected row in a selector, so an update or a selection re-renders only the rows it
names.

`bundled-dist/` is prebuilt, as for the Rust entries, because a build needs UCM (to compile
the Unison code) and binaryen (warp's optimiser): `build-prod` does nothing. The build:

1. In UCM, on the Proscenium branch: `compile bench.jfb.build jfb-build`.
2. `ucm run.compiled jfb-build.uc -- bare <dir>` writes `jfb-bare.wasm` and its loader.
3. `wasm-opt` with warp's flags (`--enable-gc --enable-multivalue --enable-reference-types
   --enable-tail-call --enable-exception-handling --closed-world -O3 --gufa --converge`),
   then `esbuild --minify` on the loader.
4. Copy the module to `bundled-dist/jfb.opt.wasm` and the loader to
   `bundled-dist/jfb.loader.min.js`.
