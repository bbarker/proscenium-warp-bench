# Signals without implicits: a comparison

Written 2026-10-30, as phase 6 of the plan after the author's review. The author's view of
signals is a tradeoff: more bookkeeping up front, in exchange for cheaper updates. Without
implicits, a Unison signals library has three ways to know which signals a computation
reads. This note measures two of them and sizes up the third.

## What was built

`bench.sig` (Proscenium `perf-r7-signals`) is a minimal signals core in Leptos's model.
A view is built once, and each piece of it that depends on a signal is an effect that
updates its own DOM node when the signal changes. Nothing is diffed, and no body runs
again.

- **Signals and effects.** A signal holds its value and the observers that read it since
  it last changed. Setting it empties that list and runs each live observer, which
  subscribes again as it reads. So no list of sources is kept per effect.
- **Owners.** Each piece of view owns the effects made while building it, and its
  cleanups. Removing it disposes its owner, which stops those effects.
- **A selector by key,** as Solid's `createSelector` and Proscenium's `Selector` store
  are. An effect that asks whether its row is selected hears only about that row.
- **A keyed list,** as Leptos's `For` is: an effect that reads the items and reconciles
  the children. It keeps the tree's fast paths: a cleared list, a list built from empty,
  the common prefix and suffix, a swap, and ink's `stableIndices` for the rest. A new row
  is built once, untracked, under an owner of its own.

The core builds DOM directly rather than going through the tree's memos: when a view is
built once, the tree's diff has nothing to do. What it shares with the tree is the
reconcile of keyed children.

The rows app is written on it twice, with the same markup as the other rows apps and
labels from the same generator:

- **`bench.sig.rows`, explicit passing.** The reactive context (the owner and the current
  observer) is an argument: `bench.sig.get ctx label`, and `dynText doc ctx (inner -> ...)`.
- **`bench.sig.rowsA`, an ability.** The context is carried by an ability,
  `bench.sig.Reactive`, with one operation, `context`. A read is
  `bench.sig.read label`, an ability operation. Each effect's body runs under a handler
  that answers `context` with that effect's own context. Nothing in a component's code
  mentions the context.

Both match Leptos over 200 random steps on two seeds.

## The tradeoff, measured

The rows suite, 9 interleaved runs at load about 4 (`results/round7-signals-rows.json`),
median ms until the DOM is done:

| Operation | Leptos | Round 7 on ink | The tree (stores) | **Signals, explicit** | **Signals, ability** |
| --- | --- | --- | --- | --- | --- |
| ready | 25.9 | 25.1 | 22.4 | **17.9** | 21.2 |
| create 1,000 | 28.0 | 82.4 | 70.0 | **29.7** | 32.8 |
| replace 1,000 | 27.6 | 91.2 | 78.2 | **32.1** | 34.4 |
| append 1,000 | 19.1 | 52.8 | 38.2 | **15.5** | 16.8 |
| update every 10th | 1.0 | 7.7 | 5.9 | **1.0** | 1.1 |
| select a row | 0.6 | 0.8 | 0.7 | **0.4** | 0.5 |
| swap rows | 0.7 | 5.4 | 1.8 | 2.2 | **1.7** |
| remove a row | 0.9 | 5.9 | 2.1 | **1.1** | 1.2 |
| clear 2,000 | 16.3 | 39.9 | 43.7 | **12.4** | 15.8 |
| create 10,000 | 170.9 | 617.3 | 433.0 | **163.8** | 178.3 |
| clear 10,000 | 86.3 | 116.5 | 175.1 | 61.6 | **59.3** |
| heap at 10,000 rows (MB) | 9.7 + 21.8 linear | 142.0 | 120.5 | **21.9** | 22.8 |

The module is 19.7 KB brotli (20.1 with the ability), against 31.2 for the tree and 43.0
for round 7. warp builds it in 0.26 s.

**The up-front bookkeeping costs less than the virtual DOM's.** Creating rows takes a
third of the tree's time and about Leptos's. The heap at 10,000 rows is a sixth of the
tree's, and less than Leptos's JS heap and linear memory together. A signal, two effects,
an owner and a selector entry per row cost less than a tree of memo nodes with cells,
keys and records.

**The updates are as cheap as expected.** Update every 10th is 100 signal sets, each
running one text effect: 1.0 ms, Leptos's time, against 5.9 on the tree. Select runs two
effects. Swap and remove are the list's reconcile, the same algorithm as the tree's, and
cost about the same.

So for these apps there is no tradeoff to make: signals win on both sides. The author's
caution holds where views are mostly rebuilt rather than updated, a page whose every
change replaces most of what it shows. None of the suites is like that.

## Explicit passing against an ability

The ability costs **7–10% on building** (create 1,000 32.8 against 29.7 ms, create 10,000
178.3 against 163.8) and **nothing measurable on updates**. That is about 3 µs a row.
Building a row with the ability makes five ability operations (three for the effects
and the cleanup it registers, two for the reads) and installs three handlers (the row,
and each effect's first run). At about 70 ns an operation (warp `handler-cost`,
`docs/TailResumptive.md`), the operations are only a tenth of the difference. The rest is
most likely the three handlers and the continuation-passing code warp compiles for code
that performs `Reactive`, where the explicit row's code is called directly. The split was
not measured. An update makes one operation per effect run.

The ability is what makes the code read like Leptos's: a component never mentions the
context, and `read label` subscribes whatever effect is running. Explicit passing threads
`ctx` through every component and every closure an effect runs, and a mistake (passing
the outer context into an inner effect) silently subscribes the wrong observer.

## Implicits

Unison's implicits RFC (unisonweb/unison pull request #6238, "Implicit parameters for
Unison — RFC + working prototype", open, last updated 2026-10-07) settles the runtime
question by design. Its first principle is that a given is sugar for an ordinary
parameter: after elaboration, a constraint is a positional argument, and the runtime and
code generation learn nothing new. **So implicits would run exactly as explicit passing
does,** 29.7 ms to create 1,000 rows here. warp compiles both the same way.

What they would change is the code. Under the RFC's v1, a sketch of the row:

```unison
get : Ctx => Signal a ->{JS} a
get signal = bench.sig.get summon signal

rowView : Ctx => State -> SRow ->{JS} JSValue
rowView state = cases SRow rowId label ->
  labelText = dynText doc (inner ->
    given here : Ctx = inner
    get label)
  ...
```

Reads lose their argument, and components carry `Ctx =>` in their types rather than a
parameter. But each effect still binds its own context by hand, because the observer
changes at every effect boundary. That would need context function types (Scala 3's
`?=>`, an argument of type `Ctx => Text` elaborated as a lambda), and v1 lists none: its
`=>I` rule covers a binding's own leading lambda, and "partial-application handling" is
listed as not ready. The prototype also changes the codebase format (given and class
marks in namespace metadata), so it was not built and run here. Its runtime cost is
known by construction.

## What this means

- **For warp:** a Unison UI can run at Leptos's speed on today's warp, with no change to
  its continuation handling, when the library builds views once and updates them through
  signals. The cost that rounds 1 to 7 measured was the virtual DOM over ink, not warp.
- **For Proscenium:** its API (`useState`, regions, elements) re-runs bodies and diffs.
  A signals layer would be a different API, or a different implementation of
  `useState` whose readers are effects. Either is Dan's call.
- **For the language:** abilities already give signals without implicits, at 7–10% on
  building and nothing on updates. Implicits would remove that cost but, without context
  functions, not the ceremony at each effect.

## Not done

- **The meals page in this style.** Only the rows app is written on the signals core.
- **Allocation counts.** The suite's time and heap are measured; the instrumented counts
  per row were not taken.

## A UCM bug found on the way

`(Ref.read r)()`, applying a function read from a `Ref` directly, makes UCM 1.5.0 fail at
`run` or `compile` with "wrong number of args for unary unboxed primop:
(REFR,VArg2 1 0)". A two-line repro on `@unison/base` 7.20.0 is in
`unison/ucm-bugs/ref-read-applied.u`, with its transcript. The signals core avoids it by
boxing the effect's body in a data type (`bench.sig.Body`).
