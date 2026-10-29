Run `nu bench/frontend-wasm/round4.nu` first, then run this transcript with
`ucm -c target/unison-bench-codebase transcript.in-place bench/frontend-wasm/round4.md`.
These branch names must be unused. This operates only on the isolated benchmark copy.

``` ucm
@dfreeman/warp/perf> branch perf-r4

  Done. I've created the perf-r4 branch based off of perf.

  Tip: To merge your work back into the perf branch, first
       `switch /perf` then `merge /perf-r4`.

@dfreeman/warp/perf-r4> load target/unison/frontend-bench/scratch-warp--perf-list.u

  Loading changes detected in
  target/unison/frontend-bench/scratch-warp--perf-list.u.

  + internal.javascript.supportJS.listFromArrayJS : Text
  + internal.javascript.supportJS.listToArrayJS   : Text
  + internal.runtime.Helper.BuildSeq.define.doc   : Doc
  + internal.runtime.ListOps.emitBalance          : TypeIdx
                                                    -> GlobalReference
                                                    ->{TypeCtx,
                                                    ModuleCtx} ( FuncReference,
                                                      FuncReference)
  + internal.runtime.ListOps.emitBalance.doc      : Doc
  + internal.runtime.ListOps.emitConcat           : TypeIdx
                                                    -> TypeIdx
                                                    -> TypeIdx
                                                    -> GlobalReference
                                                    ->{TypeCtx,
                                                    ModuleCtx} ( FuncReference,
                                                      FuncReference)
  + internal.runtime.ListOps.emitConcat.doc       : Doc
  + internal.runtime.ListOps.emitEmpty            : TypeIdx
                                                    -> TypeIdx
                                                    ->{TypeCtx,
                                                    ModuleCtx} ( GlobalReference,
                                                      GlobalReference)
  + internal.runtime.ListOps.emitEmpty.doc        : Doc
  + internal.runtime.ListOps.emitSeqAt            : TypeIdx
                                                    -> TypeIdx
                                                    -> TypeIdx
                                                    ->{TypeCtx,
                                                    ModuleCtx} FuncReference
  + internal.runtime.ListOps.emitSeqAt.doc        : Doc
  + tests.builtins.list                           : WasmTest
  + tests.builtins.list.doc                       : Doc
  ~ internal.javascript.devtoolsJS                                                  : Text
  ~ internal.javascript.supportJS                                                   : [( Text,
                                                                                        Text)]
  ~ internal.javascript.supportJS.buildSeqJS                                        : Text
  ~ internal.javascript.supportJS.toDebugStringJS                                   : Text
  ~ internal.runtime.Helper.BuildSeq.define                                         : Types
                                                                                      ->{TypeCtx,
                                                                                      ModuleCtx} FuncReference
  ~ internal.runtime.replacements.unison_base.Bytes_fromList                        : Replacement
  ~ internal.runtime.replacements.unison_base.Bytes_toList                          : Replacement
  ~ internal.runtime.replacements.unison_base.Char_Class_anyOf                      : Replacement
  ~ internal.runtime.replacements.unison_base.List_append                           : Replacement
  ~ internal.runtime.replacements.unison_base.List_at                               : Replacement
  ~ internal.runtime.replacements.unison_base.List_cons                             : Replacement
  ~ internal.runtime.replacements.unison_base.List_drop                             : Replacement
  ~ internal.runtime.replacements.unison_base.List_empty                            : Replacement
  ~ internal.runtime.replacements.unison_base.List_size                             : Replacement
  ~ internal.runtime.replacements.unison_base.List_snoc                             : Replacement
  ~ internal.runtime.replacements.unison_base.List_take                             : Replacement
  ~ internal.runtime.replacements.unison_base.List_viewl                            : Replacement
  ~ internal.runtime.replacements.unison_base.List_viewr                            : Replacement
  ~ internal.runtime.replacements.unison_base.Pattern_join                          : Replacement
  ~ internal.runtime.replacements.unison_base.Pattern_run                           : Replacement
  ~ internal.runtime.replacements.unison_base.Text_fromCharList                     : Replacement
  ~ internal.runtime.replacements.unison_base.Text_toCharList                       : Replacement
  ~ internal.runtime.replacements.unison_base.Universal_compare.defineCompareValues : Runtime
                                                                                      -> GlobalReference
                                                                                      -> FuncReference
                                                                                      ->{TypeCtx,
                                                                                      ModuleCtx} FuncReference
  ~ internal.runtime.replacements.unison_base.Universal_compare.jsSource            : Text
  ~ internal.runtime.replacements.unison_base.Universal_eq.defineEqValues           : Runtime
                                                                                      -> GlobalReference
                                                                                      -> FuncReference
                                                                                      ->{TypeCtx,
                                                                                      ModuleCtx} FuncReference
  ~ internal.runtime.replacements.unison_base.Universal_eq.jsSource                 : Text
  ~ internal.runtime.replacements.unison_base.Value_load                            : Replacement
  ~ internal.runtime.replacements.unison_base.Value_value                           : Replacement
  ~ internal.runtime.replacements.warp_js.JSValue_array                             : Replacement
  ~ internal.runtime.replacements.warp_js.JSValue_asList                            : Replacement
  ~ internal.runtime.replacements.warp_js.JSValue_call                              : Replacement
  ~ internal.runtime.replacements.warp_js.JSValue_function                          : Replacement
  ~ internal.runtime.replacements.warp_js.JSValue_new                               : Replacement
  ~ internal.runtime.replacements.warp_js.JSValue_object                            : Replacement
  ~ internal.runtime.Runtime.defineTypes                                            : Boolean
                                                                                      ->{TypeCtx,
                                                                                      ModuleCtx} Types
  ~ tests.builtins                                                                  : [WasmTest]

  + (added), ~ (modified)

  Run `update` to apply these changes to your codebase.

@dfreeman/warp/perf-r4> update

  Done.

@dfreeman/warp/perf-r4> load target/unison/frontend-bench/scratch-warp--perf-js.u

  Loading changes detected in
  target/unison/frontend-bench/scratch-warp--perf-js.u.

  + internal.javascript.supportJS.jsValueJS.doc                       : Doc
  + internal.runtime.replacements.doc                                 : Doc
  + internal.runtime.replacements.warp_js.JSValue_callback1_          : Replacement
  + internal.runtime.replacements.warp_js.JSValue_callback1_.doc      : Doc
  + internal.runtime.replacements.warp_js.JSValue_getProperty         : Replacement
  + internal.runtime.replacements.warp_js.JSValue_getProperty.doc     : Doc
  + internal.runtime.replacements.warp_js.JSValue_invoke0             : Replacement
  + internal.runtime.replacements.warp_js.JSValue_invoke0.doc         : Doc
  + internal.runtime.replacements.warp_js.JSValue_invoke0_            : Replacement
  + internal.runtime.replacements.warp_js.JSValue_invoke0_.doc        : Doc
  + internal.runtime.replacements.warp_js.JSValue_invoke1_            : Replacement
  + internal.runtime.replacements.warp_js.JSValue_invoke1_.doc        : Doc
  + internal.runtime.replacements.warp_js.JSValue_invokeText1         : Replacement
  + internal.runtime.replacements.warp_js.JSValue_invokeText1.doc     : Doc
  + internal.runtime.replacements.warp_js.JSValue_invokeText1_        : Replacement
  + internal.runtime.replacements.warp_js.JSValue_invokeText1_.doc    : Doc
  + internal.runtime.replacements.warp_js.JSValue_invokeText2         : Replacement
  + internal.runtime.replacements.warp_js.JSValue_invokeText2.doc     : Doc
  + internal.runtime.replacements.warp_js.JSValue_invokeText2_        : Replacement
  + internal.runtime.replacements.warp_js.JSValue_invokeText2_.doc    : Doc
  + internal.runtime.replacements.warp_js.JSValue_invokeText3_        : Replacement
  + internal.runtime.replacements.warp_js.JSValue_invokeText3_.doc    : Doc
  + internal.runtime.replacements.warp_js.JSValue_invokeTextVal_      : Replacement
  + internal.runtime.replacements.warp_js.JSValue_invokeTextVal_.doc  : Doc
  + internal.runtime.replacements.warp_js.JSValue_setProperty         : Replacement
  + internal.runtime.replacements.warp_js.JSValue_setProperty.doc     : Doc
  + internal.runtime.replacements.warp_js.JSValue_setPropertyText     : Replacement
  + internal.runtime.replacements.warp_js.JSValue_setPropertyText.doc : Doc
  + JSValue.callback1_                                                : (JSValue
                                                                         ->{JS} a)
                                                                        ->{JS} JSValue
  + JSValue.callback1_.doc                                            : Doc
  + JSValue.getProperty                                               : Text
                                                                        -> JSValue
                                                                        ->{JS} JSValue
  + JSValue.getProperty.doc                                           : Doc
  + JSValue.invoke0                                                   : Text
                                                                        -> JSValue
                                                                        ->{JS} JSValue
  + JSValue.invoke0.doc                                               : Doc
  + JSValue.invoke0_                                                  : Text
                                                                        -> JSValue
                                                                        ->{JS} ()
  + JSValue.invoke0_.doc                                              : Doc
  + JSValue.invoke1_                                                  : Text
                                                                        -> JSValue
                                                                        -> JSValue
                                                                        ->{JS} ()
  + JSValue.invoke1_.doc                                              : Doc
  + JSValue.invokeText1                                               : Text
                                                                        -> Text
                                                                        -> JSValue
                                                                        ->{JS} JSValue
  + JSValue.invokeText1.doc                                           : Doc
  + JSValue.invokeText1_                                              : Text
                                                                        -> Text
                                                                        -> JSValue
                                                                        ->{JS} ()
  + JSValue.invokeText1_.doc                                          : Doc
  + JSValue.invokeText2                                               : Text
                                                                        -> Text
                                                                        -> Text
                                                                        -> JSValue
                                                                        ->{JS} JSValue
  + JSValue.invokeText2.doc                                           : Doc
  + JSValue.invokeText2_                                              : Text
                                                                        -> Text
                                                                        -> Text
                                                                        -> JSValue
                                                                        ->{JS} ()
  + JSValue.invokeText2_.doc                                          : Doc
  + JSValue.invokeText3_                                              : Text
                                                                        -> Text
                                                                        -> Text
                                                                        -> Text
                                                                        -> JSValue
                                                                        ->{JS} ()
  + JSValue.invokeText3_.doc                                          : Doc
  + JSValue.invokeTextVal_                                            : Text
                                                                        -> Text
                                                                        -> JSValue
                                                                        -> JSValue
                                                                        ->{JS} ()
  + JSValue.invokeTextVal_.doc                                        : Doc
  + JSValue.setProperty                                               : Text
                                                                        -> JSValue
                                                                        -> JSValue
                                                                        ->{JS} ()
  + JSValue.setProperty.doc                                           : Doc
  + JSValue.setPropertyText                                           : Text
                                                                        -> Text
                                                                        -> JSValue
                                                                        ->{JS} ()
  + JSValue.setPropertyText.doc                                       : Doc
  + tests.js.doc                                                      : Doc
  + tests.js.jsDirectFastPaths                                        : WasmTest
  + tests.js.jsDirectFastPaths.doc                                    : Doc
  ~ internal.javascript.supportJS.jsValueJS : Text
  ~ internal.runtime.replacements           : BuildConfig
                                              ->{IO, Exception} Map
                                                Reference
                                                Replacement
  ~ tests.js                                : [WasmTest]

  + (added), ~ (modified)

  Run `update` to apply these changes to your codebase.

@dfreeman/warp/perf-r4> update

  Done.

@dfreeman/warp/perf-r4> run tests

  [Ok "Passed"]

@dfreeman/ink/perf> branch perf-r4

  Done. I've created the perf-r4 branch based off of perf.

  Tip: To merge your work back into the perf branch, first
       `switch /perf` then `merge /perf-r4`.

@dfreeman/ink/perf-r4> load target/unison/frontend-bench/scratch-ink--perf-r4.u

  Loading changes detected in
  target/unison/frontend-bench/scratch-ink--perf-r4.u.

  ~ structural type Incremental.reconcile.KeyState
  ~ structural type Incremental.reconcile.PreviousChildren a g

  + (>)                                                            : ∀ test tests.reconcileFastPaths.
                                                                       test
                                                                       -> tests.reconcileFastPaths
                                                                       -> [Result]
  + >.doc                                                          : Doc
  + Incremental.reconcile.childSegment                             : Key
                                                                     -> Segment
  + Incremental.reconcile.childSegment.doc                         : Doc
  + Incremental.reconcile.descend                                  : Key
                                                                     -> Nat
                                                                     -> [Message]
                                                                     -> ComputeRecord
                                                                       a
                                                                       g
                                                                     ->{g,
                                                                     Stream
                                                                       (Delta
                                                                         a)} Optional
                                                                       (ComputeRecord
                                                                         a
                                                                         g)
  + Incremental.reconcile.descend.doc                              : Doc
  + Incremental.reconcile.handler.doc                              : Doc
  + Incremental.reconcile.KeyState.doc                             : Doc
  + Incremental.reconcile.KeyState.enter.doc                       : Doc
  + Incremental.reconcile.KeyState.nextKey.doc                     : Doc
  + Incremental.reconcile.KeyState.root.doc                        : Doc
  + Incremental.reconcile.KeyState.segments.doc                    : Doc
  + Incremental.reconcile.mountCompute                             : Location
                                                                     -> Key
                                                                     -> '{g,
                                                                     Incremental
                                                                       a
                                                                       g} a
                                                                     ->{g,
                                                                     Stream
                                                                       (Delta
                                                                         a)} ComputeRecord
                                                                       a
                                                                       g
  + Incremental.reconcile.mountCompute.doc                         : Doc
  + Incremental.reconcile.mountHandler                             : Location
                                                                     -> KeyState
                                                                     -> [IncrementalNode
                                                                       a
                                                                       g]
                                                                     -> Request
                                                                       {g,
                                                                       Incremental
                                                                         a
                                                                         g}
                                                                       a
                                                                     ->{g,
                                                                     Stream
                                                                       (Delta
                                                                         a)} ( a,
                                                                       [IncrementalNode
                                                                       a
                                                                       g])
  + Incremental.reconcile.mountHandler.doc                         : Doc
  + Incremental.reconcile.PreviousChildren.doc                     : Doc
  + Incremental.reconcile.PreviousChildren.lookup.doc              : Doc
  + Incremental.reconcile.PreviousChildren.lookupCellRecord.doc    : Doc
  + Incremental.reconcile.PreviousChildren.lookupComputeRecord.doc : Doc
  + Incremental.reconcile.PreviousChildren.of.doc                  : Doc
  + Incremental.reconcile.reconcileCell.doc                        : Doc
  + Incremental.reconcile.reconcileChildren.doc                    : Doc
  + Incremental.reconcile.reconcileExisting                        : Location
                                                                     -> Key
                                                                     -> [Message]
                                                                     -> ComputeRecord
                                                                       a
                                                                       g
                                                                     -> '{g,
                                                                     Incremental
                                                                       a
                                                                       g} a
                                                                     ->{g,
                                                                     Stream
                                                                       (Delta
                                                                         a)} ComputeRecord
                                                                       a
                                                                       g
  + Incremental.reconcile.reconcileExisting.doc                    : Doc
  + Incremental.reconcile.removedCellRecords                       : [( Key,
                                                                       Any)]
                                                                     -> [( Key,
                                                                       Any)]
                                                                     -> [CellRecord
                                                                       s
                                                                       m
                                                                       g]
  + Incremental.reconcile.removedCellRecords.doc                   : Doc
  + Incremental.reconcile.rerunExisting                            : Location
                                                                     -> Key
                                                                     -> [Message]
                                                                     -> ComputeRecord
                                                                       a
                                                                       g
                                                                     -> '{g,
                                                                     Incremental
                                                                       a
                                                                       g} a
                                                                     ->{g,
                                                                     Stream
                                                                       (Delta
                                                                         a)} ComputeRecord
                                                                       a
                                                                       g
  + Incremental.reconcile.rerunExisting.doc                        : Doc
  + Incremental.reconcile.splitNodes                               : [IncrementalNode
                                                                       a
                                                                       g]
                                                                     -> ( [( Key,
                                                                       Any)],
                                                                       [( Key,
                                                                       ComputeRecord
                                                                       a
                                                                       g)])
  + Incremental.reconcile.splitNodes.doc                           : Doc
  + Key.filterMessages.doc                                         : Doc
  ~ Incremental.reconcile.handler                              : Location
                                                                 -> PreviousChildren
                                                                   a
                                                                   g
                                                                 -> [Message]
                                                                 -> KeyState
                                                                 -> [IncrementalNode
                                                                   a
                                                                   g]
                                                                 -> Request
                                                                   {g,
                                                                   Incremental
                                                                     a
                                                                     g}
                                                                   a
                                                                 ->{g,
                                                                 Stream
                                                                   (Delta
                                                                     a)} ( a,
                                                                   [IncrementalNode
                                                                   a
                                                                   g])
  ~ Incremental.reconcile.KeyState.enter                       : Key
                                                                 -> KeyState
  ~ Incremental.reconcile.KeyState.nextKey                     : Optional
                                                                   k
                                                                 -> KeyState
                                                                 -> ( Key,
                                                                   KeyState)
  ~ Incremental.reconcile.KeyState.root                        : KeyState
  ~ Incremental.reconcile.KeyState.segments                    : KeyState
                                                                 -> [Segment]
  ~ Incremental.reconcile.PreviousChildren.lookup              : Key
                                                                 -> PreviousChildren
                                                                   a
                                                                   g
                                                                 -> Optional
                                                                   (IncrementalNode
                                                                     a
                                                                     g)
  ~ Incremental.reconcile.PreviousChildren.lookupCellRecord    : Key
                                                                 -> PreviousChildren
                                                                   a
                                                                   g
                                                                 -> Optional
                                                                   (CellRecord
                                                                     s
                                                                     m
                                                                     g)
  ~ Incremental.reconcile.PreviousChildren.lookupComputeRecord : Key
                                                                 -> PreviousChildren
                                                                   a
                                                                   g
                                                                 -> Optional
                                                                   (ComputeRecord
                                                                     a
                                                                     g)
  ~ Incremental.reconcile.PreviousChildren.of                  : Optional
                                                                   (ComputeRecord
                                                                     a
                                                                     g)
                                                                 -> PreviousChildren
                                                                   a
                                                                   g
  ~ Incremental.reconcile.reconcileCell                        : Key
                                                                 -> [Message]
                                                                 -> Optional
                                                                   (CellRecord
                                                                     s
                                                                     m
                                                                     g)
                                                                 -> Cell
                                                                   s
                                                                   m
                                                                   g
                                                                 ->{g} ( s,
                                                                   IncrementalNode
                                                                   a
                                                                   g)
  ~ Incremental.reconcile.reconcileChildLocations              : Location
                                                                 -> [( Key,
                                                                   ComputeRecord
                                                                   a
                                                                   g)]
                                                                 -> [( Key,
                                                                   ComputeRecord
                                                                   a
                                                                   g)]
                                                                 ->{g,
                                                                 Stream
                                                                   (Delta
                                                                     a)} ()
  ~ Incremental.reconcile.reconcileChildLocations.doc          : Doc
  ~ Incremental.reconcile.reconcileChildren                    : Key
                                                                 -> [IncrementalNode
                                                                   a
                                                                   g]
                                                                 -> [IncrementalNode
                                                                   a
                                                                   g]
                                                                 ->{g,
                                                                 Stream
                                                                   (Delta
                                                                     a)} ()
  ~ Incremental.reconcile.reconcileCompute                     : Location
                                                                 -> Key
                                                                 -> [Message]
                                                                 -> Optional
                                                                   (ComputeRecord
                                                                     a
                                                                     g)
                                                                 -> '{g,
                                                                 Incremental
                                                                   a
                                                                   g} a
                                                                 ->{g,
                                                                 Stream
                                                                   (Delta
                                                                     a)} ComputeRecord
                                                                   a
                                                                   g
  ~ Incremental.reconcile.reconcileCompute.doc                 : Doc
  ~ Incremental.reconcile.siblingSegment                       : Key
                                                                 -> Optional
                                                                   Segment
  ~ Incremental.reconcile.stableIndices                        : [Optional
                                                                   Nat]
                                                                 -> [Boolean]
  ~ Key.filterMessages                                         : Key
                                                                 -> [Message]
                                                                 -> [Message]

  (and 2 unchanged terms)

  + (added), ~ (modified)

  Run `update` to apply these changes to your codebase.

@dfreeman/ink/perf-r4> update

  Done.

@dfreeman/ink/perf-r4> test

  ✅  























    New test results:

    1.  Incremental.reconcile.stableIndices.tests.empty          ◉ Passed
    2.  Incremental.reconcile.stableIndices.tests.newAndSorted   ◉ Passed
    3.  Incremental.reconcile.stableIndices.tests.reversed       ◉ Passed
    4.  Incremental.reconcile.stableIndices.tests.swap           ◉ Passed
    5.  tests.attachedReconcile                                  ◉ the body reading the result ran again
    6.  tests.cellLifecycle                                      ◉ Ok
                                                                 ◉ Ok
                                                                 ◉ Ok
                                                                 ◉ Ok
                                                                 ◉ Ok
                                                                 ◉ Ok
                                                                 ◉ Ok
                                                                 ◉ Ok
                                                                 ◉ Ok
    7.  tests.detachedReconcile                                  ◉ only the computation owning the cell ran again
    8.  tests.indexReconciliation                                ◉ Ok
                                                                 ◉ Ok
                                                                 ◉ Ok
                                                                 ◉ Ok
                                                                 ◉ Ok
                                                                 ◉ Ok
                                                                 ◉ Ok
    9.  tests.statePersistence                                   ◉ Ok
                                                                 ◉ Ok
                                                                 ◉ Ok
                                                                 ◉ Ok
                                                                 ◉ Ok
                                                                 ◉ Ok
                                                                 ◉ Ok
                                                                 ◉ Ok
                                                                 ◉ Ok
                                                                 ◉ Ok
    10. tests.structureUpdates                                   ◉ Ok
                                                                 ◉ Ok
                                                                 ◉ Ok
                                                                 ◉ Ok
                                                                 ◉ Ok
                                                                 ◉ Ok
                                                                 ◉ Ok
                                                                 ◉ Ok
    11. tests.subtreeRemoval                                     ◉ Ok
                                                                 ◉ Ok
                                                                 ◉ Ok
                                                                 ◉ Ok

  ✅ 44 test(s) passing

  Tip: Use view 1 to view the source of a test.

@dfreeman/proscenium/perf-mount-compute> branch perf-r4

  Done. I've created the perf-r4 branch based off of
  perf-mount-compute.

  Tip: To merge your work back into the perf-mount-compute
       branch, first `switch /perf-mount-compute` then
       `merge /perf-r4`.

@dfreeman/proscenium/perf-r4> fork @dfreeman/warp/perf-r4: lib.dfreeman_warp_r4

  Done.

@dfreeman/proscenium/perf-r4> upgrade dfreeman_warp_perf3 dfreeman_warp_r4

  I upgraded dfreeman_warp_perf3 to dfreeman_warp_r4.

@dfreeman/proscenium/perf-r4> fork @dfreeman/ink/perf-r4: lib.dfreeman_ink_r4

  Done.

@dfreeman/proscenium/perf-r4> upgrade dfreeman_ink_mount dfreeman_ink_r4

  I upgraded dfreeman_ink_mount to dfreeman_ink_r4.

@dfreeman/proscenium/perf-r4> load target/unison/frontend-bench/scratch-proscenium--perf-r4.u

  Loading changes detected in
  target/unison/frontend-bench/scratch-proscenium--perf-r4.u.

  + structural type app.Root.internal.PreparedStep g
  + type dom.internal.NodeHint
  ~ type dom.internal.HintPath

  + abilities.Render.element.doc                    : Doc
  + abilities.Render.region.doc                     : Doc
  + abilities.Render.text.doc                       : Doc
  + abilities.Render.voidElement.doc                : Doc
  + app.Root.internal.addEventListener.doc          : Doc
  + app.Root.internal.listenerToJSFunc.doc          : Doc
  + app.Root.internal.PreparedStep.doc              : Doc
  + app.Root.internal.removeEventListener.doc       : Doc
  + app.Root.internal.synchronize.doc               : Doc
  + app.Root.internal.synchronizeAttributes.doc     : Doc
  + app.Root.internal.synchronizeEventListeners.doc : Doc
  + app.Root.internal.synchronizeProperties.doc     : Doc
  + app.Root.internal.trieInsert                    : [Key.Segment]
                                                      -> val
                                                      -> Trie
                                                        Key.Segment
                                                        val
                                                      -> Trie
                                                        Key.Segment
                                                        val
  + app.Root.internal.trieInsert.doc                : Doc
  + app.Root.internal.trieLookup                    : [Key.Segment]
                                                      -> Trie
                                                        Key.Segment
                                                        val
                                                      -> Optional
                                                        val
  + app.Root.internal.trieLookup.doc                : Doc
  + app.Root.internal.triePopSubtree                : [Key.Segment]
                                                      -> Trie
                                                        Key.Segment
                                                        val
                                                      -> ( Optional
                                                        val,
                                                        Trie
                                                        Key.Segment
                                                        val)
  + app.Root.internal.triePopSubtree.doc            : Doc
  + dom.internal.emptyBody                          : '{g,
                                                      Render g} ()
  + dom.internal.emptyBody.doc                      : Doc
  + dom.internal.HintPath.appendRegion              : Any
                                                      -> HintPath
                                                      -> HintPath
  + dom.internal.HintPath.appendRegion.doc          : Doc
  + dom.internal.inheritNamespace                   : Namespace
  + dom.internal.inheritNamespace.doc               : Doc
  + dom.internal.NodeHint.doc                       : Doc
  + dom.internal.render.doc                         : Doc
  + dom.internal.someHere                           : Optional
                                                        HintPath
  + dom.internal.someHere.doc                       : Doc
  ~ abilities.Render.element                    : Text
                                                  -> [Modifier g]
                                                  -> '{g,
                                                  Render g} ()
                                                  ->{Render g} ()
  ~ abilities.Render.elementWith                : Text
                                                  -> '{g,
                                                  Render g} [Modifier
                                                    g]
                                                  ->{Render g} ()
  ~ abilities.Render.elementWith.doc            : Doc
  ~ abilities.Render.region                     : key
                                                  -> '{g,
                                                  Render g} res
                                                  ->{Render g} res
  ~ abilities.Render.text                       : Text
                                                  ->{Render g} ()
  ~ abilities.Render.voidElement                : Text
                                                  -> [Modifier g]
                                                  ->{Render g} ()
  ~ app.Root.internal.addEventListener          : EventTarget g
                                                  -> Text
                                                  -> Exists
                                                    (Listener g)
                                                  -> (Action
                                                     JS g
                                                   ->{JS} ())
                                                  ->{JS} ()
  ~ app.Root.internal.listenerToJSFunc          : Exists
                                                    (Listener g)
                                                  -> (Action
                                                     JS g
                                                   ->{JS} ())
                                                  ->{JS} JSValue
  ~ app.Root.internal.removeEventListener       : EventTarget g
                                                  -> Text
                                                  -> Exists
                                                    (Listener g)
                                                  ->{Exception,
                                                  JS} ()
  ~ app.Root.internal.synchronize               : Ref
                                                    JS
                                                    (JSState g)
                                                  -> [Delta
                                                    (Node g)]
                                                  ->{JS} ()
  ~ app.Root.internal.synchronizeAttributes     : Map
                                                    Name [Text]
                                                  -> Map
                                                    Name [Text]
                                                  -> EventTarget
                                                    g
                                                  ->{JS} ()
  ~ app.Root.internal.synchronizeEventListeners : Map
                                                    Text
                                                    [Exists
                                                      (Listener
                                                        g)]
                                                  -> EventTarget
                                                    g
                                                  -> (Action
                                                     JS g
                                                   ->{JS} ())
                                                  ->{JS} ()
  ~ app.Root.internal.synchronizeProperties     : Map Text Json
                                                  -> Map
                                                    Text Json
                                                  -> EventTarget
                                                    g
                                                  ->{JS} ()
  ~ dom.internal.HintPath.doc                   : Doc
  ~ dom.internal.render                         : [Message]
                                                  -> Optional
                                                    (IncrementalRecord
                                                      (Node g)
                                                      {g,
                                                      Effect g})
                                                  -> '{g,
                                                  Render g} ()
                                                  ->{g,
                                                  Effect g,
                                                  Stream
                                                    (Delta
                                                      (Node g))} IncrementalRecord
                                                    (Node g)
                                                    {g,
                                                    Effect g}
  ~ provider.Keyed.useKeyed                     : (∀ b.
                                                    Keyed.Accessor
                                                      k v b
                                                    ->{g} b)
                                                  -> k
                                                  ->{Render g} Optional
                                                    v
  ~ provider.Keyed.useKeyed.doc                 : Doc
  ~ provider.Selector.useSelected               : (∀ b.
                                                    Selector.Accessor
                                                      k b
                                                    ->{g} b)
                                                  -> k
                                                  ->{Render g} Boolean
  ~ provider.Selector.useSelected.doc           : Doc

  + (added), ~ (modified)

  Run `update` to apply these changes to your codebase.

@dfreeman/proscenium/perf-r4> update

  Done.

@dfreeman/proscenium/perf-r4> test

  ✅  









    New test results:

    1. tests.testRender           ◉ Passed
    2. tests.testScheduling       ◉ Passed
    3. tests.testSingleton        ◉ Passed
    4. tests.testStatefulRender   ◉ Passed

  ✅ 4 test(s) passing

  Tip: Use view 1 to view the source of a test.

@dfreeman/proscenium/perf-r4> compile bench.rowsfg.build target/unison/frontend-bench/rows-build-r4
```
