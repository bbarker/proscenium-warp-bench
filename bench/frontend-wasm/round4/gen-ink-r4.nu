#!/usr/bin/env nu

# Generates Round 4 optimizations for `@dfreeman/ink` into `target/unison/frontend-bench/scratch-ink--perf-r4.u`.
def main [] {
    let dest = $env.FILE_PWD | path join ".." ".." ".." "target" "unison" "frontend-bench" | path expand; mkdir $dest
    r##'{{
Tracks sibling keys within a single parent computation: untagged children use a plain counter (`O(1)`, zero `Map` operations), while tagged children count occurrences in `Map Any Nat` without `Optional` key wrappers.
}}
structural type Incremental.reconcile.KeyState
  = KeyState [Key.Segment] Nat (Map Any Nat)

{{ Creates the root `KeyState` with empty ancestry and zeroed counters. }}
Incremental.reconcile.KeyState.root : KeyState
Incremental.reconcile.KeyState.root =
  KeyState [] 0 Map.empty

{{ Extracts the ancestor segments of a `KeyState`. }}
Incremental.reconcile.KeyState.segments : KeyState -> [Key.Segment]
Incremental.reconcile.KeyState.segments = cases
  KeyState ancestors _ _ -> ancestors

{{ Creates a fresh `KeyState` for children nested immediately under `key`. }}
Incremental.reconcile.KeyState.enter : Key -> KeyState
Incremental.reconcile.KeyState.enter key =
  KeyState (Key.segments key) 0 Map.empty

{{ Allocates the next child `Key` for `hint` within the current parent computation. }}
Incremental.reconcile.KeyState.nextKey : Optional k -> KeyState -> (Key, KeyState)
Incremental.reconcile.KeyState.nextKey hint = cases
  KeyState ancestors untaggedCount taggedCounts ->
    use List :+
    use Nat +
    match hint with
      None ->
        segment = Key.Segment.Untagged untaggedCount
        (Key (ancestors :+ segment), KeyState ancestors (untaggedCount + 1) taggedCounts)
      Some rawHint ->
        anyTag = Any rawHint
        index = Map.get anyTag taggedCounts |> Optional.getOrElse 0
        segment = Key.Segment.Tagged index anyTag
        taggedCounts' = Map.insert anyTag (index + 1) taggedCounts
        (Key (ancestors :+ segment), KeyState ancestors untaggedCount taggedCounts')

{{ Filters `messages` down to those addressed at or below `key`, short-circuiting empty message lists and the root key. }}
Key.filterMessages : Key -> [Message] -> [Message]
Key.filterMessages key messages =
  if List.isEmpty messages then []
  else
    ancestors = Key.segments key
    depth = List.size ancestors
    if depth Nat.== 0 then messages
    else
      matchesPrefix msg =
        msgSegments = Key.segments (Message.key msg)
        (List.size msgSegments Nat.>= depth) && (List.take depth msgSegments === ancestors)
      List.filter matchesPrefix messages

{{
The segment that tells a child apart from its siblings: every child's key is its parent's segments plus one more, so siblings can be compared, looked up and ordered by this alone, without walking their shared ancestry.
}}
Incremental.reconcile.siblingSegment : Key -> Optional Key.Segment
Incremental.reconcile.siblingSegment = cases
  Key segments ->
    len = List.size segments
    if len Nat.== 0 then None
    else List.at (Nat.diff len 1) segments

{{ Extracts the final distinguishing `Key.Segment` of a non-root child key in `O(1)` without wrapping in `Optional`. }}
Incremental.reconcile.childSegment : Key -> Key.Segment
Incremental.reconcile.childSegment = cases
  Key segments ->
    len = List.size segments
    if len Nat.== 0 then Key.Segment.Untagged 0
    else
      match List.at (Nat.diff len 1) segments with
        Some seg -> seg
        None     -> Key.Segment.Untagged 0

{{ Indexes a computation's previous children by their distinguishing `Key.Segment`, avoiding `Map` allocation when empty. }}
structural type Incremental.reconcile.PreviousChildren a g
  = EmptyPrevious
  | PreviousMap (Map Key.Segment (IncrementalNode a g))

{{ Builds a `PreviousChildren` index from an optional `ComputeRecord`. }}
Incremental.reconcile.PreviousChildren.of : Optional (ComputeRecord a g) -> PreviousChildren a g
Incremental.reconcile.PreviousChildren.of = cases
  None -> EmptyPrevious
  Some record ->
    children = ComputeRecord.children record
    if List.isEmpty children then EmptyPrevious
    else
      insertChild acc node = Map.insert (childSegment (IncrementalNode.key node)) node acc
      PreviousMap (List.foldLeft insertChild Map.empty children)

{{ Looks up a previous child node by its sibling `Key.Segment`. }}
Incremental.reconcile.PreviousChildren.lookup : Key -> PreviousChildren a g -> Optional (IncrementalNode a g)
Incremental.reconcile.PreviousChildren.lookup key = cases
  EmptyPrevious   -> None
  PreviousMap map -> Map.get (childSegment key) map

{{ Looks up a previous child `ComputeRecord` by its sibling `Key.Segment`. }}
Incremental.reconcile.PreviousChildren.lookupComputeRecord : Key -> PreviousChildren a g -> Optional (ComputeRecord a g)
Incremental.reconcile.PreviousChildren.lookupComputeRecord key records =
  match PreviousChildren.lookup key records with
    Some (ComputeChild _ record)  -> Some record
    Some (DetachedChild _ record) -> Some record
    _                             -> None

{{ Looks up a previous child `CellRecord` by its sibling `Key.Segment`. }}
Incremental.reconcile.PreviousChildren.lookupCellRecord : Key -> PreviousChildren a g -> Optional (CellRecord s m g)
Incremental.reconcile.PreviousChildren.lookupCellRecord key records =
  match PreviousChildren.lookup key records with
    Some (CellChild _ anyRecord) -> Some (unsafeExtract anyRecord)
    _                            -> None

{{
For each entry, whether it belongs to a longest strictly increasing run of the present positions (patience sorting, `O(n log n)`). Entries that are {None} are never in the run.

Children whose old positions form such a run are already in the right order relative to each other, so they can stay where they are while every other child moves around them: that is the fewest moves that reorder the list.
}}
Incremental.reconcile.stableIndices : [Optional Nat] -> [Boolean]
Incremental.reconcile.stableIndices positions =
  use List size +: :+
  use Nat + < ==
  totalPositions = size positions
  if totalPositions == 0 then []
  else
    present = positions |> List.indexed |> List.filterMap cases
      (Some position, index) -> Some (index, position)
      (None, _) -> None
    presentSize = size present
    if presentSize == 0 then List.fill totalPositions false
    else
      valueAt index = List.at index present |> Optional.map at2 |> Optional.getOrElse 0
      search tails value low high =
        if low < high then
          middle = (low + high) / 2
          if valueAt (List.at middle tails |> Optional.getOrElse 0) < value then search tails value (middle + 1) high
          else search tails value low middle
        else low
      build index tails predecessors =
        if index == presentSize then (tails, predecessors)
        else
          value = valueAt index
          tailsSize = size tails
          slot = search tails value 0 tailsSize
          predecessor = if slot == 0 then None else List.at (Nat.diff slot 1) tails
          tails' = if slot == tailsSize then tails :+ index else List.replace slot index tails
          build (index + 1) tails' (predecessors :+ predecessor)
      (tails, predecessors) = build 0 [] []
      lastTail = List.at (Nat.diff (size tails) 1) tails
      members acc = cases
        None -> acc
        Some index -> members (index +: acc) (List.at index predecessors |> Optional.flatten)
      stableEntries = members [] lastTail |> List.filterMap (index -> List.at index present |> Optional.map at1)
      mark index remaining acc =
        if index == totalPositions then acc
        else match remaining with
          next +: rest | next == index -> mark (index + 1) rest (acc :+ true)
          _ -> mark (index + 1) remaining (acc :+ false)
      mark 0 stableEntries []

{{
Emits the {Remove}s and {Relocate}s that turn the previous order of a computation's children into the new one.

Common prefixes and suffixes stay put; empty lists, clears, appends, single removals, and opposite-end swaps take linear `O(n)` fast paths without building maps; general reorderings keep a longest increasing run ({stableIndices}) in `O(n log n)` so only out-of-order children move.
}}
Incremental.reconcile.reconcileChildLocations : Location -> [(Key, ComputeRecord a g)] -> [(Key, ComputeRecord a g)] ->{g, Stream (Delta a)} ()
Incremental.reconcile.reconcileChildLocations location computes computes' =
  use List +: :+
  use Stream emit
  skipPrefix loc olds news = match (olds, news) with
    ((oldKey, _) +: olds', (newKey, _) +: news') | childSegment oldKey === childSegment newKey ->
      skipPrefix (After newKey) olds' news'
    _ -> (loc, olds, news)
  skipSuffix olds news = match (olds, news) with
    (oldsInit :+ (oldKey, _), newsInit :+ (newKey, _)) | childSegment oldKey === childSegment newKey ->
      skipSuffix oldsInit newsInit
    _ -> (olds, news)
  sameSegments olds news =
    total = List.size olds
    if total Nat.!= List.size news then false
    else
      checkAt idx =
        if idx Nat.== total then true
        else
          match (List.at idx olds, List.at idx news) with
            (Some (oldKey, _), Some (newKey, _)) | childSegment oldKey === childSegment newKey ->
              checkAt (idx Nat.+ 1)
            _ -> false
      checkAt 0
  removeOld = cases
    (oldKey, oldComp) ->
      emit (Remove oldKey (ComputeRecord.result oldComp))
      cleanupCompute oldKey oldComp
  (location', oldsAfterPrefix, newsAfterPrefix) = skipPrefix location computes computes'
  if List.isEmpty oldsAfterPrefix then ()
  else if List.isEmpty newsAfterPrefix then
    List.foreach removeOld oldsAfterPrefix
  else
    (olds, news) = skipSuffix oldsAfterPrefix newsAfterPrefix
    if List.isEmpty olds then ()
    else if List.isEmpty news then
      List.foreach removeOld olds
    else
      handledSwap = match (olds, news) with
        ((oldFirstKey, _) +: oldsRest, (newFirstKey, _) +: newsRest) ->
          match (oldsRest, newsRest) with
            (oldsMid :+ (oldLastKey, _), newsMid :+ (newLastKey, _))
              | (childSegment oldFirstKey === childSegment newLastKey)
                  && (childSegment oldLastKey === childSegment newFirstKey)
                  && sameSegments oldsMid newsMid ->
                emit (Relocate newFirstKey location')
                match newsMid with
                  _ :+ (midLastKey, _) -> emit (Relocate newLastKey (After midLastKey))
                  [] -> ()
                true
            _ -> false
        _ -> false
      when (Boolean.not handledSwap) do
        insertNewSeg acc entry = Map.insert (childSegment (at1 entry)) () acc
        newSegments = List.foldLeft insertNewSeg Map.empty news
        keep entry = match entry with
          (oldKey, oldComp) ->
            if Map.contains (childSegment oldKey) newSegments then true
            else
              emit (Remove oldKey (ComputeRecord.result oldComp))
              cleanupCompute oldKey oldComp
              false
        kept = List.filter keep olds
        when (Boolean.not (List.isEmpty kept)) do
          buildOldPos idx acc = cases
            [] -> acc
            entry +: rest -> buildOldPos (idx Nat.+ 1) (Map.insert (childSegment (at1 entry)) idx acc) rest
          oldPositions = buildOldPos 0 Map.empty kept
          positions = List.map (entry -> Map.get (childSegment (at1 entry)) oldPositions) news
          stables = stableIndices positions
          totalNews = List.size news
          relocateLoop loc previousMoved idx =
            if idx Nat.== totalNews then ()
            else
              match (List.at idx news, List.at idx positions, List.at idx stables) with
                (Some (newKey, _), Some posOpt, Some isStable) ->
                  moves = match posOpt with
                    Some _ -> Boolean.not isStable
                    None   -> previousMoved
                  when moves do emit (Relocate newKey loc)
                  relocateLoop (After newKey) moves (idx Nat.+ 1)
                _ -> ()
          relocateLoop location' false 0

{{ Partitions incremental child nodes into cell entries and child computation entries in a single pass. }}
Incremental.reconcile.splitNodes : [IncrementalNode a g] -> ([(Key, Any)], [(Key, ComputeRecord a g)])
Incremental.reconcile.splitNodes nodes =
  step acc = cases
    CellChild childKey rec ->
      use List :+
      (at1 acc :+ (childKey, rec), at2 acc)
    ComputeChild childKey rec ->
      use List :+
      (at1 acc, at2 acc :+ (childKey, rec))
    DetachedChild childKey rec ->
      use List :+
      (at1 acc, at2 acc :+ (childKey, rec))
  List.foldLeft step ([], []) nodes

{{ Computes the list of `CellRecord`s removed between `cells` and `cells'`, returning `[]` immediately when `cells` is empty. }}
Incremental.reconcile.removedCellRecords : [(Key, Any)] -> [(Key, Any)] -> [CellRecord s m g]
Incremental.reconcile.removedCellRecords cells cells' =
  if List.isEmpty cells then []
  else if List.isEmpty cells' then
    List.map (entry -> unsafeExtract (at2 entry)) cells
  else
    keptSegs = List.foldLeft (acc entry -> Map.insert (childSegment (at1 entry)) () acc) Map.empty cells'
    keepRemoved acc = cases
      (cellKey, anyRec) ->
        use List :+
        if Map.contains (childSegment cellKey) keptSegs then acc
        else acc :+ unsafeExtract anyRec
    List.foldLeft keepRemoved [] cells

{{ Cleans up removed cells and reconciles child computation positions. }}
Incremental.reconcile.reconcileChildren : Key -> [IncrementalNode a g] -> [IncrementalNode a g] ->{g, Stream (Delta a)} ()
Incremental.reconcile.reconcileChildren key children children' =
  (cells, computes) = Incremental.reconcile.splitNodes children
  (cells', computes') = Incremental.reconcile.splitNodes children'
  removedCells = Incremental.reconcile.removedCellRecords cells cells'
  List.foreach cleanupCell removedCells
  reconcileChildLocations (Under key) computes computes'

{{ Reconciles a stateful `Cell` against optional previous state and already-filtered parent messages. }}
Incremental.reconcile.reconcileCell : Key -> [Message] -> Optional (CellRecord s m g) -> Cell s m g ->{g} (s, IncrementalNode a g)
Incremental.reconcile.reconcileCell key' messages previous cell' =
  value' = match previous with
    None ->
      makeMessage msg = Message key' (Any msg)
      initFn cell' makeMessage
    Some (CellRecord prevCell prevValue) ->
      if prevCell === cell' then
        if List.isEmpty messages then prevValue
        else
          targetSeg = childSegment key'
          applyMsg acc = cases
            Message msgKey rawMsg | (childSegment msgKey === targetSeg) && (msgKey === key') ->
              messageFn cell' acc (unsafeExtract rawMsg)
            _ -> acc
          List.foldLeft applyMsg prevValue messages
      else
        cleanupFn prevCell prevValue
        makeMessage msg = Message key' (Any msg)
        initFn cell' makeMessage
  (value', forCell key' (CellRecord cell' value'))

{{ Mounts a brand-new computation subtree (`previous == None`) directly without message filtering, previous-child lookups, or diffing. }}
Incremental.reconcile.mountCompute : Location -> Key -> '{g, Incremental a g} a ->{g, Stream (Delta a)} ComputeRecord a g
Incremental.reconcile.mountCompute location key body' =
  (value', children') = handle body'() with Incremental.reconcile.mountHandler (Under key) (enter key) []
  Stream.emit (Resolve key value' location)
  ComputeRecord body' value' children'

{{ Ability handler for `mountCompute` when mounting a computation with no prior state. }}
Incremental.reconcile.mountHandler : Location -> KeyState -> [IncrementalNode a g] -> Request {g, Incremental a g} a ->{g, Stream (Delta a)} (a, [IncrementalNode a g])
Incremental.reconcile.mountHandler location keyState siblings = cases
  { compute keyHint body' -> resume } ->
    use List :+
    (key', keyState') = nextKey keyHint keyState
    record' = Incremental.reconcile.mountCompute location key' body'
    handle resume (ComputeRecord.result record') with Incremental.reconcile.mountHandler (After key') keyState' (siblings :+ ComputeChild key' record')
  { compute_ keyHint body' -> resume } ->
    use List :+
    (key', keyState') = nextKey keyHint keyState
    record' = Incremental.reconcile.mountCompute location key' body'
    handle resume () with Incremental.reconcile.mountHandler (After key') keyState' (siblings :+ DetachedChild key' record')
  { cell keyHint cell' -> resume } ->
    use List :+
    (key', keyState') = nextKey keyHint keyState
    makeMessage msg = Message key' (Any msg)
    value' = initFn cell' makeMessage
    child' = forCell key' (CellRecord cell' value')
    handle resume value' with Incremental.reconcile.mountHandler location keyState' (siblings :+ child')
  { value } -> (value, siblings)

{{ Ability handler for `rerunExisting` when reconciling a computation against `previousChildren`. }}
Incremental.reconcile.handler : Location -> PreviousChildren a g -> [Message] -> KeyState -> [IncrementalNode a g] -> Request {g, Incremental a g} a ->{g, Stream (Delta a)} (a, [IncrementalNode a g])
Incremental.reconcile.handler location previousChildren messages keyState siblings = cases
  { compute keyHint body' -> resume } ->
    use List :+
    (key', keyState') = nextKey keyHint keyState
    previous = previousChildren |> lookupComputeRecord key'
    record' = Incremental.reconcile.reconcileCompute location key' messages previous body'
    child' = forCompute key' record'
    handle resume (ComputeRecord.result record') with Incremental.reconcile.handler (After key') previousChildren messages keyState' (siblings :+ child')
  { compute_ keyHint body' -> resume } ->
    use List :+
    (key', keyState') = nextKey keyHint keyState
    previous = previousChildren |> lookupComputeRecord key'
    record' = Incremental.reconcile.reconcileCompute location key' messages previous body'
    handle resume () with Incremental.reconcile.handler (After key') previousChildren messages keyState' (siblings :+ DetachedChild key' record')
  { cell keyHint cell' -> resume } ->
    use List :+
    (key', keyState') = nextKey keyHint keyState
    previous = previousChildren |> lookupCellRecord key'
    (result', child') = reconcileCell key' messages previous cell'
    handle resume result' with Incremental.reconcile.handler location previousChildren messages keyState' (siblings :+ child')
  { value } -> (value, siblings)

{{ Re-evaluates an existing computation against `record` and reconciles its updated children. }}
Incremental.reconcile.rerunExisting : Location -> Key -> [Message] -> ComputeRecord a g -> '{g, Incremental a g} a ->{g, Stream (Delta a)} ComputeRecord a g
Incremental.reconcile.rerunExisting _ key messages record body' =
  previousChildren = PreviousChildren.of (Some record)
  (value', children') = handle body'() with Incremental.reconcile.handler (Under key) previousChildren messages (enter key) []
  prevValue = ComputeRecord.result record
  when (prevValue !== value') do Stream.emit (Update key prevValue value')
  reconcileChildren key (ComputeRecord.children record) children'
  ComputeRecord body' value' children'

{{
Delivers `messages` directly into `DetachedChild` subcomputations of `record` when every message belongs to a detached child, stopping its scan as soon as all messages are matched and splicing updated children in `O(k log N)`.
}}
Incremental.reconcile.descend : Key -> Nat -> [Message] -> ComputeRecord a g ->{g, Stream (Delta a)} Optional (ComputeRecord a g)
Incremental.reconcile.descend key depth messages = cases
  ComputeRecord body value children ->
    use List ++ +: :+
    use Nat + == >=
    groupMsg groups = cases
      msg@(Message messageKey _) ->
        match List.at depth (Key.segments messageKey) with
          Some seg ->
            existing = Map.get seg groups |> Optional.getOrElse []
            Map.insert seg (existing :+ msg) groups
          None -> groups
    groups = List.foldLeft groupMsg Map.empty messages
    totalMessages = List.size messages
    totalChildren = List.size children
    collect idx matchedCount acc =
      if matchedCount == totalMessages then Some acc
      else if idx >= totalChildren then None
      else
        match List.at idx children with
          Some (DetachedChild childKey childRecord) ->
            match Map.get (childSegment childKey) groups with
              Some childMsgs ->
                collect (idx + 1) (matchedCount + List.size childMsgs) (acc :+ (idx, childKey, childRecord, childMsgs))
              None ->
                collect (idx + 1) matchedCount acc
          _ ->
            collect (idx + 1) matchedCount acc
    match collect 0 0 [] with
      None -> None
      Some hits ->
        splice startIdx prefix = cases
          [] ->
            prefix ++ List.drop startIdx children
          (idx, childKey, childRecord, childMsgs) +: rest ->
            updatedRecord = Incremental.reconcile.reconcileExisting (Under key) childKey childMsgs childRecord (ComputeRecord.body childRecord)
            unchangedSlice = List.take (Nat.diff idx startIdx) (List.drop startIdx children)
            splice (idx + 1) ((prefix ++ unchangedSlice) :+ DetachedChild childKey updatedRecord) rest
        Some (ComputeRecord body value (splice 0 [] hits))

{{ Reconciles an existing `ComputeRecord` when `messages` have already been filtered to `key`'s subtree. }}
Incremental.reconcile.reconcileExisting : Location -> Key -> [Message] -> ComputeRecord a g -> '{g, Incremental a g} a ->{g, Stream (Delta a)} ComputeRecord a g
Incremental.reconcile.reconcileExisting location key messages record body' =
  if ComputeRecord.body record === body' then
    if List.isEmpty messages then record
    else
      depth = List.size (Key.segments key)
      ownCellDepth = depth Nat.+ 1
      isOwnCell = cases Message messageKey _ -> List.size (Key.segments messageKey) Nat.== ownCellDepth
      if List.any isOwnCell messages then
        Incremental.reconcile.rerunExisting location key messages record body'
      else
        match Incremental.reconcile.descend key depth messages record with
          Some record' -> record'
          None         -> Incremental.reconcile.rerunExisting location key messages record body'
  else
    Incremental.reconcile.rerunExisting location key messages record body'

{{
Runs one computation again, or doesn't.

Mounting (`previous == None`) uses `mountCompute` directly without closure or map overhead. With an unchanged body and no messages, the previous record stands immediately. With messages, the body runs again unless every message belongs to a child made with {compute_}, in which case only the matched children are reconciled and spliced in `O(k log N)`.
}}
Incremental.reconcile.reconcileCompute : Location -> Key -> [Message] -> Optional (ComputeRecord a g) -> '{g, Incremental a g} a ->{g, Stream (Delta a)} ComputeRecord a g
Incremental.reconcile.reconcileCompute location key allMessages previous body' =
  match previous with
    None -> Incremental.reconcile.mountCompute location key body'
    Some record ->
      messages =
        if List.isEmpty allMessages then []
        else filterMessages key allMessages
      Incremental.reconcile.reconcileExisting location key messages record body'

{{ Verifies fast paths in `reconcileChildLocations` (append, single remove, opposite-end swap, adjacent swap, clear) and multi-child `descend` splicing. }}
tests.reconcileFastPaths : [Result]
tests.reconcileFastPaths =
  renderIds : [Nat] -> '{Incremental Nat {}} Nat
  renderIds ids = do
    List.foreach (itemId -> compute_ (Some itemId) do itemId) ids
    List.size ids
  runStep prev ids =
    Stream.toListWithResult do
      Incremental.reconcileWithDeltas [] prev (renderIds ids)
  (mountDeltas, rec0) = runStep None [10, 20, 30, 40, 50]
  (appendDeltas, rec1) = runStep (Some rec0) [10, 20, 30, 40, 50, 60, 70]
  (removeDeltas, rec2) = runStep (Some rec1) [10, 20, 40, 50, 60, 70]
  (swapDeltas, rec3) = runStep (Some rec2) [10, 60, 40, 50, 20, 70]
  (clearDeltas, _) = runStep (Some rec3) []
  (_, adj0) = runStep None [1, 2]
  (adjSwapDeltas, _) = runStep (Some adj0) [2, 1]
  multiOuter : '{Log, Incremental Nat {Log}} Nat
  multiOuter = do
    List.foreach
      (idx ->
        compute_ None do
          Log.log (Nat.toText idx)
          at1 (cell None tests.detachedReconcile.counter))
      (Nat.range 0 6)
    0
  bump1 = Message (Key [Key.Segment.Untagged 1, Key.Segment.Untagged 0]) (Any Nat.increment)
  bump4 = Message (Key [Key.Segment.Untagged 4, Key.Segment.Untagged 0]) (Any Nat.increment)
  descendTrace = Log.toList do
    initRec = Incremental.run multiOuter
    nextRec = reconcile [bump1, bump4] (Some initRec) multiOuter
    v1 = IncrementalRecord.lookup (Key [Key.Segment.Untagged 1]) nextRec |> Optional.getOrElse 99
    v3 = IncrementalRecord.lookup (Key [Key.Segment.Untagged 3]) nextRec |> Optional.getOrElse 99
    v4 = IncrementalRecord.lookup (Key [Key.Segment.Untagged 4]) nextRec |> Optional.getOrElse 99
    Log.log (Nat.toText v1 Text.++ ":" Text.++ Nat.toText v3 Text.++ ":" Text.++ Nat.toText v4)
  isRelocate = cases
    Relocate _ _ -> true
    _            -> false
  isRemove = cases
    Remove _ _ -> true
    _          -> false
  check
    ( (List.size mountDeltas Nat.== 6)
        && (List.size (List.filter isRelocate appendDeltas) Nat.== 0)
        && (List.size (List.filter isRemove removeDeltas) Nat.== 1)
        && (List.size (List.filter isRelocate removeDeltas) Nat.== 0)
        && (List.size (List.filter isRelocate swapDeltas) Nat.== 2)
        && (List.size (List.filter isRemove clearDeltas) Nat.== 6)
        && (List.size (List.filter isRelocate adjSwapDeltas) Nat.== 1)
        && (descendTrace === ["0", "1", "2", "3", "4", "5", "1", "4", "1:0:1"])
    )
'## | save --force ($dest | path join scratch-ink--perf-r4.u)
    print ($dest | path join scratch-ink--perf-r4.u)
}
