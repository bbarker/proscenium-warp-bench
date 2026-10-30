# A tree of Proscenium's own: design note

Written 2026-10-30. The author of Proscenium has said that, given time for performance
work, they would replace ink with something built for Proscenium's use. This note says what
Proscenium takes from ink today, what that costs per element in the measured builds, and
what a tree of Proscenium's own would look like behind the current API. Its floor is
measured ("The floor, measured", below); the prototype behind the API is not built yet.

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
  - This is a change from today. Now, `region` is a keyed `fragment`, which lengthens the
    hint path and runs its body in its parent's render. Only elements are computations
    that ink can skip. So a region's body, and whatever it computes, runs on every render
    of its parent, even when nothing it reads changed. The meals page shows it: setting
    the mascot's pose re-renders the root, and the search region filters all 240 recipes
    again (240 `Text.indexOf` calls), before its elements are skipped. Making the region
    the skip boundary fixes that. Within today's design, it would take a `fragment`
    reconciled as a computation whose result its parent reads (ink's `compute`, not
    `compute_`).
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

## The floor, measured

Before building the tree behind Proscenium's API, its floor was measured: a keyed virtual
DOM in plain Unison with no ink and no Proscenium (`bench.mini`, Proscenium
`perf-r7-mini`; the report's "A floor for a tree without ink"). On the rows app, against
round 7:

- **Allocations:** 1,041 a row instead of 4,198.
- **Creating rows:** 37% less time for 1,000, and 36% less for 10,000.
- **Memory:** 44 MB at 10,000 rows instead of 152.
- **Interactions:** level.

Written through an `Html` ability with one handler, the shape this note proposes, it costs
11 operations and 390 allocations a row more than plain data, and 13–24% more time to
create rows.

Three things the floor needed now belong in the design:

- **The skip.** A memo node, skipped while its input is equal, is what makes interactions
  cheap. This note's region skipped by closure equality is the same thing.
- **Fast paths for children:** matching by position when no keys changed, and trimming
  the common prefix and suffix before the keyed reconcile. Without the trim, removing a
  row allocated eleven times as much.
- **Targeted updates.** A whole-view diff costs selecting a row 70,000 allocations
  against round 7's 2,900. The tree should keep `Keyed` and `Selector`'s targeted
  updates rather than re-run a whole region's body.

## A first prototype behind the API

`bench.tree`, on Proscenium `perf-r7-tree`, is this note's tree for the part of the API the
plain rows app uses:
- **The handler:** one `Render` handler (`bench.tree.collect`) takes `node`,
  `nodeWith`, `fragment`, `useCell` and `currentNamespace`, and builds a tree of
  elements, text nodes and memos.
- **The skip:** each element is a memo of its name, modifiers and body closure. That is
  Proscenium's skip, made at the element as now, with the render's generation added to
  the input when a cell under the element changed.
- **Keys:** a node's key is its path. A region adds its key to the path, so a row keeps
  its key when it moves.
- **Cells:** kept in a map by path. `Update.send` addresses one through ink's `Message`
  key, and every prefix of a changed cell's path is marked, so its ancestors re-run.
- **Children:** the floor's reconcile, plus a swap fast path: after the prefix and suffix
  trim, if the first and last children of what is left swapped places and nothing else
  moved, only those two move.
- **Listeners:** each element listens once per event name, through a cell holding its
  current listeners, so a re-render swaps listeners without touching the DOM.

`bench.rows.ui` runs on it unchanged, and matches Leptos over 200 steps on two seeds.
Against the same source on ink (the report's "A first prototype behind Proscenium's API"):
- **Creating and replacing rows:** 32–39% less time.
- **Small interactions:** update every 10th, swap and remove take 38–65% less.
- **Allocations:** two thirds of ink's per row, with 11 handler operations a row instead
  of 31.
- **Size:** the module is 24 KB brotli against 40 KB.

Then providers, `Keyed` and `Selector`, for round 7's fine-grained rows app:
- **A session like Proscenium's:** the tree is polymorphic in the UI's abilities and runs
  render and events inside `Provider.run`, paused with `Yield` between events.
- **Redraw by owner:** a message to a cell redraws only the element that owns it, as ink
  re-runs only the computation that owns a cell. An element whose body uses a cell is
  registered by path with a cell holding what it drew.

That app runs on it unchanged:
- **Select:** costs the same as on ink, 0.6 ms.
- **Swap and remove:** a third of ink's time.
- **Creating rows:** 12–36% less.
- **Update every 10th:** slower, 9.0 against 5.8 ms. Its cells, dirty marks and registry
  are maps keyed by paths, and comparing paths of `Any` segments dominates. A number per
  path from one global map was tried. It cut the compares to a third, but cost every
  node of a full render a lookup, and creating rows got 17–31% slower. So the open
  question below, path or stable id, has a measured answer.
- **Paths work, if an update never looks them up twice.** Each cell holds its value in a
  cell of its own and names its owner when it is made. A message then changes the value
  in place, and the owner is redrawn directly, with no dirty set and no owner search.
  That cut update every 10th's compares to 42,048, and the fine-grained app became faster
  on the tree than on ink in every operation but append (5% slower) at load 3–4:
  update every 10th 4.8 against 6.0 ms, swap 1.7 against 5.4, create 10,000 389 against
  571. The 400-card page runs on it too, ready in 82 ms against ink's 88.

Not in the prototype yet:
- `Effect`, namespaces, and payloads other than a click's. So the meals app doesn't run on
  it. The 400-card page does, since it needs only elements, text, `useState` and clicks.

**Cleanup, and cells in the mounted tree.** js-framework-benchmark's create-and-clear
memory found the tree keeping removed rows' cells: 61.6 MB. The fix answers this note's
open question about naming nodes:
- **Where cells live:** each memo carries a small store of its own cells. Its view takes
  the store, so a re-render finds its cells there.
- **Messages:** a message names the store and the path.
- **Unmounting:** walks a removed subtree, queues each store's cleanups, and makes one
  registry delete per owner.

Memory after clearing is now 0.96 MB against ink's 1.58. Clearing rows remains about
twice ink's time: each removed row runs two store unsubscribes through the provider.

## Open questions for the prototype

- Whether messages should name a node by path (a list of keys) or by a stable id handed
  out when the node is created. An id is cheaper to deliver to but needs a map from id to
  node.
- Whether the walk should mutate the DOM while it reconciles, or collect the operations
  for each parent and apply them in one batch. The boundary counts say a batch saves at
  most the crossings, about 10% of creating 1,000 rows.
- How much of `KeyState`'s behaviour apps depend on: two unkeyed children of the same tag
  are told apart by count today.
