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
  - **Each subscription records the run that made it,** and is skipped if its observer
    has run since. Without that, an effect that reads two signals re-subscribes to both
    on every run. The one that didn't fire then collects a subscription per run, and
    each one runs the effect again, so the work doubles. The meals page found this: its
    grocery sections read the counts and the checked items, and after about 55 random
    steps the page stopped answering. The rows app never has two sources in one effect.
- **Memos:** a derived signal, set only when its value changes, so its readers hear only
  about real changes.
- **Conditional content** (`show`): built when a condition becomes true, disposed when it
  becomes false.
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

Both match Leptos over 200 random steps on two seeds. The meals page is written on it
once, with explicit passing ("The meals page", below).

## The tradeoff, measured

The rows suite, 9 interleaved runs at load about 2 (`results/round7-signals-rows.json`),
median ms until the DOM is done:

| Operation | Leptos | Round 7 on ink | The tree (stores) | **Signals, explicit** | **Signals, ability** |
| --- | --- | --- | --- | --- | --- |
| ready | 21.2 | 24.8 | 22.2 | **20.4** | 20.3 |
| create 1,000 | 26.4 | 79.9 | 69.2 | **31.2** | 30.2 |
| replace 1,000 | 26.7 | 83.5 | 74.7 | **31.1** | 33.3 |
| append 1,000 | 18.5 | 47.3 | 35.5 | **14.0** | 15.6 |
| update every 10th | 0.7 | 7.4 | 5.9 | **0.8** | 0.9 |
| select a row | 0.6 | 0.7 | 0.7 | **0.4** | 0.4 |
| swap rows | 0.6 | 4.0 | 1.8 | 2.1 | 2.3 |
| remove a row | 1.0 | 4.5 | 1.8 | **1.0** | 1.1 |
| clear 2,000 | 14.6 | 36.2 | 39.1 | 13.1 | **12.2** |
| create 10,000 | 161.1 | 557.6 | 419.4 | **154.8** | 169.1 |
| clear 10,000 | 80.6 | 110.6 | 169.0 | 59.1 | **57.7** |
| heap at 10,000 rows (MB) | 9.7 + 21.8 linear | 141.7 | 120.5 | **25.4** | 26.3 |

The module is 19.9 KB brotli (20.3 with the ability), against 31.2 for the tree and 43.0
for round 7. warp builds it in a quarter of a second.

**The up-front bookkeeping costs less than the virtual DOM's.** Creating 1,000 rows takes
45% of the tree's time and 1.2 times Leptos's. Creating 10,000 takes a little less than
Leptos. The heap at 10,000 rows is a fifth of the tree's, and less than Leptos's JS heap
and linear memory together. A signal, two effects, an owner and a selector entry per row
cost less than a tree of memo nodes with cells, keys and records. A run before the
subscription fix, at load about 4 (`results/round7-signals-rows-first.json`), gave the
same picture with 3.5 MB less heap: stamping each subscription with its run costs that.

**The updates are as cheap as expected.** Update every 10th is 100 signal sets, each
running one text effect: 0.8 ms, about Leptos's time, against 5.9 on the tree. Select
runs two effects. Swap and remove are the list's reconcile, the same algorithm as the
tree's, and cost about the same.

So for these apps there is no tradeoff to make: signals win on both sides. The author's
caution holds where views are mostly rebuilt rather than updated, a page whose every
change replaces most of what it shows. None of the suites is like that.

## The meals page

`bench.sig.meals` is the meals page on the same core, with explicit passing.
- **Signals:** the plan, the pose and the checked items.
- **Memos:** the week resolved against the catalog is a memo of the plan. Each day reads
  a memo of its own day in it, and each meal a memo of its own slot in that. So an edit
  runs only the effects whose values changed. Shuffling a meal sets that slot's texts,
  its day's totals and the grocery counts.
- **Conditional content:** the macros panel, and the week and grocery list before there
  is a plan.
- **The FLIP move** calls the app's own measuring halves directly.
- **The markup** is the same, but for three wrappers around keyed lists (`div.days`, a
  `div.slots` per day, `div.aisles`), since a keyed list owns its parent.

It matches Leptos over 120 steps on two seeds.

Timed with Leptos, round 7 on ink and the tree, 9 interleaved runs at load about 2.5
(`results/round7-signals-meals.json`), median ms until the DOM is done:

| Operation | Leptos | Round 7 on ink | The tree | **Signals** |
| --- | --- | --- | --- | --- |
| ready | 21.7 | 47.4 | 38.2 | **31.0** |
| plan the week | 5.1 | 9.5 | 9.3 | **6.0** |
| re-plan | 1.3 | 4.6 | 2.3 | **2.3** |
| shuffle a meal | 2.1 | 1.1 | **0.9** | 1.5 |
| add a serving | 1.3 | 1.0 | 0.6 | **0.5** |
| remove a meal | 1.4 | 2.2 | **0.7** | **0.7** |
| check an item | 0.4 | 0.8 | 0.5 | **0.3** |
| uncheck an item | 0.3 | 0.8 | 0.4 | **0.2** |
| move a day (FLIP) | 2.0 | 1.6 | 1.1 | **0.9** |
| type 7 keys | 2.2 | 5.0 | 3.9 | **3.7** |
| clear the search | 2.2 | 9.3 | 6.2 | **2.9** |

The module is 29.1 KB brotli against the tree's 38.5 and round 7's 50.5, and warp builds
it in 0.34 s.

- **One meal's edit,** the cheaper update the author's tradeoff promises: adding a
  serving, removing a meal, checking an item and the move are the fastest of the four.
  Shuffling is slower than on the tree, since a new recipe changes the grocery counts,
  and their memos are compared whole.
- **Building:** planning the week is close to Leptos and a third faster than the tree.
  Clearing the search rebuilds 240 results, and is close to Leptos too.
- **Loading** is slower than Leptos, since the page builds its search results with
  effects, but faster than the tree.

## Explicit passing against an ability

The ability costs **up to 10% on building** and **nothing measurable on updates**. Two
runs, before and after the subscription fix:
- **Create 1,000:** 32.8 against 29.7 ms, then 30.2 against 31.2, which is within noise.
- **Create 10,000:** 178.3 against 163.8, then 169.1 against 154.8, 9% both times.
- **Replace and append 1,000:** 7–11% in the second run.

At 10,000 rows that is about 1.4 µs a row. Building a row with the ability makes five
ability operations (three for the effects and the cleanup it registers, two for the
reads) and installs three handlers (the row, and each effect's first run). At about 70 ns
an operation (warp `handler-cost`, `docs/TailResumptive.md`), the operations are a
quarter of the difference. The rest is
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
does.** warp compiles both the same way.

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
- **For the language:** abilities already give signals without implicits, at up to 10%
  on building and nothing on updates. Implicits would remove that cost but, without context
  functions, not the ceremony at each effect.

## Not done

- **Allocation counts.** The suites' time and heap are measured; the instrumented counts
  per row were not taken.
- **Glitch-free propagation.** An effect that reads a memo and that memo's source would
  run twice for one change, the first time with the memo's old value. The apps here are
  written so that no effect does (the search note reads only the memo of the query and
  its matches). Leptos and Solid order updates so that it cannot happen.

## A UCM bug found on the way

`(Ref.read r)()`, applying a function read from a `Ref` directly, makes UCM 1.5.0 fail at
`run` or `compile` with "wrong number of args for unary unboxed primop:
(REFR,VArg2 1 0)". A two-line repro on `@unison/base` 7.20.0 is in
`unison/ucm-bugs/ref-read-applied.u`, with its transcript. The signals core avoids it by
boxing the effect's body in a data type (`bench.sig.Body`).
