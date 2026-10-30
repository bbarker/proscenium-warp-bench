# A tree of Proscenium's own: design note

Written 2026-10-30. The author of Proscenium has said that, given time for performance
work, he would replace ink with something built for Proscenium's use. This note says what
Proscenium takes from ink today, what that costs per element in the measured builds, and
what a tree of Proscenium's own would look like behind the current API. The prototype is
not built yet; the plan is `/var/workspace/ProsceniumWarpReviewPlan.md`, phase 5.

## What Proscenium takes from ink

All of it goes through one function, `dom.internal.render`. It handles the `Render`
ability (`fragment`, `currentNamespace`, `node`, `nodeWith`, `useCell`) and turns each
operation into ink's:

| Proscenium | ink |
| --- | --- |
| `node key value body`: an element, a text node or a custom node | `compute_ hint body`: a computation whose result its parent never reads |
| `nodeWith key body`: an element whose modifiers its body computes (round 2) | `compute_` |
| `useCell def`: a component's state | `cell hint def` |
| `fragment ns key body`: a region or a namespace | a longer hint path (`appendRegion`) |
| the whole tree, each render | `reconcileWithDeltas messages previous`, which emits `Delta (Node g)` on a `Stream` |

Everything else in Proscenium sits on either side of that function:

- **Above it:** the `Render` builders (`element*`, `region`, the modifiers and events), the
  stores (`Keyed`, `Selector`) and the session (`app.Session`: actions, effects,
  suspension, providers).
- **Below it:** the DOM sync, which applies the `Delta`s to the page and keeps an index of
  live nodes.

ink itself provides keys built from hints (`KeyState`, a map of counts per hint), records
of each computation and cell (`ComputeRecord`, `CellRecord`, `IncrementalNode`), the
lookup of previous children (by position since round 5, else a map), and the keyed
reconcile of children (`reconcileChildren`, longest increasing run since round 1). It also
delivers messages to cells: each message names the key of the cell it updates, and since
round 2 it re-runs only the computation that owns that cell.

Of that, Proscenium needs the ordered keyed tree, the state slots, targeted re-rendering
and the keyed reconcile. Three things exist only because ink is general, for any result
type and not only DOM nodes:

- keys as lists of `Any` segments, hashed and compared through `Universal.compare`;
- the result of every computation kept in its record;
- the `Delta` stream between reconcile and the DOM.

## What it costs, per element

From the round 7 counts ("Measured attribution" in the report, `results/sites-rows-r7.json`),
creating 1,000 rows of 10 DOM nodes each:

- **41 ability operations a row.** Each element is two: `Render.node`, taken by
  Proscenium's handler, then `compute_`, taken by ink's. Each is a `shift` (4
  allocations, a walk of the frame list), plus a re-handle (`hnd`, 5 allocations) when the
  handler resumes. Cells and the stores' reads add the rest.
- **4,356 allocations a row:** `Values` arrays 1,764, `Data` 815, `Continuation` 376, `List`
  328, `Closure` 309, boxed numbers 270. Garbage collection is the largest single cost
  in a CPU profile (43 of about 200 ms, at high load).
- **Bookkeeping that is ink's alone:** per element, a key (`Any k +: subkeys`), a
  `KeyState` map update, a `ComputeRecord` and an `IncrementalNode`, an append to the
  siblings list, a previous-children lookup, and a `Delta` value sent through the stream.

## The design

One handler, Proscenium's, and a retained tree of Proscenium's own nodes.

- **A node** holds its key, its kind (element and namespace, text, custom), its last
  modifiers, its children in order, its state slots, its last body closure and its DOM
  node.
- **Rendering a region** runs its body under the `Render` handler with a cursor into
  that node's previous children. The cursor tries the next child first, as ink's round 5
  lookup does, and falls back to an index by key built only after a few misses.
- **Skipping:**
  - A region whose body closure equals its previous one (`Universal.==`, now entirely
    in wasm for closures) is reused whole, as ink skips an unchanged computation.
  - A region with pending messages is never skipped.
- **State slots** are numbered by call order within their node. A message names the
  node's path and the slot, and marks that node for re-rendering. The next flush
  re-renders only the marked nodes, outermost first, which is what ink's `compute_` gives
  today.
- **The DOM is patched during the walk:**
  - A new element is created and its children appended to it, bottom-up, before it is
    inserted, as round 5's sync does now.
  - A changed modifier is applied in place.
  - Moved keyed children are reordered with the longest-increasing-run algorithm from
    ink's round 1 rewrite.

  There is no `Delta` value and no separate sync pass.
- **Keys** are the user's key value and the node's position among its siblings, compared
  only among siblings, with no path of segments.
- **Bookkeeping** stays persistent (lists and records), as now, until a measurement says
  mutable arrays would pay. warp's `List` is already a wasm tree of arrays.

Per element that removes one of the two ability operations, every `Delta`, the key list
and the `KeyState` map. It also removes ink's records, replaced by one node.

## What stays the same

- **The public API:** `useState`, `region`, `element`, `elementWith`, `voidElement`, the
  `el.*` builders, modifiers and events, `Keyed`, `Selector`, providers and `mount`.
  The rows, cards, meals and js-framework-benchmark apps compile unchanged.
- **The session:** `app.Session`'s action queue, effects, suspension and providers are
  above the tree and do not change.
- **The checks:** `consistency.mjs`, `cards-check.mjs` and `meals-check.mjs` must pass
  unchanged, and the boundary and site counts are taken again to show what the tree
  removed.

## Open questions for the prototype

- Whether messages should name a node by path (a list of keys) or by a stable id handed
  out when the node is created. An id is cheaper to deliver to but needs a map from id to
  node.
- Whether the walk should mutate the DOM while it reconciles, or collect the operations
  for each parent and apply them in one batch. The boundary counts say a batch saves at
  most the crossings, about 10% of creating 1,000 rows.
- How much of `KeyState`'s behaviour apps depend on: two unkeyed children of the same tag
  are told apart by count today.
