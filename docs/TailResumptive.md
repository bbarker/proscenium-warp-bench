# Handlers that resume once, at the end: design note for warp

Written 2026-10-30, as phase 4 of the plan after the author's review. It says how warp
handles abilities today, what that costs in a UI, and how warp could skip capturing a
continuation for the commonest kind of handler clause. The shape was then detected in
warp's codegen ("Detected in warp's codegen", below), and the most it could save was
measured before building it ("The ceiling, measured"). That ceiling is about 3 ms per
1,000 rows created, 2–3% of the time, so the direct path is not built.

## What warp does today

From `internal.runtime.Helper.Handle.define` and `Shift.define` (warp 1.3.0):

- **`handle body with h`** calls `hnd`. It pushes a `Frame` that holds the handler as a
  `Continuation` (`hnd::continue`, whose 2-element `Values` holds the handler and the
  continuation), and returns `hnd::complete` for a normal return. That is 5 allocations.
- **Performing an operation** calls `shift`.
  1. It walks the frame list to the frame that handles the ability (`findFrame`).
  2. It returns that frame's parent as the new stack.
  3. It builds the rest of the computation as a `Continuation` (`shift::continue`) over
     a 3-element `Values`: the current frame and the target frame, each boxed as a
     `Foreign`, and the continuation. That is 4 allocations.
- **The handler** gets a `Request` holding the operation's arguments and that continuation.
- **`resume v`** applies the continuation. `shift::continue` rebuilds the frames between
  the operation and the handler on top of the current stack (`attachFrame`), allocating
  one `Frame` for each, and continues with `v`.
- **A handler that re-handles,** `handle resume v with h'`, the way ink's and
  Proscenium's handlers carry their state, calls `hnd` again: 5 more allocations.

## What it costs in a UI

Creating 1,000 rows on round 7 makes 41 ability operations a row, two per element. The
first is `Render.node`, taken by Proscenium's handler. That handler then performs
`compute_`, taken by ink's. Every clause on that path has the same shape:

```unison
{ op args -> resume } -> ... work ...; handle resume result with handler newState
```

It resumes exactly once, in tail position, and re-handles with new state. Koka and Effekt
compile such a clause without capturing anything: they run the clause at the point of
the operation and return its result there.

## The proposal

Mark a handler **tail-resumptive** at compile time when every one of its operation clauses
is `resume e` or `handle resume e with h' ...` in tail position, with no other use of
`resume`. warp sees the handler's code when it compiles `handle`, so the check is
syntactic.

For a marked handler:

1. **`hnd`** stores, beside the handler, a *clause function* for each operation. It takes
   the operation's arguments and returns the value to resume with and the handler to
   continue under: the same handler, or `h'` with its new state.
2. **`shift`,** on finding the target frame, checks the flag. If it is set, `shift` calls
   the clause function directly, at the point of the operation, with the current stack.
   It stores the returned handler in the target frame, which needs a mutable handler
   field, and continues the operation's own continuation with the returned value. There
   is no `Continuation`, no `Foreign`, no `Values`, no `Request`, no `attachFrame` and no
   new `hnd`.

**The condition that makes it correct.** Run at the point of the operation, the clause
sees the frames between the operation and its handler. In the deep-handler semantics
Unison has, it should not. So the direct path is taken only when no frame in between
handles an ability the clause itself performs. The clause's abilities are known from its
type. `shift` already walks those frames to find the target, so it can check them on
the way. If any of them could catch what the clause performs, `shift` falls back to
today's capture.

Neither hot clause performs nothing, so this condition, rather than "the clause is pure",
is what lets the optimisation apply to UI code:

- **ink's `compute` clause** performs `{g, Stream (Delta a)}`, through `reconcileCompute`.
  The frames in between are Proscenium's `Render` handler, which handles neither, so the
  check passes.
- **Proscenium's `node` clause** performs ink's `Incremental`, and the frames between it
  and the user's code handle only `Render`. The check passes.

## Where it goes in warp's compiler

From warp's code generator (`internal.build.Op.IndirectOp`):

- **An operation** (`IReq.emit`) builds the request's data, the ability's constructor and
  arguments, and calls the `dispatch` helper with the current frame and continuation.
- **A handler** (`IMatchRequest.emit`) tests whether the value it got is a request,
  matches its ability and constructor, and binds the arm's parameters. It then calls
  `shift` (`buildResumeLocal`) to build `resume` before running the arm. So the capture
  happens on the handler's side, once the request has reached it.
- **`handle e with h`** (`IHnd.emit`) pushes the frame through `hnd`. It also allocates a
  fresh `Ids` array of the handled abilities on every `handle`, though that array is a
  constant of the site.

So the direct path needs four things:
1. a second compilation of each qualifying handler's arms, recognised from the arm's
   shape: its body is `resume e`, or `handle (resume e) with h'`;
2. a flag on the handler's frame, which `dispatch` checks before taking the general path;
3. a mutable handler field in the frame;
4. for `handle (resume e) with h'`, replacing the frame's handler with `h'` and
   continuing with `e`, rather than pushing a new frame.

Without the last, every operation would add a handler frame to the stack, and
`findFrame`'s walk would grow with each one. The smaller change that was made, a shared
completion continuation in `hnd` (below), takes 2 of `hnd`'s 5 allocations off every
`handle`.

## Detected in warp's codegen

warp `detect-tail-resumptive` adds a classifier, `internal.build.Op.tailShape`, to
`anfToOps`. Every arm of a request match is classified as warp compiles it, and the
result is reported through `Debug.trace`. The classifier reads UCM's A-normal form, where
an arm that uses its continuation first names `resume` (the builtin `jumpCont` applied to
it). It follows `resume` through each binding: into a closure that captures it once, or
into a partial application that takes it once (warp knows a term's arity from its
signature), which is how `do resume x` compiles. An arm qualifies when it ends in one of
three ways:

- `resume x`;
- `handle resume x with h`;
- a tail call that passes `resume`, or a closure holding it, exactly once.

A `match` along the way qualifies when every branch does.

The UI handlers are written in the third form, not the second. Proscenium's render
handler is a local recursive function, `go ns subkeys body = handle body() with ...`,
and its clauses end `go ns subkeys resume` or `go ns subkeys do resume x`. ink's
reconcile handler is written the same way. So the re-handle the proposal describes
happens in the callee: what it calls is the handler's own function, applied to new state.

Compiling round 7's fine-grained rows app (`results/tail-resumptive-arms-rowsfg.txt`)
classifies 32 arms:

| Shape | Arms | Abilities |
| --- | --- | --- |
| tail call with `resume` | 25 | every arm of `Render` (5), ink's `Incremental` (3, in two handlers), `Stream`, `UseCell` (2), the app's `Rows` (2), `Update`, `Schedule` (5), `Effect` (2), and one of `Extractor.Extract`'s |
| no resume | 2 | `Exception`, and one of `Extract`'s |
| other | 5 | the session's `Yield` and warp's `JS.Async`, which keep the continuation to resume later; `Suspend`, which resumes and then works on; two of `Extract`'s |

Every operation on the path of creating a row is in the first group: `Render` 13 a row,
`Incremental` 12, `Stream` 10, `UseCell` 4 and `Rows` 2 (the report's "Continuations by
ability"). So all 41 operations a row would take a direct path. The arms that do not
qualify keep their continuation by design (pausing the session, awaiting a promise) or
run once per event, not per row.

## The ceiling, measured

Before building the direct path, warp `handler-cost` measures what it could save
(`bench/handler-cost/`). A million operations go through a handler written the way UI
handlers are, `run state body = handle body() with { tick n -> resume } -> run (state + n)
do resume state`. The same work is then done as plain calls to the clause as a function
returning the answer and the new state, which is what a direct path would call. Medians of
15 in headless Chromium 149 (`results/chromium-149.json`):

| | ns per operation |
| --- | --- |
| through the handler, no frame in between | 67–75 |
| through the handler, under 4 other handlers | 104–116 |
| through the handler, under 16 other handlers | 216–248 |
| plain calls | 2.0–2.2 |

Each frame between the operation and its handler adds about 9 ns: the walk to find the
handler, and the copy of the frames when resuming. In the app, operations have almost no
frames in between. Creating 1,000 rows on round 7 makes 41,044 shifts and copies only
4,008 frames (`results/sites-rows-r7.json`). So the no-frame figure is the one that
applies.

That puts the ceiling at about 41,000 × 70 ns, **about 3 ms per 1,000 rows created**.
A real direct path would also find the frame, check its flag, make an indirect call and
build the new handler's closure, so it would save less. Creating 1,000 rows takes about
100–150 ms on round 7, depending on load, so the saving is 2–3%. Interactions perform far
fewer operations than creating rows, and would save less.

That is far less than the operations' share of allocations, about 10%, suggests. The
operations' garbage dies young and is cheap. The cost of creating a row is elsewhere: in
ink's bookkeeping (keys of `Any` segments compared through `Universal.compare`, maps per
element) and in the DOM. A tree of Proscenium's own removed those, and created rows
32–39% faster (`docs/ProsceniumTree.md`).

Building the direct path would take:

- recognising the recursive handler function across two functions, the handler's
  function and the arms' lambda;
- a second compilation of the arms that returns the answer and the new state in place of
  the tail call;
- a frame flag, a mutable handler field and a check in `dispatch`;
- the fallback when a frame in between handles what the clause performs.

That is not worth 2–3%, so it is not built. The classifier stays on its branch, ready for
the case that would change this: a page whose operations sit under many handlers (each
frame adds 9 ns), or a warp whose other costs have fallen far enough that 70 ns an
operation stands out.

## What it would save

Per operation: the 4 allocations of `shift`, the frame copies of `attachFrame`, the
`Request`, and the 5 of the re-handle, against one call and a two-field result. At 41
operations a row that is at least 370 of round 7's 4,356 allocations a row (8%), plus the
frames copied and the walks repeated on resume. In time it is less, 2–3% of creating
rows ("The ceiling, measured", above).

## Risks and what to check

- **Multi-shot continuations:** none is created on the direct path. Handlers that call
  `resume` more than once, or store it, are never marked. Nothing in ink or Proscenium
  resumes twice, measured with every captured continuation made one-shot (warp
  `guard-one-shot`; the report's "One-shot continuations"). `app.Session` stores the
  continuation of `Yield.run` as a value and resumes it once, but `Yield.run`'s handler
  would not be marked, since its `resume` escapes. base's `Each` does resume twice.
- **Handler state:** the frame's handler field becomes mutable. Anything that copies
  frames (`attachFrame`) has to copy the current handler, not the one the frame was built
  with.
- **Tests:** warp's suite, the rows, cards and meals consistency checks, and a new test of
  the fallback, an inner handler that catches what an outer clause performs.

## Relation to the other two directions

- **Stack switching** (`cont.new`, `resume`, `suspend`) would remove the CPS calling
  convention altogether. V8 has it behind `--experimental-wasm-wasmfx`, and warp's encoder
  (waltz) does not support it yet.
- **A tree of Proscenium's own** (`docs/ProsceniumTree.md`) removes one of the two
  operations per element.

The three compose: the tree halves the operations, and this note's path makes the ones
left cheap.
