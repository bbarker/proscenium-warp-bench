# Handlers that resume once, at the end: design note for warp

Written 2026-10-30, as phase 4 of the plan after the author's review. It is a design, not
built yet. It says how warp handles abilities today, what that costs in a UI, and how warp
could skip capturing a continuation for the commonest kind of handler clause.

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
`findFrame`'s walk would grow with each one. That is several days of compiler work. The
smaller change that was made, a shared completion continuation in `hnd` (below), takes
2 of `hnd`'s 5 allocations off every `handle`.

## What it would save

Per operation: the 4 allocations of `shift`, the frame copies of `attachFrame`, the
`Request`, and the 5 of the re-handle, against one call and a two-field result. At 41
operations a row that is at least 370 of round 7's 4,356 allocations a row (8%), plus the
frames copied and the walks repeated on resume. The frames' share is not measured
separately.

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
