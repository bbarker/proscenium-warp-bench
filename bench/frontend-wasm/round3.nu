#!/usr/bin/env nu
# Generate the measured ink optimization outside versioned sources.
def main [] {
    let dest = $env.FILE_PWD | path join ../../target/unison/frontend-bench | path expand
    mkdir $dest
    r#'Incremental.reconcile.reconcileCompute : Location -> Key -> [Message] -> Optional (ComputeRecord a g) -> '{g, Incremental a g} a ->{g, Stream (Delta a)} ComputeRecord a g
Incremental.reconcile.reconcileCompute location key allMessages previous body' =
  use Nat + ==
  messages = filterMessages key allMessages
  depth = List.size (Key.segments key)
  rerun = do
    previousChildren = PreviousChildren.of previous
    (value', children') = handle body'() with Incremental.reconcile.handler (Under key) previousChildren messages (enter key) []
    match previous with
      Some (ComputeRecord _ value children) -> when (value !== value') do Stream.emit (Update key value value')
      _ -> Stream.emit (Resolve key value' location)
    match previous with
      Some record -> reconcileChildren key (ComputeRecord.children record) children'
      None -> ()
    ComputeRecord body' value' children'
  ownCell = cases Message messageKey _ -> List.size (Key.segments messageKey) == depth + 1
  group groups message = match message with
    Message messageKey _ ->
      use List :+
      segment = List.at depth (Key.segments messageKey)
      Map.insert segment ((Map.get segment groups |> Optional.getOrElse []) :+ message) groups
  descend groups = cases
    ComputeRecord body value children ->
      deliverable = cases
        DetachedChild childKey _ -> Map.get (siblingSegment childKey) groups |> Optional.map List.size |> Optional.getOrElse 0
        _                        -> 0
      if List.foldLeft (count child -> count + deliverable child) 0 children == List.size messages then
        child = cases
          DetachedChild childKey childRecord -> match Map.get (siblingSegment childKey) groups with
            Some childMessages -> DetachedChild childKey (Incremental.reconcile.reconcileCompute (Under key) childKey childMessages (Some childRecord) (ComputeRecord.body childRecord))
            None               -> DetachedChild childKey childRecord
          other                              -> other
        Some (ComputeRecord body value (List.map child children))
      else None
  match previous with
    Some record | ComputeRecord.body record === body' ->
      if List.isEmpty messages then record
      else if List.any ownCell messages then rerun()
      else match descend (List.foldLeft group Map.empty messages) record with
        Some record' -> record'
        None         -> rerun()
    _ -> rerun()

'# | save --force ($dest | path join scratch-codex-ink--perf-mount-compute.u)
    print ($dest | path join scratch-codex-ink--perf-mount-compute.u)
}
