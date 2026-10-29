#!/usr/bin/env nu
# Generate @dfreeman/proscenium Round 4 DOM, render, HintPath, Trie, Modifier, and provider optimizations.

def main [] {
    let dest = $env.FILE_PWD | path join ".." ".." ".." "target" "unison" "frontend-bench" | path expand; mkdir $dest
    let out = ($dest | path join "scratch-proscenium--perf-r4.u")

    r##'{{
The value at `key`, subscribing this component to it: when `setKeyed` changes
that key, this component renders again with the new value. Deletes the `key`
entry from `subs` when the last subscriber unsubscribes so removed keys do not
retain empty list entries.
}}
provider.Keyed.useKeyed :
  (∀ b. Keyed.Accessor k v b ->{g} b)
  -> k
  ->{Render g} Optional v
provider.Keyed.useKeyed access key =
  use Keyed.Accessor Accessor
  use List +: deleteFirst
  use Map get insert
  subscribers subs = get key subs |> Optional.getOrElse []
  useCell
    (send ->
      let
        subscribe = cases
          Keyed values subs ->
            ( Keyed
                values
                (insert key (send +: subscribers subs) subs)
            , get key values
            )
        unsubscribe = cases
          Keyed values subs ->
            remaining =
              deleteFirst (Universal.eq send) (subscribers subs)
            subs' =
              if List.isEmpty remaining then Map.delete key subs
              else insert key remaining subs
            (Keyed values subs', ())
        value = access (Accessor subscribe)
        onCleanup (_ -> access (Accessor unsubscribe))
        onMessage (_ newValue -> newValue)
        value)

{{
Whether `key` is the selected one, subscribing this component to the answer.
Deletes `key` from `subs` when the last subscriber unsubscribes.
}}
provider.Selector.useSelected :
  (∀ b. Selector.Accessor k b ->{g} b)
  -> k
  ->{Render g} Boolean
provider.Selector.useSelected access key =
  use List +: deleteFirst
  use Map insert
  use Selector.Accessor Accessor
  subscribers subs = Map.get key subs |> Optional.getOrElse []
  useCell
    (send ->
      let
        subscribe = cases
          Selector current subs ->
            ( Selector
                current
                (insert key (send +: subscribers subs) subs)
            , current === Some key
            )
        unsubscribe = cases
          Selector current subs ->
            remaining =
              deleteFirst (Universal.eq send) (subscribers subs)
            subs' =
              if List.isEmpty remaining then Map.delete key subs
              else insert key remaining subs
            (Selector current subs', ())
        value = access (Accessor subscribe)
        onCleanup (_ -> access (Accessor unsubscribe))
        onMessage (_ selected -> selected)
        value)

{{
Shared no-op render body thunk used by leaf nodes ({abilities.Render.text} and
{abilities.Render.voidElement}) so {dom.internal.render} can skip installing a
nested {type Render} handler for childless nodes.
}}
dom.internal.emptyBody : '{g, Render g} ()
dom.internal.emptyBody = do ()

{{
Internal sentinel {type Namespace} used by {abilities.Render.region} to inherit
the enclosing namespace inside {dom.internal.render} without issuing a separate
`currentNamespace` ability request.
}}
dom.internal.inheritNamespace : Namespace
dom.internal.inheritNamespace = Custom "__proscenium_inherit_ns__"

{{
The region keys scoping a node or cell, stored **outermost-first** so
`Universal.compare` resolves on the outermost varying region key immediately in
pure Wasm without first comparing constant inner element tags.
}}
type dom.internal.HintPath
  = Here
  | OneRegion Any
  | NestedRegion Any HintPath

{{
Appends an inner region key to an outermost-first {type HintPath}.
}}
dom.internal.HintPath.appendRegion : Any -> HintPath -> HintPath
dom.internal.HintPath.appendRegion innerAny = cases
  Here -> OneRegion innerAny
  OneRegion outerAny -> NestedRegion outerAny (OneRegion innerAny)
  NestedRegion outerAny restPath ->
    NestedRegion outerAny (dom.internal.HintPath.appendRegion innerAny restPath)

{{
Preallocated `Some Here` hint for unscoped `useCell` hooks so cell creation
allocates no hint wrapper.
}}
dom.internal.someHere : Optional HintPath
dom.internal.someHere = Some Here

{{
Compact reconciler hint for DOM nodes. Places any enclosing region key at
field 0 so map and trie comparisons between keyed siblings resolve on the first
field in pure Wasm, and flattens common HTML element tags to a single constructor.
}}
type dom.internal.NodeHint
  = HtmlTag Text
  | CustomTag Namespace Any
  | RegionHtmlTag Any Text
  | RegionText Any
  | RegionCustom Any Namespace Any
  | NestedText Any HintPath
  | NestedCustom Any HintPath Namespace Any

{{
Emits a DOM element in the enclosing namespace with a single {type Render}
ability request, deferring namespace qualification to {dom.internal.render}.
}}
abilities.Render.element :
  Text -> [Modifier g] -> '{g, Render g} () ->{Render g} ()
abilities.Render.element localName modifiers body =
  rawName = Unqualified localName
  Render.node rawName (Element rawName modifiers) body

{{
Emits a childless HTML/SVG void element with a single {type Render} ability
request and {dom.internal.emptyBody}.
}}
abilities.Render.voidElement :
  Text -> [Modifier g] ->{Render g} ()
abilities.Render.voidElement localName modifiers =
  rawName = Unqualified localName
  Render.node rawName (Element rawName modifiers) dom.internal.emptyBody

{{
Like {abilities.Render.element}, but computes the element's modifiers inside its
own body after rendering children, using a single `nodeWith` ability request.
}}
abilities.Render.elementWith :
  Text -> '{g, Render g} [Modifier g] ->{Render g} ()
abilities.Render.elementWith localName body =
  Render.nodeWith localName do Element (Unqualified localName) body()

{{
Emits a DOM text node using {dom.internal.emptyBody} so no child handler is
installed.
}}
abilities.Render.text : Text ->{Render g} ()
abilities.Render.text contents =
  Render.node () (TextNode contents) dom.internal.emptyBody

{{
Scopes `body` under `key` while inheriting the enclosing namespace in a single
`fragment` ability request.
}}
abilities.Render.region :
  key -> '{g, Render g} res ->{Render g} res
abilities.Render.region key body =
  Render.fragment dom.internal.inheritNamespace (Some key) body

{{
Translates a {type Render} computation into incremental {type Node} computations
and reconciles it against `previous`.
}}
dom.internal.render :
  [Message]
  -> Optional (IncrementalRecord (Node g) {g, Effect g})
  -> '{g, Render g} ()
  ->{g, Effect g, Stream (Delta (Node g))} IncrementalRecord
    (Node g) {g, Effect g}
dom.internal.render messages previous rootBody =
  use HintPath Here NestedRegion OneRegion
  use NodeHint CustomTag HtmlTag NestedCustom NestedText RegionCustom RegionHtmlTag RegionText
  use dom.internal.render buildCell
  use dom.internal.render.buildCell.CellState CellState
  qualifyNode : Namespace -> Node g -> Node g
  qualifyNode ns = cases
    Element (Unqualified localName) modifiers ->
      Element (Qualified ns localName) modifiers
    otherNode -> otherNode
  customNodeHint : Namespace -> HintPath -> Any -> Optional NodeHint
  customNodeHint ns subkeys keyAny =
    match subkeys with
      Here -> Some (CustomTag ns keyAny)
      OneRegion regAny -> Some (RegionCustom regAny ns keyAny)
      NestedRegion outerAny restPath ->
        Some (NestedCustom outerAny restPath ns keyAny)
  reconcileWithDeltas messages previous do
    go :
      Namespace
      -> HintPath
      -> '{g, Render g} res
      ->{g, Incremental (Node g) {g, Effect g}} res
    go ns subkeys currentBody =
      handle currentBody()
      with cases
        { Render.fragment requestedNS maybeKey fragBody -> resume } ->
          effectiveNS =
            if requestedNS === dom.internal.inheritNamespace then ns
            else requestedNS
          subkeys' =
            match maybeKey with
              Some regionKey -> HintPath.appendRegion (Any regionKey) subkeys
              None -> subkeys
          fragResult = go effectiveNS subkeys' fragBody
          go ns subkeys do resume fragResult
        { currentNamespace -> resume } ->
          go ns subkeys do resume ns
        { Render.node rawKey rawValue childBody -> resume } ->
          (nodeHint, qualifiedValue) =
            match rawValue with
              Element (Unqualified localName) modifiers ->
                fullVal = Element (Qualified ns localName) modifiers
                hintOpt =
                  match (subkeys, ns) with
                    (Here, HTML) -> Some (HtmlTag localName)
                    (Here, _) -> Some (CustomTag ns (Any localName))
                    (OneRegion regAny, HTML) -> Some (RegionHtmlTag regAny localName)
                    (OneRegion regAny, _) -> Some (RegionCustom regAny ns (Any localName))
                    (NestedRegion outerAny restPath, _) ->
                      Some (NestedCustom outerAny restPath ns (Any localName))
                (hintOpt, fullVal)
              TextNode _ | childBody === dom.internal.emptyBody ->
                hintOpt =
                  match subkeys with
                    Here -> None
                    OneRegion regAny -> Some (RegionText regAny)
                    NestedRegion outerAny restPath ->
                      Some (NestedText outerAny restPath)
                (hintOpt, rawValue)
              otherVal ->
                (customNodeHint ns subkeys (Any rawKey), qualifyNode ns otherVal)
          nodeThunk =
            if childBody === dom.internal.emptyBody then
              do qualifiedValue
            else
              do
                go ns Here childBody
                qualifiedValue
          compute_ nodeHint nodeThunk
          go ns subkeys resume
        { Render.nodeWith rawKey childBody -> resume } ->
          hintOpt = customNodeHint ns subkeys (Any rawKey)
          compute_ hintOpt do
            qualifyNode ns (go ns Here childBody)
          go ns subkeys resume
        { useCell def -> resume } ->
          cellHint =
            match subkeys with
              Here -> dom.internal.someHere
              otherPath -> Some otherPath
          (CellState cellValue _ _) = cell cellHint (buildCell def)
          go ns subkeys do resume cellValue
        { finalResult } -> finalResult
    Function.ignore (go HTML Here rootBody)
    Root

{{
Looks up `segments` in `trie` by direct index-based descent without slicing
segment lists.
}}
app.Root.internal.trieLookup : [Key.Segment] -> Trie Key.Segment val -> Optional val
app.Root.internal.trieLookup segments rootTrie =
  len = List.size segments
  go idx curr =
    if idx Nat.>= len then Trie.head curr
    else
      match List.at idx segments with
        None -> None
        Some seg ->
          match Map.get seg (Trie.tail curr) with
            None -> None
            Some child -> go (idx Nat.+ 1) child
  go 0 rootTrie

{{
Inserts `value` at `segments` in `rootTrie` directly in a single recursive pass
without allocating a singleton trie or calling `Trie.unionWith`.
}}
app.Root.internal.trieInsert :
  [Key.Segment] -> val -> Trie Key.Segment val -> Trie Key.Segment val
app.Root.internal.trieInsert segments value rootTrie =
  len = List.size segments
  go idx curr =
    if idx Nat.>= len then
      Trie.Trie (Some value) (Trie.tail curr)
    else
      match List.at idx segments with
        None -> curr
        Some seg ->
          tailMap = Trie.tail curr
          child =
            match Map.get seg tailMap with
              Some existing -> existing
              None -> Trie.empty
          Trie.Trie (Trie.head curr) (Map.insert seg (go (idx Nat.+ 1) child) tailMap)
  go 0 rootTrie

{{
Deletes the subtree at `segments` from `rootTrie` and returns both the removed
node value (if present) and the updated trie in a single pass.
}}
app.Root.internal.triePopSubtree :
  [Key.Segment] -> Trie Key.Segment val -> (Optional val, Trie Key.Segment val)
app.Root.internal.triePopSubtree segments rootTrie =
  len = List.size segments
  if len Nat.== 0 then
    (Trie.head rootTrie, Trie.empty)
  else
    lastIdx = Nat.diff len 1
    go idx curr =
      match List.at idx segments with
        None -> (None, curr)
        Some seg ->
          tailMap = Trie.tail curr
          if idx Nat.== lastIdx then
            match Map.get seg tailMap with
              None -> (None, curr)
              Some removedTrie ->
                ( Trie.head removedTrie
                , Trie.Trie (Trie.head curr) (Map.delete seg tailMap)
                )
          else
            match Map.get seg tailMap with
              None -> (None, curr)
              Some child ->
                (found, child') = go (idx Nat.+ 1) child
                (found, Trie.Trie (Trie.head curr) (Map.insert seg child' tailMap))
    go 0 rootTrie

{{
Prepared step for two-pass DOM synchronization when `deltas` contains `Resolve`
entries.
}}
structural type app.Root.internal.PreparedStep g
  = AttachTarget (EventTarget g) Location
  | StepDelta (Delta (Node g))

{{
Wraps a {type Listener} into a 1-argument JavaScript event callback using
{JSValue.callback1_} and {JSValue.invoke0_}.
}}
app.Root.internal.listenerToJSFunc :
  Exists (Listener g)
  -> (Action JS g ->{JS} ())
  ->{JS} JSValue
app.Root.internal.listenerToJSFunc listener enqueueAction =
  buildListener : Listener g payload ->{JS} JSValue
  buildListener = cases
    Listener extractor callback ->
      JSValue.callback1_
        (event ->
          let
            JSValue.invoke0_ "preventDefault" event
            extracted = Extractor.runJS event extractor |> Either.toBug
            action : '{g, Update, Suspend g} ()
            action = do callback extracted
            enqueueAction (Execute Main action))
  Exists.apply buildListener listener

{{
Attaches a single event listener to `eventTarget` via {JSValue.invokeTextVal_}.
}}
app.Root.internal.addEventListener :
  EventTarget g
  -> Text
  -> Exists (Listener g)
  -> (Action JS g ->{JS} ())
  ->{JS} ()
app.Root.internal.addEventListener eventTarget event listener enqueueAction =
  jsFn = app.Root.internal.listenerToJSFunc listener enqueueAction
  JSValue.invokeTextVal_ "addEventListener" event jsFn (EventTarget.object eventTarget)
  insertFn = cases
    Some listeners -> Some (Map.insert listener jsFn listeners)
    None -> Some (Map.singleton listener jsFn)
  JS.ref.modify (EventTarget.listeners eventTarget) (Map.alter insertFn event)

{{
Removes a single event listener from `eventTarget` via {JSValue.invokeTextVal_}.
}}
app.Root.internal.removeEventListener :
  EventTarget g
  -> Text
  -> Exists (Listener g)
  ->{Exception, JS} ()
app.Root.internal.removeEventListener eventTarget event listener =
  use Map getOrBug
  listenersRef = EventTarget.listeners eventTarget
  listenersForEvent =
    Ref.read listenersRef |> getOrBug event "Missing listeners for event"
  jsFn =
    getOrBug listener "Missing listener function" listenersForEvent
  JS.ref.modify
    listenersRef
    (Map.insert event (Map.delete listener listenersForEvent))
  JSValue.invokeTextVal_ "removeEventListener" event jsFn (EventTarget.object eventTarget)

{{
Synchronizes element attributes between `oldAttrs` and `newAttrs` using direct
zero-allocation {JSValue.invokeText2_} / {JSValue.invokeText1_} calls.
}}
app.Root.internal.synchronizeAttributes :
  Map Name [Text]
  -> Map Name [Text]
  -> EventTarget g
  ->{JS} ()
app.Root.internal.synchronizeAttributes oldAttrs newAttrs eventTarget =
  targetObj = EventTarget.object eventTarget
  joinAttrValues = cases
    [single] -> single
    many -> Text.join " " many
  when (Boolean.not (Map.isEmpty newAttrs)) do
    Map.foreach
      newAttrs
      (attrName values ->
        let
          joined = joinAttrValues values
          match attrName with
            Qualified ns localName ->
              JSValue.invokeText3_ "setAttributeNS" (Namespace.toText ns) localName joined targetObj
            Unqualified localName ->
              JSValue.invokeText2_ "setAttribute" localName joined targetObj)
  when (Boolean.not (Map.isEmpty oldAttrs)) do
    Map.foreach
      (Map.difference oldAttrs newAttrs)
      (attrName _ ->
        match attrName with
          Qualified ns localName ->
            JSValue.invokeText2_ "removeAttributeNS" (Namespace.toText ns) localName targetObj
          Unqualified localName ->
            JSValue.invokeText1_ "removeAttribute" localName targetObj)

{{
Synchronizes DOM properties between `oldProps` and `newProps` using direct
{JSValue.setPropertyText} and {JSValue.setProperty} calls.
}}
app.Root.internal.synchronizeProperties :
  Map Text Json -> Map Text Json -> EventTarget g ->{JS} ()
app.Root.internal.synchronizeProperties oldProps newProps eventTarget =
  use List map
  targetObj = EventTarget.object eventTarget
  toJSValue = cases
    Json.Null -> JSValue.null()
    Json.Boolean bool -> JSValue.boolean bool
    Json.Number numText -> JSValue.global "Number" :$ [JSValue.string numText]
    Json.Text str -> JSValue.string str
    Json.Array values -> JSValue.array (map toJSValue values)
    Json.Object entries ->
      JSValue.object (map (Tuple.second toJSValue) entries)
  when (Boolean.not (Map.isEmpty newProps)) do
    Map.foreach
      newProps
      (propName propVal ->
        match propVal with
          Json.Text str -> JSValue.setPropertyText propName str targetObj
          otherJson -> JSValue.setProperty propName (toJSValue otherJson) targetObj)
  when (Boolean.not (Map.isEmpty oldProps)) do
    undef = JSValue.undefined()
    Map.foreach
      (Map.difference oldProps newProps)
      (propName _ -> JSValue.setProperty propName undef targetObj)

{{
Synchronizes DOM event listeners on `eventTarget` via {JSValue.invokeTextVal_}.
}}
app.Root.internal.synchronizeEventListeners :
  Map Text [Exists (Listener g)]
  -> EventTarget g
  -> (Action JS g ->{JS} ())
  ->{JS} ()
app.Root.internal.synchronizeEventListeners listeners eventTarget enqueueAction =
  use Map empty mergeWith
  targetObj = EventTarget.object eventTarget
  listenerListToMap listenerList =
    Map.fromList
      (List.map
        (listener ->
          (listener, app.Root.internal.listenerToJSFunc listener enqueueAction))
        listenerList)
  removeListener event jsFn =
    JSValue.invokeTextVal_ "removeEventListener" event jsFn targetObj
  addListener event jsFn =
    JSValue.invokeTextVal_ "addEventListener" event jsFn targetObj
  mergeListeners event = cases
    This newListener ->
      addListener event newListener
      Some newListener
    That oldListener ->
      removeListener event oldListener
      None
    Both newListener oldListener ->
      when (newListener !== oldListener) do
        removeListener event oldListener
        addListener event newListener
      Some newListener
  mergeEvent event = cases
    This newListeners ->
      Some
        (mergeWith
          (mergeListeners event)
          (listenerListToMap newListeners)
          empty)
    That oldListeners ->
      _ = mergeWith (mergeListeners event) empty oldListeners
      None
    Both newListeners oldListeners ->
      Some
        (mergeWith
          (mergeListeners event)
          (listenerListToMap newListeners)
          oldListeners)
  JS.ref.modify
    (EventTarget.listeners eventTarget)
    (Map.mergeWithKey mergeEvent listeners)

{{
Applies incremental {type Node} `deltas` to the live browser DOM.

Uses a direct zero-allocation pass when `deltas` contains no `Resolve` entries,
and a two-pass strategy when mounting new nodes: Pass 1 instantiates detached
real DOM nodes (`document.createElement` for HTML tags) into `domNodes`, and
Pass 2 attaches children directly to their real parent elements without
intermediate `DocumentFragment`s. Listener-free targets share a single immutable
empty listener `Ref`.
}}
app.Root.internal.synchronize :
  Ref JS (JSState g) -> [Delta (Node g)] ->{JS} ()
app.Root.internal.synchronize state deltas =
  use Key Segment
  use PreparedStep AttachTarget StepDelta
  use app.Root.internal listenerToJSFunc synchronizeAttributes synchronizeEventListeners synchronizeProperties trieInsert trieLookup triePopSubtree
  use app.Root.internal.JSState enqueueAction
  totalDeltas = List.size deltas
  when (totalDeltas Nat.> 0) do
    enqueue = enqueueAction state
    init = Ref.read state
    root = JSState.root init
    sharedEmptyRef = JS.ref Map.empty
    checkHasResolve idx =
      if idx Nat.>= totalDeltas then false
      else
        match List.at idx deltas with
          Some (Resolve _ _ _) -> true
          _ -> checkHasResolve (idx Nat.+ 1)
    attachAt : EventTarget g -> Location -> Trie Segment (EventTarget g) ->{JS} ()
    attachAt eventTarget location jsDOM =
      match location with
        AtRoot -> ()
        After (Key siblingSegments) ->
          match trieLookup siblingSegments jsDOM with
            Some siblingHandle ->
              JSValue.invoke1_
                "after"
                (EventTarget.object eventTarget)
                (EventTarget.object siblingHandle)
            None -> ()
        Under (Key parentSegments) ->
          match trieLookup parentSegments jsDOM with
            Some parentHandle ->
              JSValue.invoke1_
                "prepend"
                (EventTarget.object eventTarget)
                (EventTarget.object parentHandle)
            None -> ()
    runCapture : (JSValue ->{g, Update} ()) -> JSValue ->{JS} ()
    runCapture capture el =
      action : '{g, Update, Suspend g} ()
      action = do capture el
      enqueue (Execute Main action)
    setupElement : JSValue -> [Modifier g] ->{JS} EventTarget g
    setupElement jsObject = cases
      [] ->
        EventTarget jsObject sharedEmptyRef
      [Attribute (Unqualified attrName) attrVal] ->
        JSValue.invokeText2_ "setAttribute" attrName attrVal jsObject
        EventTarget jsObject sharedEmptyRef
      [Attribute (Unqualified attrName) attrVal, EventListener evName listener] ->
        JSValue.invokeText2_ "setAttribute" attrName attrVal jsObject
        jsFn = listenerToJSFunc listener enqueue
        JSValue.invokeTextVal_ "addEventListener" evName jsFn jsObject
        EventTarget jsObject (JS.ref (Map.singleton evName (Map.singleton listener jsFn)))
      [EventListener evName listener] ->
        jsFn = listenerToJSFunc listener enqueue
        JSValue.invokeTextVal_ "addEventListener" evName jsFn jsObject
        EventTarget jsObject (JS.ref (Map.singleton evName (Map.singleton listener jsFn)))
      [EventListener evName listener, Attribute (Unqualified attrName) attrVal] ->
        JSValue.invokeText2_ "setAttribute" attrName attrVal jsObject
        jsFn = listenerToJSFunc listener enqueue
        JSValue.invokeTextVal_ "addEventListener" evName jsFn jsObject
        EventTarget jsObject (JS.ref (Map.singleton evName (Map.singleton listener jsFn)))
      [Attribute (Unqualified k0) v0, Attribute (Unqualified k1) v1] | k0 Text.!= k1 ->
        JSValue.invokeText2_ "setAttribute" k0 v0 jsObject
        JSValue.invokeText2_ "setAttribute" k1 v1 jsObject
        EventTarget jsObject sharedEmptyRef
      [Attribute (Unqualified k0) v0, Attribute (Unqualified k1) v1, Attribute (Unqualified k2) v2]
        | (k0 Text.!= k1) && (k1 Text.!= k2) && (k0 Text.!= k2) ->
        JSValue.invokeText2_ "setAttribute" k0 v0 jsObject
        JSValue.invokeText2_ "setAttribute" k1 v1 jsObject
        JSValue.invokeText2_ "setAttribute" k2 v2 jsObject
        EventTarget jsObject sharedEmptyRef
      modifiers ->
        (attrs, props, listeners, captures) = Modifier.collect modifiers
        hasListeners = Boolean.not (Map.isEmpty listeners)
        listenersRef =
          if hasListeners then JS.ref Map.empty
          else sharedEmptyRef
        target = EventTarget jsObject listenersRef
        synchronizeAttributes Map.empty attrs target
        synchronizeProperties Map.empty props target
        when hasListeners do
          synchronizeEventListeners listeners target enqueue
        List.foreach (capture -> runCapture capture jsObject) captures
        target
    applyNonResolve :
      Trie Segment (EventTarget g)
      -> Delta (Node g)
      ->{JS} Trie Segment (EventTarget g)
    applyNonResolve jsDOM = cases
      Update (Key segments) (Element oldName oldModifiers) (Element newName newModifiers)
        | oldName === newName ->
        match trieLookup segments jsDOM with
          None -> jsDOM
          Some eventTarget ->
            match (oldModifiers, newModifiers) with
              ([Attribute (Unqualified oldAttr) oldVal], [Attribute (Unqualified newAttr) newVal]) ->
                targetObj = EventTarget.object eventTarget
                if oldAttr Text.== newAttr then
                  when (oldVal Text.!= newVal) do
                    JSValue.invokeText2_ "setAttribute" newAttr newVal targetObj
                else
                  JSValue.invokeText2_ "setAttribute" newAttr newVal targetObj
                  JSValue.invokeText1_ "removeAttribute" oldAttr targetObj
                jsDOM
              ([], [Attribute (Unqualified newAttr) newVal]) ->
                JSValue.invokeText2_ "setAttribute" newAttr newVal (EventTarget.object eventTarget)
                jsDOM
              ([Attribute (Unqualified oldAttr) _], []) ->
                JSValue.invokeText1_ "removeAttribute" oldAttr (EventTarget.object eventTarget)
                jsDOM
              _ ->
                (oldAttrs, oldProps, _, _) = Modifier.collect oldModifiers
                (newAttrs, newProps, newListeners, _) = Modifier.collect newModifiers
                synchronizeAttributes oldAttrs newAttrs eventTarget
                synchronizeProperties oldProps newProps eventTarget
                oldListenersMap = Ref.read (EventTarget.listeners eventTarget)
                if Map.isEmpty oldListenersMap then
                  if Map.isEmpty newListeners then jsDOM
                  else
                    freshTarget = EventTarget (EventTarget.object eventTarget) (JS.ref Map.empty)
                    synchronizeEventListeners newListeners freshTarget enqueue
                    trieInsert segments freshTarget jsDOM
                else
                  synchronizeEventListeners newListeners eventTarget enqueue
                  jsDOM
      Update (Key segments) (TextNode oldText) (TextNode newText) ->
        match trieLookup segments jsDOM with
          None -> jsDOM
          Some eventTarget ->
            when (oldText Text.!= newText) do
              JSValue.setPropertyText "textContent" newText (EventTarget.object eventTarget)
            jsDOM
      Remove (Key segments) _ ->
        (removedOpt, jsDOM') = triePopSubtree segments jsDOM
        match removedOpt with
          Some eventTarget ->
            JSValue.invoke0_ "remove" (EventTarget.object eventTarget)
          None -> ()
        jsDOM'
      Relocate (Key segments) location ->
        match trieLookup segments jsDOM with
          Some eventTarget ->
            attachAt eventTarget location jsDOM
          None -> ()
        jsDOM
      _ -> jsDOM
    domNodes' =
      if checkHasResolve 0 then
        doc = JSValue.getProperty "document" (JSValue.global "globalThis")
        prepareLoop idx jsDOM acc =
          if idx Nat.>= totalDeltas then (jsDOM, acc)
          else
            use List :+
            match List.at idx deltas with
              None -> (jsDOM, acc)
              Some (Resolve (Key segments) (Element elemName modifiers) location) ->
                jsNode =
                  match elemName with
                    Qualified HTML localName ->
                      JSValue.invokeText1 "createElement" localName doc
                    Unqualified localName ->
                      JSValue.invokeText1 "createElement" localName doc
                    Qualified ns localName ->
                      JSValue.invokeText2 "createElementNS" (Namespace.toText ns) localName doc
                target = setupElement jsNode modifiers
                prepareLoop
                  (idx Nat.+ 1)
                  (trieInsert segments target jsDOM)
                  (acc :+ AttachTarget target location)
              Some (Resolve (Key segments) (TextNode contents) location) ->
                jsNode = JSValue.invokeText1 "createTextNode" contents doc
                target = EventTarget jsNode sharedEmptyRef
                prepareLoop
                  (idx Nat.+ 1)
                  (trieInsert segments target jsDOM)
                  (acc :+ AttachTarget target location)
              Some (Resolve _ Root _) ->
                rootTarget = EventTarget root sharedEmptyRef
                prepareLoop
                  (idx Nat.+ 1)
                  (trieInsert [] rootTarget jsDOM)
                  acc
              Some otherDelta ->
                prepareLoop (idx Nat.+ 1) jsDOM (acc :+ StepDelta otherDelta)
        (jsDOMPrepared, preparedSteps) = prepareLoop 0 (JSState.domNodes init) []
        totalPrepared = List.size preparedSteps
        applyPrepared idx jsDOM =
          if idx Nat.>= totalPrepared then jsDOM
          else
            match List.at idx preparedSteps with
              None -> jsDOM
              Some (AttachTarget target location) ->
                attachAt target location jsDOM
                applyPrepared (idx Nat.+ 1) jsDOM
              Some (StepDelta otherDelta) ->
                jsDOM' = applyNonResolve jsDOM otherDelta
                applyPrepared (idx Nat.+ 1) jsDOM'
        applyPrepared 0 jsDOMPrepared
      else
        applyDirect idx jsDOM =
          if idx Nat.>= totalDeltas then jsDOM
          else
            match List.at idx deltas with
              None -> jsDOM
              Some delta ->
                jsDOM' = applyNonResolve jsDOM delta
                applyDirect (idx Nat.+ 1) jsDOM'
        applyDirect 0 (JSState.domNodes init)
    latest = Ref.read state
    Ref.write state (latest |> JSState.domNodes.set domNodes')
'## | save --force $out
    print $out
}
