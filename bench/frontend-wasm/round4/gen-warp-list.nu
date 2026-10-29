#!/usr/bin/env nu

def main [] {
    let dest = $env.FILE_PWD | path join ".." ".." ".." "target" "unison" "frontend-bench" | path expand; mkdir $dest
    r##'internal.runtime.Runtime.defineTypes : Boolean ->{TypeCtx, ModuleCtx} Runtime.Types
internal.runtime.Runtime.defineTypes emitJSAPI =
  use agg.ref null
  use func *
  use struct sub.named
  makeValueType = defineTypes.makeValueType emitJSAPI
  idRef = abs.ref extern
  idsType = array.named "IDArray" (agg.const idRef)
  idsRef = agg.ref idsType
  valueType = sub.named "Value" [subtypeable] [const.named "tag" i32]
  valuesType = array.named "Values" (agg.var (agg.ref valueType))
  valuesRef = agg.ref valuesType
  cellType = struct.named "Cell" [var.named "contents" (null valueType)]
  booleanType =
    makeValueType
      VBoolean
      "Boolean"
      [subtypeOf valueType]
      [const.named "tag" i32, const.named "value" i32]
  natType =
    makeValueType
      VNat
      "Nat"
      [subtypeOf valueType]
      [const.named "tag" i32, const.named "value" i64]
  intType =
    makeValueType
      VInt
      "Int"
      [subtypeOf valueType]
      [const.named "tag" i32, const.named "value" i64]
  floatType =
    makeValueType
      VFloat
      "Float"
      [subtypeOf valueType]
      [const.named "tag" i32, const.named "value" f64]
  textType =
    makeValueType
      VText
      "Text"
      [subtypeOf valueType]
      [const.named "tag" i32, const.named "value" (abs.ref extern)]
  charType =
    makeValueType
      VChar
      "Char"
      [subtypeOf valueType]
      [const.named "tag" i32, const.named "value" (abs.ref extern)]
  typeLinkType =
    makeValueType
      VTypeLink
      "TypeLink"
      [subtypeOf valueType]
      [const.named "tag" i32, const.named "id" idRef]
  termLinkType =
    makeValueType
      VTermLink
      "TermLink"
      [subtypeOf valueType]
      [ const.named "tag" i32
      , const.named "id" idRef
      , const.named "constructor" i32
      ]
  foreignType =
    makeValueType
      VForeign
      "Foreign"
      [subtypeOf valueType]
      [const.named "tag" i32, const.named "value" (abs.ref abs.any)]
  (listType, makeListAPI) =
    struct.rec.named "List" cases
      listTy ->
        listFields =
          [ const.named "tag" i32
          , const.named "size" i32
          , const.named "depth" i32
          , const.named "offset" i32
          , const.named "values" valuesRef
          , const.named "left" (null listTy)
          , const.named "right" (null listTy)
          ]
        emitListAPI =
          do
            when emitJSAPI do
              defineTypes.emitJSAPIForType
                VList "List" listFields listTy
        ([subtypeOf valueType], listFields, (listTy, emitListAPI))
  makeListAPI()
  dataType =
    makeValueType
      VData
      "Data"
      [subtypeOf valueType]
      [ const.named "tag" i32
      , const.named "type" idRef
      , const.named "constructor" i32
      , const.named "args" valuesRef
      ]
  arrayType =
    makeValueType
      VArray
      "Array"
      [subtypeOf valueType]
      [ const.named "tag" i32
      , var.named "mutable" i32
      , const.named "contents" valuesRef
      ]
  byteArrayType =
    makeValueType
      VByteArray
      "ByteArray"
      [subtypeOf valueType]
      [ const.named "tag" i32
      , var.named "mutable" i32
      , const.named "contents" (abs.ref extern)
      ]
  bytesType =
    makeValueType
      VBytes
      "Bytes"
      [subtypeOf valueType]
      [const.named "tag" i32, const.named "value" (abs.ref extern)]
  dataRef = agg.ref dataType
  (contSig, contType, makeContAPI, frameType) =
    struct.rec.named "Frame" cases
      frameTy ->
        use agg ref
        contSignature =
          param.named "frame" (ref frameTy)
            * param.named "passthrough" valuesRef
            * param.named "value" (ref valueType)
            => func.void
        contFields =
          [ const.named "tag" i32
          , const.named "impl" (ref (ty.func contSignature))
          , const.named "data" valuesRef
          ]
        contTy =
          sub.named "Continuation" [subtypeOf valueType] contFields
        emitContAPI =
          do
            when emitJSAPI do
              defineTypes.emitJSAPIForType
                VCont "Continuation" contFields contTy
        frameFields =
          [ const.named "parent" (null frameTy)
          , const.named "abilities" idsRef
          , const.named "continue" (ref contTy)
          ]
        ([], frameFields, (contSignature, contTy, emitContAPI, frameTy))
  use abs func
  use const named
  makeContAPI()
  contRef = agg.ref contType
  reqType =
    makeValueType
      VReq
      "Request"
      [subtypeOf valueType]
      [named "tag" i32, named "data" dataRef, named "continue" contRef]
  funcType =
    makeValueType
      VFunc
      "Function"
      [subtypeable, subtypeOf valueType]
      [ named "tag" i32
      , named "id" idRef
      , named "arity" i32
      , named "impl" (abs.ref func)
      ]
  closureType =
    makeValueType
      VClosure
      "Closure"
      [subtypeOf funcType]
      [ named "tag" i32
      , named "id" idRef
      , named "arity" i32
      , named "impl" (abs.ref func)
      , named "bound" valuesRef
      ]
  quoteType =
    makeValueType
      VQuote
      "Quote"
      [subtypeOf valueType]
      [named "tag" i32, named "value" (agg.ref dataType)]
  codeType =
    makeValueType
      VCode
      "Code"
      [subtypeOf valueType]
      [named "tag" i32, named "value" (abs.ref extern)]
  getInternalType = cases
    InternalType.Id    -> idsType
    Ids                -> idsType
    Values             -> valuesType
    Frame              -> frameType
    InternalType.Value -> valueType
    RefCell            -> cellType
  getValueType = cases
    VNat       -> natType
    VInt       -> intType
    VFloat     -> floatType
    VTypeLink  -> typeLinkType
    VTermLink  -> termLinkType
    VChar      -> charType
    VText      -> textType
    VData      -> dataType
    VReq       -> reqType
    VFunc      -> funcType
    VClosure   -> closureType
    VCont      -> contType
    VForeign   -> foreignType
    VBoolean   -> booleanType
    VArray     -> arrayType
    VByteArray -> byteArrayType
    VList      -> listType
    VBytes     -> bytesType
    VQuote     -> quoteType
    VCode      -> codeType
  Runtime.Types.Types getInternalType getValueType contSig

{{
Emits the shared empty `Values` array global and empty `VList` global for Wasm GC sequences.
}}
internal.runtime.ListOps.emitEmpty : TypeIdx -> TypeIdx ->{TypeCtx, ModuleCtx} (GlobalReference, GlobalReference)
internal.runtime.ListOps.emitEmpty listType valuesType =
  listRef = agg.ref listType
  valuesRef = agg.ref valuesType
  emptyValuesGlobal =
    def.global.named "emptyValues" (global.const valuesRef) do
      newFixed valuesType 0
  emptyListGlobal =
    def.global.named "emptyList" (global.const listRef) do
      pushTag VList
      i32.const 0
      i32.const 0
      i32.const 0
      global.get emptyValuesGlobal
      instr.ref.null listType
      instr.ref.null listType
      struct.new listType
  (emptyValuesGlobal, emptyListGlobal)

{{
Emits O(log n) indexed lookup on a Wasm GC `VList` tree (O(1) array load on `depth == 0` leaves).
}}
internal.runtime.ListOps.emitSeqAt : TypeIdx -> TypeIdx -> TypeIdx ->{TypeCtx, ModuleCtx} FuncReference
internal.runtime.ListOps.emitSeqAt listType valuesType anyValueType =
  use func *
  use local get named set tee
  listRef = agg.ref listType
  anyValueRef = agg.ref anyValueType
  def.func.named
    "seqAt"
    (param.named "seq" listRef * param.named "idx" i32 => result anyValueRef)
    cases
      (seq, idx) ->
        subL = named "subL" listRef
        leftSize = named "leftSize" i32
        instr.loop cases
          continue ->
            get seq
            struct.get listType 2
            i32.eqz()
            ifThen do
              get seq
              struct.get listType 4
              get seq
              struct.get listType 3
              get idx
              i32.add()
              array.get valuesType
              return()
            get seq
            struct.get listType 5
            asNonNull()
            tee subL
            struct.get listType 1
            tee leftSize
            get idx
            i32.gtU()
            ifThen do
              get subL
              set seq
              br continue
            get idx
            get leftSize
            i32.sub()
            set idx
            get seq
            struct.get listType 6
            asNonNull()
            set seq
            br continue
        unreachable()

{{
Emits `mkBranch` and AVL `balance` helpers for Wasm GC `VList` trees.
}}
internal.runtime.ListOps.emitBalance : TypeIdx -> GlobalReference ->{TypeCtx, ModuleCtx} (FuncReference, FuncReference)
internal.runtime.ListOps.emitBalance listType emptyValuesGlobal =
  use func *
  use local get named set tee
  listRef = agg.ref listType
  mkBranch =
    def.func.named
      "seqMkBranch"
      (param.named "lhs" listRef * param.named "rhs" listRef => result listRef)
      cases
        (lhs, rhs) ->
          lhsDepth = named "lhsDepth" i32
          rhsDepth = named "rhsDepth" i32
          maxDepth = named "maxDepth" i32
          get lhs
          struct.get listType 2
          tee lhsDepth
          set maxDepth
          get rhs
          struct.get listType 2
          tee rhsDepth
          get lhsDepth
          i32.gtU()
          ifThen do
            get rhsDepth
            set maxDepth
          pushTag VList
          get lhs
          struct.get listType 1
          get rhs
          struct.get listType 1
          i32.add()
          get maxDepth
          i32.const 1
          i32.add()
          i32.const 0
          global.get emptyValuesGlobal
          get lhs
          get rhs
          struct.new listType
  balance =
    def.func.named
      "seqBalance"
      (param.named "lhs" listRef * param.named "rhs" listRef => result listRef)
      cases
        (lhs, rhs) ->
          lhsDepth = named "lhsDepth" i32
          rhsDepth = named "rhsDepth" i32
          subL = named "subL" listRef
          subR = named "subR" listRef
          get lhs
          struct.get listType 2
          set lhsDepth
          get rhs
          struct.get listType 2
          set rhsDepth
          get lhsDepth
          get rhsDepth
          i32.const 1
          i32.add()
          i32.gtU()
          ifThen do
            get lhs
            struct.get listType 5
            asNonNull()
            set subL
            get lhs
            struct.get listType 6
            asNonNull()
            set subR
            get subL
            struct.get listType 2
            get subR
            struct.get listType 2
            i32.geU()
            ifThen do
              get subL
              get subR
              get rhs
              instr.call mkBranch
              instr.call mkBranch
              return()
            get subL
            get subR
            struct.get listType 5
            asNonNull()
            instr.call mkBranch
            get subR
            struct.get listType 6
            asNonNull()
            get rhs
            instr.call mkBranch
            instr.call mkBranch
            return()
          get rhsDepth
          get lhsDepth
          i32.const 1
          i32.add()
          i32.gtU()
          ifThen do
            get rhs
            struct.get listType 5
            asNonNull()
            set subL
            get rhs
            struct.get listType 6
            asNonNull()
            set subR
            get subR
            struct.get listType 2
            get subL
            struct.get listType 2
            i32.geU()
            ifThen do
              get lhs
              get subL
              instr.call mkBranch
              get subR
              instr.call mkBranch
              return()
            get lhs
            get subL
            struct.get listType 5
            asNonNull()
            instr.call mkBranch
            get subL
            struct.get listType 6
            asNonNull()
            get subR
            instr.call mkBranch
            instr.call mkBranch
            return()
          get lhs
          get rhs
          emitReturnCall mkBranch
  (mkBranch, balance)

{{
Emits `balance` and `seqConcat` helpers for Wasm GC `VList` trees, coalescing leaf chunks up to 32 elements.
}}
internal.runtime.ListOps.emitConcat : TypeIdx -> TypeIdx -> TypeIdx -> GlobalReference ->{TypeCtx, ModuleCtx} (FuncReference, FuncReference)
internal.runtime.ListOps.emitConcat listType valuesType anyValueType emptyValuesGlobal =
  use array copy
  use func *
  use local get named set tee
  listRef = agg.ref listType
  valuesRef = agg.ref valuesType
  (mkBranch, balance) = ListOps.emitBalance listType emptyValuesGlobal
  (seqConcat, defSeqConcat) =
    declare.func.named
      "seqConcat"
      (param.named "lhs" listRef * param.named "rhs" listRef => result listRef)
  defSeqConcat cases
    (lhs, rhs) ->
      lhsSize = named "lhsSize" i32
      rhsSize = named "rhsSize" i32
      lhsDepth = named "lhsDepth" i32
      rhsDepth = named "rhsDepth" i32
      total = named "total" i32
      dest = named "dest" valuesRef
      get lhs
      struct.get listType 1
      tee lhsSize
      i32.eqz()
      ifThen do
        get rhs
        return()
      get rhs
      struct.get listType 1
      tee rhsSize
      i32.eqz()
      ifThen do
        get lhs
        return()
      get lhs
      struct.get listType 2
      set lhsDepth
      get rhs
      struct.get listType 2
      set rhsDepth
      get lhsDepth
      get rhsDepth
      i32.or()
      i32.eqz()
      ifThen do
        get lhsSize
        get rhsSize
        i32.add()
        tee total
        i32.const 32
        i32.leU()
        ifThen do
          i32.const 0
          struct.new anyValueType
          get total
          array.new valuesType
          tee dest
          i32.const 0
          get lhs
          struct.get listType 4
          get lhs
          struct.get listType 3
          get lhsSize
          copy valuesType valuesType
          get dest
          get lhsSize
          get rhs
          struct.get listType 4
          get rhs
          struct.get listType 3
          get rhsSize
          copy valuesType valuesType
          pushTag VList
          get total
          i32.const 0
          i32.const 0
          get dest
          instr.ref.null listType
          instr.ref.null listType
          struct.new listType
          return()
        get lhs
        get rhs
        emitReturnCall mkBranch
      get lhsDepth
      get rhsDepth
      i32.gtU()
      ifThen do
        get lhs
        struct.get listType 5
        asNonNull()
        get lhs
        struct.get listType 6
        asNonNull()
        get rhs
        instr.call seqConcat
        instr.call balance
        return()
      get rhsDepth
      get lhsDepth
      i32.gtU()
      ifThen do
        get lhs
        get rhs
        struct.get listType 5
        asNonNull()
        instr.call seqConcat
        get rhs
        struct.get listType 6
        asNonNull()
        instr.call balance
        return()
      get lhs
      get rhs
      emitReturnCall mkBranch
  (balance, seqConcat)

{{
Defines `buildSeq` in pure Wasm GC (zero-copy single struct for lists of 32 elements or fewer, balanced binary tree of 32-element leaves for larger lists) and exports `buildSeq`, `seqEmpty`, `List_size`, and `List_at` to the runtime API.
}}
internal.runtime.Helper.BuildSeq.define : Runtime.Types ->{TypeCtx, ModuleCtx} FuncReference
internal.runtime.Helper.BuildSeq.define types =
  use Runtime.Types internalRef internalType valueRef valueType
  use array copy
  use func *
  use local get named set tee
  anyValueType = internalType InternalType.Value types
  valuesType = internalType Values types
  valuesRef = internalRef Values types
  listType = valueType VList types
  listRef = valueRef VList types
  (emptyValuesGlobal, emptyListGlobal) = ListOps.emitEmpty listType valuesType
  seqEmpty =
    def.func.named "seqEmpty" (func.void => result listRef) do
      global.get emptyListGlobal
  export.func "seqEmpty" seqEmpty
  listSizeFn =
    def.func.named "List_size" (param.named "list" listRef => result i32) cases
      list ->
        get list
        struct.get listType 1
  export.func "List_size" listSizeFn
  seqAt = ListOps.emitSeqAt listType valuesType anyValueType
  export.func "List_at" seqAt
  (_, balance) = ListOps.emitBalance listType emptyValuesGlobal
  (seqFromRange, defSeqFromRange) =
    declare.func.named
      "seqFromRange"
      (param.named "els" valuesRef * param.named "start" i32 * param.named "cnt" i32 => result listRef)
  defSeqFromRange cases
    (els, start, cnt) ->
      dest = named "dest" valuesRef
      half = named "half" i32
      get cnt
      i32.const 32
      i32.leU()
      ifThen do
        i32.const 0
        struct.new anyValueType
        get cnt
        array.new valuesType
        tee dest
        i32.const 0
        get els
        get start
        get cnt
        copy valuesType valuesType
        pushTag VList
        get cnt
        i32.const 0
        i32.const 0
        get dest
        instr.ref.null listType
        instr.ref.null listType
        struct.new listType
        return()
      get cnt
      i32.const 1
      i32.shrU()
      set half
      get els
      get start
      get half
      instr.call seqFromRange
      get els
      get start
      get half
      i32.add()
      get cnt
      get half
      i32.sub()
      instr.call seqFromRange
      emitReturnCall balance
  buildSeq =
    def.func.named "buildSeq" (BuildSeq.signature types) cases
      els ->
        elsLen = named "elsLen" i32
        get els
        array.len()
        tee elsLen
        i32.eqz()
        ifThen do
          global.get emptyListGlobal
          return()
        get elsLen
        i32.const 32
        i32.leU()
        ifThen do
          pushTag VList
          get elsLen
          i32.const 0
          i32.const 0
          get els
          instr.ref.null listType
          instr.ref.null listType
          struct.new listType
          return()
        get els
        i32.const 0
        get elsLen
        emitReturnCall seqFromRange
  export.func "buildSeq" buildSeq
  buildSeq

internal.runtime.replacements.unison_base.List_empty : Replacement
internal.runtime.replacements.unison_base.List_empty =
  builder name runtime =
    listType = Runtime.valueType VList runtime
    valuesType = Runtime.internalType Values runtime
    (_, emptyListGlobal) = ListOps.emitEmpty listType valuesType
    defDirectFunc name runtime 0 do
      global.get emptyListGlobal
  NativeTerm (SigDirect 0) None builder

internal.runtime.replacements.unison_base.List_size : Replacement
internal.runtime.replacements.unison_base.List_size =
  wasmExpression 1 (runtime env vars -> let
    pushTag VNat
    env' = pushVar env (List.unsafeAt 0 vars)
    ref.cast (Runtime.valueRef VList runtime)
    struct.get (Runtime.valueType VList runtime) 1
    i64.extendI32U()
    struct.new (Runtime.valueType VNat runtime)
    env')

internal.runtime.replacements.unison_base.List_cons : Replacement
internal.runtime.replacements.unison_base.List_cons =
  builder name runtime =
    use array copy
    use local get named set tee
    anyValueRef = Runtime.internalRef InternalType.Value runtime
    anyValueType = Runtime.internalType InternalType.Value runtime
    valuesType = Runtime.internalType Values runtime
    valuesRef = Runtime.internalRef Values runtime
    listType = Runtime.valueType VList runtime
    listRef = Runtime.valueRef VList runtime
    (emptyValuesGlobal, _) = ListOps.emitEmpty listType valuesType
    (_, seqConcat) = ListOps.emitConcat listType valuesType anyValueType emptyValuesGlobal
    defDirectFunc name runtime 2 do
      elem = named "elem" anyValueRef
      seq = named "seq" listRef
      seqSize = named "seqSize" i32
      dest = named "dest" valuesRef
      getDirectArg 0 runtime
      set elem
      getDirectArg 1 runtime
      ref.cast listRef
      tee seq
      struct.get listType 1
      tee seqSize
      i32.eqz()
      ifThen do
        pushTag VList
        i32.const 1
        i32.const 0
        i32.const 0
        get elem
        newFixed valuesType 1
        instr.ref.null listType
        instr.ref.null listType
        struct.new listType
        return()
      get seq
      struct.get listType 2
      i32.eqz()
      ifThen do
        get seqSize
        i32.const 32
        i32.ltU()
        ifThen do
          get elem
          get seqSize
          i32.const 1
          i32.add()
          array.new valuesType
          tee dest
          i32.const 1
          get seq
          struct.get listType 4
          get seq
          struct.get listType 3
          get seqSize
          copy valuesType valuesType
          pushTag VList
          get seqSize
          i32.const 1
          i32.add()
          i32.const 0
          i32.const 0
          get dest
          instr.ref.null listType
          instr.ref.null listType
          struct.new listType
          return()
      pushTag VList
      i32.const 1
      i32.const 0
      i32.const 0
      get elem
      newFixed valuesType 1
      instr.ref.null listType
      instr.ref.null listType
      struct.new listType
      get seq
      emitReturnCall seqConcat
  NativeTerm (SigDirect 2) None builder

internal.runtime.replacements.unison_base.List_snoc : Replacement
internal.runtime.replacements.unison_base.List_snoc =
  builder name runtime =
    use array copy
    use local get named set tee
    anyValueRef = Runtime.internalRef InternalType.Value runtime
    anyValueType = Runtime.internalType InternalType.Value runtime
    valuesType = Runtime.internalType Values runtime
    valuesRef = Runtime.internalRef Values runtime
    listType = Runtime.valueType VList runtime
    listRef = Runtime.valueRef VList runtime
    (emptyValuesGlobal, _) = ListOps.emitEmpty listType valuesType
    (_, seqConcat) = ListOps.emitConcat listType valuesType anyValueType emptyValuesGlobal
    defDirectFunc name runtime 2 do
      seq = named "seq" listRef
      elem = named "elem" anyValueRef
      seqSize = named "seqSize" i32
      dest = named "dest" valuesRef
      getDirectArg 1 runtime
      set elem
      getDirectArg 0 runtime
      ref.cast listRef
      tee seq
      struct.get listType 1
      tee seqSize
      i32.eqz()
      ifThen do
        pushTag VList
        i32.const 1
        i32.const 0
        i32.const 0
        get elem
        newFixed valuesType 1
        instr.ref.null listType
        instr.ref.null listType
        struct.new listType
        return()
      get seq
      struct.get listType 2
      i32.eqz()
      ifThen do
        get seqSize
        i32.const 32
        i32.ltU()
        ifThen do
          get elem
          get seqSize
          i32.const 1
          i32.add()
          array.new valuesType
          tee dest
          i32.const 0
          get seq
          struct.get listType 4
          get seq
          struct.get listType 3
          get seqSize
          copy valuesType valuesType
          pushTag VList
          get seqSize
          i32.const 1
          i32.add()
          i32.const 0
          i32.const 0
          get dest
          instr.ref.null listType
          instr.ref.null listType
          struct.new listType
          return()
      get seq
      pushTag VList
      i32.const 1
      i32.const 0
      i32.const 0
      get elem
      newFixed valuesType 1
      instr.ref.null listType
      instr.ref.null listType
      struct.new listType
      emitReturnCall seqConcat
  NativeTerm (SigDirect 2) None builder

internal.runtime.replacements.unison_base.List_append : Replacement
internal.runtime.replacements.unison_base.List_append =
  builder name runtime =
    anyValueType = Runtime.internalType InternalType.Value runtime
    valuesType = Runtime.internalType Values runtime
    listType = Runtime.valueType VList runtime
    listRef = Runtime.valueRef VList runtime
    (emptyValuesGlobal, _) = ListOps.emitEmpty listType valuesType
    (_, seqConcat) = ListOps.emitConcat listType valuesType anyValueType emptyValuesGlobal
    defDirectFunc name runtime 2 do
      getDirectArg 0 runtime
      ref.cast listRef
      getDirectArg 1 runtime
      ref.cast listRef
      emitReturnCall seqConcat
  NativeTerm (SigDirect 2) None builder

internal.runtime.replacements.unison_base.List_at : Replacement
internal.runtime.replacements.unison_base.List_at =
  builder name runtime =
    use local get named set tee
    (someID, someCtor) = constructorGlobal (termLink Some)
    (noneID, noneCtor) = constructorGlobal (termLink None)
    anyValueType = Runtime.internalType InternalType.Value runtime
    valuesType = Runtime.internalType Values runtime
    listType = Runtime.valueType VList runtime
    listRef = Runtime.valueRef VList runtime
    dataType = Runtime.valueType VData runtime
    seqAt = ListOps.emitSeqAt listType valuesType anyValueType
    defDirectFunc name runtime 2 do
      idxNat = named "idxNat" i64
      seq = named "seq" listRef
      getDirectArg 0 runtime
      ref.cast (Runtime.valueRef VNat runtime)
      struct.get (Runtime.valueType VNat runtime) 1
      set idxNat
      getDirectArg 1 runtime
      ref.cast listRef
      tee seq
      struct.get listType 1
      i64.extendI32U()
      get idxNat
      i64.leU()
      ifThen do
        pushTag VData
        global.get noneID
        i32.const noneCtor
        newFixed valuesType 0
        struct.new dataType
        return()
      pushTag VData
      global.get someID
      i32.const someCtor
      get seq
      get idxNat
      i32.wrapI64()
      instr.call seqAt
      newFixed valuesType 1
      struct.new dataType
  NativeTerm (SigDirect 2) None builder

internal.runtime.replacements.unison_base.List_take : Replacement
internal.runtime.replacements.unison_base.List_take =
  builder name runtime =
    use func *
    use local get named set tee
    anyValueType = Runtime.internalType InternalType.Value runtime
    valuesType = Runtime.internalType Values runtime
    listType = Runtime.valueType VList runtime
    listRef = Runtime.valueRef VList runtime
    (emptyValuesGlobal, emptyListGlobal) = ListOps.emitEmpty listType valuesType
    (_, seqConcat) = ListOps.emitConcat listType valuesType anyValueType emptyValuesGlobal
    (seqTake, defSeqTake) =
      declare.func.named
        "seqTake"
        (param.named "seq" listRef * param.named "cnt" i32 => result listRef)
    defSeqTake cases
      (seq, cnt) ->
        subL = named "subL" listRef
        leftSize = named "leftSize" i32
        get seq
        struct.get listType 2
        i32.eqz()
        ifThen do
          pushTag VList
          get cnt
          i32.const 0
          get seq
          struct.get listType 3
          get seq
          struct.get listType 4
          instr.ref.null listType
          instr.ref.null listType
          struct.new listType
          return()
        get seq
        struct.get listType 5
        asNonNull()
        tee subL
        struct.get listType 1
        tee leftSize
        get cnt
        i32.eq()
        ifThen do
          get subL
          return()
        get cnt
        get leftSize
        i32.ltU()
        ifThen do
          get subL
          get cnt
          emitReturnCall seqTake
        get subL
        get seq
        struct.get listType 6
        asNonNull()
        get cnt
        get leftSize
        i32.sub()
        instr.call seqTake
        emitReturnCall seqConcat
    defDirectFunc name runtime 2 do
      cntNat = named "cntNat" i64
      seq = named "seq" listRef
      getDirectArg 0 runtime
      ref.cast (Runtime.valueRef VNat runtime)
      struct.get (Runtime.valueType VNat runtime) 1
      tee cntNat
      i64.eqz()
      ifThen do
        global.get emptyListGlobal
        return()
      getDirectArg 1 runtime
      ref.cast listRef
      tee seq
      struct.get listType 1
      i64.extendI32U()
      get cntNat
      i64.leU()
      ifThen do
        get seq
        return()
      get seq
      get cntNat
      i32.wrapI64()
      emitReturnCall seqTake
  NativeTerm (SigDirect 2) None builder

internal.runtime.replacements.unison_base.List_drop : Replacement
internal.runtime.replacements.unison_base.List_drop =
  builder name runtime =
    use func *
    use local get named set tee
    anyValueType = Runtime.internalType InternalType.Value runtime
    valuesType = Runtime.internalType Values runtime
    listType = Runtime.valueType VList runtime
    listRef = Runtime.valueRef VList runtime
    (emptyValuesGlobal, emptyListGlobal) = ListOps.emitEmpty listType valuesType
    (_, seqConcat) = ListOps.emitConcat listType valuesType anyValueType emptyValuesGlobal
    (seqDrop, defSeqDrop) =
      declare.func.named
        "seqDrop"
        (param.named "seq" listRef * param.named "cnt" i32 => result listRef)
    defSeqDrop cases
      (seq, cnt) ->
        subL = named "subL" listRef
        leftSize = named "leftSize" i32
        get seq
        struct.get listType 2
        i32.eqz()
        ifThen do
          pushTag VList
          get seq
          struct.get listType 1
          get cnt
          i32.sub()
          i32.const 0
          get seq
          struct.get listType 3
          get cnt
          i32.add()
          get seq
          struct.get listType 4
          instr.ref.null listType
          instr.ref.null listType
          struct.new listType
          return()
        get seq
        struct.get listType 5
        asNonNull()
        tee subL
        struct.get listType 1
        tee leftSize
        get cnt
        i32.eq()
        ifThen do
          get seq
          struct.get listType 6
          asNonNull()
          return()
        get cnt
        get leftSize
        i32.ltU()
        ifThen do
          get subL
          get cnt
          instr.call seqDrop
          get seq
          struct.get listType 6
          asNonNull()
          emitReturnCall seqConcat
        get seq
        struct.get listType 6
        asNonNull()
        get cnt
        get leftSize
        i32.sub()
        emitReturnCall seqDrop
    defDirectFunc name runtime 2 do
      cntNat = named "cntNat" i64
      seq = named "seq" listRef
      getDirectArg 0 runtime
      ref.cast (Runtime.valueRef VNat runtime)
      struct.get (Runtime.valueType VNat runtime) 1
      tee cntNat
      i64.eqz()
      ifThen do
        getDirectArg 1 runtime
        return()
      getDirectArg 1 runtime
      ref.cast listRef
      tee seq
      struct.get listType 1
      i64.extendI32U()
      get cntNat
      i64.leU()
      ifThen do
        global.get emptyListGlobal
        return()
      get seq
      get cntNat
      i32.wrapI64()
      emitReturnCall seqDrop
  NativeTerm (SigDirect 2) None builder

internal.runtime.replacements.unison_base.List_viewl : Replacement
internal.runtime.replacements.unison_base.List_viewl =
  builder name runtime =
    use func *
    use local get named set tee
    (velemID, velemCtor) = constructorGlobal (termLink VElem)
    (vemptyID, vemptyCtor) = constructorGlobal (termLink VEmpty)
    anyValueRef = Runtime.internalRef InternalType.Value runtime
    valuesType = Runtime.internalType Values runtime
    listType = Runtime.valueType VList runtime
    listRef = Runtime.valueRef VList runtime
    dataType = Runtime.valueType VData runtime
    (emptyValuesGlobal, emptyListGlobal) = ListOps.emitEmpty listType valuesType
    (_, balance) = ListOps.emitBalance listType emptyValuesGlobal
    unconsSig = func.Signature.Signature [(Some "seq", listRef)] [anyValueRef, listRef] ()
    (seqUncons, defSeqUncons) = declare.func.named "seqUncons" unconsSig
    defSeqUncons do
      seq = LocalIdx 0
      subL = named "subL" listRef
      subR = named "subR" listRef
      headVal = named "headVal" anyValueRef
      tailSeq = named "tailSeq" listRef
      get seq
      struct.get listType 2
      i32.eqz()
      ifThen do
        get seq
        struct.get listType 4
        get seq
        struct.get listType 3
        array.get valuesType
        set headVal
        get seq
        struct.get listType 1
        i32.const 1
        i32.eq()
        ifThen do
          get headVal
          global.get emptyListGlobal
          return()
        get headVal
        pushTag VList
        get seq
        struct.get listType 1
        i32.const 1
        i32.sub()
        i32.const 0
        get seq
        struct.get listType 3
        i32.const 1
        i32.add()
        get seq
        struct.get listType 4
        instr.ref.null listType
        instr.ref.null listType
        struct.new listType
        return()
      get seq
      struct.get listType 5
      asNonNull()
      set subL
      get seq
      struct.get listType 6
      asNonNull()
      set subR
      get subL
      struct.get listType 1
      i32.const 1
      i32.eq()
      ifThen do
        get subL
        struct.get listType 4
        get subL
        struct.get listType 3
        array.get valuesType
        get subR
        return()
      get subL
      instr.call seqUncons
      set tailSeq
      set headVal
      get headVal
      get tailSeq
      get subR
      instr.call balance
    defDirectFunc name runtime 1 do
      seq = named "seq" listRef
      headVal = named "headVal" anyValueRef
      tailSeq = named "tailSeq" listRef
      getDirectArg 0 runtime
      ref.cast listRef
      tee seq
      struct.get listType 1
      i32.eqz()
      ifThen do
        pushTag VData
        global.get vemptyID
        i32.const vemptyCtor
        newFixed valuesType 0
        struct.new dataType
        return()
      get seq
      instr.call seqUncons
      set tailSeq
      set headVal
      pushTag VData
      global.get velemID
      i32.const velemCtor
      get headVal
      get tailSeq
      newFixed valuesType 2
      struct.new dataType
  NativeTerm (SigDirect 1) None builder

internal.runtime.replacements.unison_base.List_viewr : Replacement
internal.runtime.replacements.unison_base.List_viewr =
  builder name runtime =
    use func *
    use local get named set tee
    (velemID, velemCtor) = constructorGlobal (termLink VElem)
    (vemptyID, vemptyCtor) = constructorGlobal (termLink VEmpty)
    anyValueRef = Runtime.internalRef InternalType.Value runtime
    valuesType = Runtime.internalType Values runtime
    listType = Runtime.valueType VList runtime
    listRef = Runtime.valueRef VList runtime
    dataType = Runtime.valueType VData runtime
    (emptyValuesGlobal, emptyListGlobal) = ListOps.emitEmpty listType valuesType
    (_, balance) = ListOps.emitBalance listType emptyValuesGlobal
    unsnocSig = func.Signature.Signature [(Some "seq", listRef)] [listRef, anyValueRef] ()
    (seqUnsnoc, defSeqUnsnoc) = declare.func.named "seqUnsnoc" unsnocSig
    defSeqUnsnoc do
      seq = LocalIdx 0
      subL = named "subL" listRef
      subR = named "subR" listRef
      initSeq = named "initSeq" listRef
      lastVal = named "lastVal" anyValueRef
      get seq
      struct.get listType 2
      i32.eqz()
      ifThen do
        get seq
        struct.get listType 4
        get seq
        struct.get listType 3
        get seq
        struct.get listType 1
        i32.add()
        i32.const 1
        i32.sub()
        array.get valuesType
        set lastVal
        get seq
        struct.get listType 1
        i32.const 1
        i32.eq()
        ifThen do
          global.get emptyListGlobal
          get lastVal
          return()
        pushTag VList
        get seq
        struct.get listType 1
        i32.const 1
        i32.sub()
        i32.const 0
        get seq
        struct.get listType 3
        get seq
        struct.get listType 4
        instr.ref.null listType
        instr.ref.null listType
        struct.new listType
        get lastVal
        return()
      get seq
      struct.get listType 5
      asNonNull()
      set subL
      get seq
      struct.get listType 6
      asNonNull()
      set subR
      get subR
      struct.get listType 1
      i32.const 1
      i32.eq()
      ifThen do
        get subL
        get subR
        struct.get listType 4
        get subR
        struct.get listType 3
        array.get valuesType
        return()
      get subR
      instr.call seqUnsnoc
      set lastVal
      set initSeq
      get subL
      get initSeq
      instr.call balance
      get lastVal
    defDirectFunc name runtime 1 do
      seq = named "seq" listRef
      initSeq = named "initSeq" listRef
      lastVal = named "lastVal" anyValueRef
      getDirectArg 0 runtime
      ref.cast listRef
      tee seq
      struct.get listType 1
      i32.eqz()
      ifThen do
        pushTag VData
        global.get vemptyID
        i32.const vemptyCtor
        newFixed valuesType 0
        struct.new dataType
        return()
      get seq
      instr.call seqUnsnoc
      set lastVal
      set initSeq
      pushTag VData
      global.get velemID
      i32.const velemCtor
      get initSeq
      get lastVal
      newFixed valuesType 2
      struct.new dataType
  NativeTerm (SigDirect 1) None builder

internal.runtime.replacements.unison_base.Universal_compare.defineCompareValues : Runtime -> GlobalReference -> FuncReference ->{TypeCtx, ModuleCtx} FuncReference
internal.runtime.replacements.unison_base.Universal_compare.defineCompareValues runtime rt jsCompare =
  use func *
  use local get named set tee
  anyValueRef = Runtime.internalRef InternalType.Value runtime
  anyValueType = Runtime.internalType InternalType.Value runtime
  valuesType = Runtime.internalType Values runtime
  valuesRef = Runtime.internalRef Values runtime
  listType = Runtime.valueType VList runtime
  listRef = Runtime.valueRef VList runtime
  compareIds = Runtime.helper CompareIds runtime
  compareStrings = Runtime.helper CompareStrings runtime
  seqAt = ListOps.emitSeqAt listType valuesType anyValueType
  (compareValues, defCompareValues) = declare.func.named "compareValues" (param.named "lhs" anyValueRef * param.named "rhs" anyValueRef => result i32)
  (compareArgs, defCompareArgs) = declare.func.named "compareArgs" (param.named "lhsArgs" valuesRef * param.named "rhsArgs" valuesRef => result i32)
  (compareSeqs, defCompareSeqs) = declare.func.named "compareSeqs" (param.named "lhsSeq" listRef * param.named "rhsSeq" listRef => result i32)
  threeWay ty pushA pushB lt gt =
    valA = named "valA" ty
    valB = named "valB" ty
    pushA()
    set valA
    pushB()
    set valB
    get valA
    get valB
    gt()
    get valA
    get valB
    lt()
    i32.sub()
  returnIfNonZero = do
    cmpRes = named "cmpRes" i32
    tee cmpRes
    ifThen do
      get cmpRes
      return()
  isIntOrNat tagLocal = do
    get tagLocal
    pushTag VNat
    i32.eq()
    get tagLocal
    pushTag VInt
    i32.eq()
    i32.or()
  isFnOrClosure tagLocal = do
    get tagLocal
    pushTag VFunc
    i32.eq()
    get tagLocal
    pushTag VClosure
    i32.eq()
    i32.or()
  defCompareValues cases
    (lhs, rhs) ->
      tagA = named "tagA" i32
      tagB = named "tagB" i32
      field vt index side = do
        get side
        ref.cast (Runtime.valueRef vt runtime)
        struct.get (Runtime.valueType vt runtime) index
      whenTag vt body =
        get tagA
        pushTag vt
        i32.eq()
        ifThen do
          body()
          return()
      get lhs
      get rhs
      ref.eq()
      ifThen do
        i32.const 0
        return()
      get lhs
      struct.get anyValueType 0
      tee tagA
      get rhs
      struct.get anyValueType 0
      tee tagB
      i32.eq()
      ifThen do
        whenTag VNat do threeWay i64 (field VNat 1 lhs) (field VNat 1 rhs) i64.ltU i64.gtU
        whenTag VInt do threeWay i64 (field VInt 1 lhs) (field VInt 1 rhs) i64.ltS i64.gtS
        whenTag VBoolean do threeWay i32 (field VBoolean 1 lhs) (field VBoolean 1 rhs) i32.ltU i32.gtU
        whenTag VText do
          field VText 1 lhs ()
          field VText 1 rhs ()
          instr.call compareStrings
        whenTag VChar do
          field VChar 1 lhs ()
          field VChar 1 rhs ()
          instr.call compareStrings
        whenTag VTypeLink do
          field VTypeLink 1 lhs ()
          field VTypeLink 1 rhs ()
          instr.call compareIds
        whenTag VTermLink do
          field VTermLink 1 lhs ()
          field VTermLink 1 rhs ()
          instr.call compareIds
          returnIfNonZero()
          threeWay i32 (field VTermLink 2 lhs) (field VTermLink 2 rhs) i32.ltU i32.gtU
        whenTag VData do
          field VData 1 lhs ()
          field VData 1 rhs ()
          instr.call compareIds
          returnIfNonZero()
          threeWay i32 (field VData 2 lhs) (field VData 2 rhs) i32.ltU i32.gtU
          returnIfNonZero()
          field VData 3 lhs ()
          field VData 3 rhs ()
          instr.call compareArgs
        whenTag VList do
          get lhs
          ref.cast listRef
          get rhs
          ref.cast listRef
          instr.call compareSeqs
        whenTag VArray do
          field VArray 2 lhs ()
          field VArray 2 rhs ()
          instr.call compareArgs
        whenTag VFunc do
          field VFunc 1 lhs ()
          field VFunc 1 rhs ()
          instr.call compareIds
        whenTag VClosure do
          field VClosure 1 lhs ()
          field VClosure 1 rhs ()
          instr.call compareIds
          returnIfNonZero()
          field VClosure 4 lhs ()
          field VClosure 4 rhs ()
          instr.call compareArgs
      get tagA
      get tagB
      i32.ne()
      ifThen do
        isIntOrNat tagA ()
        isIntOrNat tagB ()
        i32.and()
        isFnOrClosure tagA ()
        isFnOrClosure tagB ()
        i32.and()
        i32.or()
        i32.eqz()
        ifThen do
          threeWay i32 (do get tagA) (do get tagB) i32.ltS i32.gtS
          return()
      global.get rt
      get lhs
      get rhs
      instr.call jsCompare
      ref.cast (Runtime.valueRef VInt runtime)
      struct.get (Runtime.valueType VInt runtime) 1
      i32.wrapI64()
  defCompareArgs cases
    (lhsArgs, rhsArgs) ->
      index = named "index" i32
      lhsLen = named "lhsLen" i32
      rhsLen = named "rhsLen" i32
      minLen = named "minLen" i32
      get lhsArgs
      array.len()
      tee lhsLen
      set minLen
      get rhsArgs
      array.len()
      tee rhsLen
      get lhsLen
      i32.ltU()
      ifThen do
        get rhsLen
        set minLen
      i32.const 0
      set index
      instr.loop cases
        continue ->
          get index
          get minLen
          i32.geU()
          ifThen do
            threeWay i32 (do get lhsLen) (do get rhsLen) i32.ltU i32.gtU
            return()
          get lhsArgs
          get index
          array.get valuesType
          get rhsArgs
          get index
          array.get valuesType
          instr.call compareValues
          returnIfNonZero()
          get index
          i32.const 1
          i32.add()
          set index
          br continue
      unreachable()
  defCompareSeqs cases
    (lhsSeq, rhsSeq) ->
      lhsSize = named "lhsSize" i32
      rhsSize = named "rhsSize" i32
      minSize = named "minSize" i32
      index = named "index" i32
      lhsVals = named "lhsVals" valuesRef
      rhsVals = named "rhsVals" valuesRef
      lhsOff = named "lhsOff" i32
      rhsOff = named "rhsOff" i32
      get lhsSeq
      get rhsSeq
      ref.eq()
      ifThen do
        i32.const 0
        return()
      get lhsSeq
      struct.get listType 1
      tee lhsSize
      set minSize
      get rhsSeq
      struct.get listType 1
      tee rhsSize
      get lhsSize
      i32.ltU()
      ifThen do
        get rhsSize
        set minSize
      get lhsSeq
      struct.get listType 2
      get rhsSeq
      struct.get listType 2
      i32.or()
      i32.eqz()
      ifThen do
        get lhsSeq
        struct.get listType 4
        set lhsVals
        get lhsSeq
        struct.get listType 3
        set lhsOff
        get rhsSeq
        struct.get listType 4
        set rhsVals
        get rhsSeq
        struct.get listType 3
        set rhsOff
        i32.const 0
        set index
        instr.loop cases
          continue ->
            get index
            get minSize
            i32.geU()
            ifThen do
              threeWay i32 (do get lhsSize) (do get rhsSize) i32.ltU i32.gtU
              return()
            get lhsVals
            get lhsOff
            get index
            i32.add()
            array.get valuesType
            get rhsVals
            get rhsOff
            get index
            i32.add()
            array.get valuesType
            instr.call compareValues
            returnIfNonZero()
            get index
            i32.const 1
            i32.add()
            set index
            br continue
        unreachable()
      i32.const 0
      set index
      instr.loop cases
        continue ->
          get index
          get minSize
          i32.geU()
          ifThen do
            threeWay i32 (do get lhsSize) (do get rhsSize) i32.ltU i32.gtU
            return()
          get lhsSeq
          get index
          instr.call seqAt
          get rhsSeq
          get index
          instr.call seqAt
          instr.call compareValues
          returnIfNonZero()
          get index
          i32.const 1
          i32.add()
          set index
          br continue
      unreachable()
  compareValues

internal.runtime.replacements.unison_base.Universal_compare.jsSource : Text
internal.runtime.replacements.unison_base.Universal_compare.jsSource =
  """
  (() => {
    function compareJSPrimitives(a, b) {
      return a < b ? -1 : a > b ? 1 : 0;
    }
    function compareArgs(rt, as, bs) {
      let aLen = rt.Args_length(as);
      let bLen = rt.Args_length(bs);
      let minLen = Math.min(aLen, bLen);
      for (let i = 0; i < minLen; i++) {
        let cmp = compare(rt, rt.Args_at(as, i), rt.Args_at(bs, i));
        if (cmp !== 0) return cmp;
      }
      return compareJSPrimitives(aLen, bLen);
    }
    function compare(rt, a, b) {
      if (a === b) return 0;
      if (!rt.Value_detect(a) || !rt.Value_detect(b)) rt.js.panic(rt, "builtin.bug", rt.Tuple_Cons(rt.Text('Attempted to compare non-value'), rt.Tuple_Cons(rt.Foreign([a, b]), rt.Unit())));
      let aTag = rt.Value_getTag(a);
      let bTag = rt.Value_getTag(b);
      if (!rt.js.valueTagsCompatible(rt, aTag, bTag)) return compareJSPrimitives(aTag, bTag);
      switch (aTag) {
        case rt.Nat_TAG.value:
        case rt.Int_TAG.value: {
          let aRaw = rt.Nat_getValue(a);
          let bRaw = rt.Nat_getValue(b);
          let aVal = aTag === rt.Nat_TAG.value ? BigInt.asUintN(64, aRaw) : BigInt.asIntN(64, aRaw);
          let bVal = bTag === rt.Nat_TAG.value ? BigInt.asUintN(64, bRaw) : BigInt.asIntN(64, bRaw);
          return compareJSPrimitives(aVal, bVal);
        }
        case rt.Float_TAG.value:
          return compareJSPrimitives(rt.Float_getValue(a), rt.Float_getValue(b));
        case rt.TypeLink_TAG.value:
          return rt.compareIds(rt.TypeLink_getId(a), rt.TypeLink_getId(b));
        case rt.TermLink_TAG.value: {
          let idComparison = rt.compareIds(rt.TermLink_getId(a), rt.TermLink_getId(b));
          if (idComparison !== 0) return idComparison;
          return compareJSPrimitives(rt.TermLink_getConstructor(a), rt.TermLink_getConstructor(b));
        }
        case rt.Char_TAG.value:
          return compareJSPrimitives(rt.Char_getValue(a), rt.Char_getValue(b));
        case rt.Text_TAG.value:
          return compareJSPrimitives(rt.Text_getValue(a), rt.Text_getValue(b));
        case rt.Data_TAG.value: {
          let typeComparison = rt.compareIds(rt.Data_getType(a), rt.Data_getType(b));
          if (typeComparison !== 0) return typeComparison;
          let constructorComparison = compareJSPrimitives(rt.Data_getConstructor(a), rt.Data_getConstructor(b));
          if (constructorComparison !== 0) return constructorComparison;
          return compareArgs(rt, rt.Data_getArgs(a), rt.Data_getArgs(b));
        }
        case rt.Request_TAG.value: {
          let dataComparison = compare(rt, rt.Request_getData(a), rt.Request_getData(b));
          if (dataComparison !== 0) return dataComparison;
          return compare(rt, rt.Request_getContinue(a), rt.Request_getContinue(b));
        }
        case rt.Function_TAG.value:
          return rt.compareIds(rt.Function_getId(a), rt.Function_getId(b));
        case rt.Closure_TAG.value: {
          let idComparison = rt.compareIds(rt.Closure_getId(a), rt.Closure_getId(b));
          if (idComparison !== 0) return idComparison;
          return compareArgs(rt, rt.Closure_getBound(a), rt.Closure_getBound(b));
        }
        case rt.Continuation_TAG.value: {
          let dataComparison = compareArgs(rt, rt.Continuation_getData(a), rt.Continuation_getData(b));
          if (dataComparison !== 0) return dataComparison;
          if (rt.Continuation_getImpl(a) === rt.Continuation_getImpl(b)) return 0;
          rt.js.panic(rt, "builtin.bug", rt.Tuple_Cons(rt.Text('Unable to compare different continuations with the same carried data'), rt.Tuple_Cons(rt.Foreign([a, b]), rt.Unit())));
        }
        case rt.Quote_TAG.value:
          return compare(rt, rt.Quote_getValue(a), rt.Quote_getValue(b));
        case rt.Code_TAG.value:
          return compare(rt, rt.Code_getValue(a), rt.Code_getValue(b));
        case rt.Foreign_TAG.value: {
          let valueA = rt.Foreign_getValue(a);
          let valueB = rt.Foreign_getValue(b);
          if (valueA === valueB) return 0;
          if (valueA instanceof rt.js.JSValue && valueB instanceof rt.js.JSValue) {
            valueA = valueA.get();
            valueB = valueB.get();
            if (valueA === valueB) return 0;
            if (typeof valueA === typeof valueB) {
              switch (typeof valueA) {
                case 'number':
                case 'string':
                case 'boolean':
                case 'bigint':
                case 'undefined':
                  return compareJSPrimitives(valueA, valueB);
                default:
              }
            }
          }
          rt.js.panic(rt, "builtin.bug", rt.Tuple_Cons(rt.Text('Unable to compare different foreign values'), rt.Tuple_Cons(rt.Foreign([a, b]), rt.Unit())));
        }
        case rt.Boolean_TAG.value:
          return compareJSPrimitives(rt.Boolean_getValue(a), rt.Boolean_getValue(b));
        case rt.Array_TAG.value:
          return compareArgs(rt, rt.Array_getContents(a), rt.Array_getContents(b));
        case rt.ByteArray_TAG.value: {
          let aView = rt.ByteArray_getContents(a);
          let bView = rt.ByteArray_getContents(b);
          let aBytes = new Uint8Array(aView.buffer, aView.byteOffset, aView.byteLength);
          let bBytes = new Uint8Array(bView.buffer, bView.byteOffset, bView.byteLength);
          for (let i = 0, len = Math.max(aBytes.byteLength, bBytes.byteLength); i < len; i++) {
            let aByte = aBytes[i];
            let bByte = bBytes[i];
            if (aByte == null) return -1;
            if (bByte == null) return 1;
            if (aByte !== bByte) return aByte < bByte ? -1 : 1;
          }
          return 0;
        }
        case rt.Bytes_TAG.value: {
          let aBytes = rt.Bytes_getValue(a).toUint8Array();
          let bBytes = rt.Bytes_getValue(b).toUint8Array();
          for (let i = 0, len = Math.max(aBytes.byteLength, bBytes.byteLength); i < len; i++) {
            let aByte = aBytes[i];
            let bByte = bBytes[i];
            if (aByte == null) return -1;
            if (bByte == null) return 1;
            if (aByte !== bByte) return aByte < bByte ? -1 : 1;
          }
          return 0;
        }
        case rt.List_TAG.value: {
          let aLen = rt.List_size(a);
          let bLen = rt.List_size(b);
          let minLen = Math.min(aLen, bLen);
          for (let i = 0; i < minLen; i++) {
            let cmp = compare(rt, rt.List_at(a, i), rt.List_at(b, i));
            if (cmp !== 0) return cmp;
          }
          return compareJSPrimitives(aLen, bLen);
        }
        default:
          rt.js.panic(rt, "builtin.bug", rt.Tuple_Cons(rt.Text('Unknown value type for comparison'), rt.Tuple_Cons(rt.Foreign([a, b]), rt.Unit())));
      }
    }
    return (rt, a, b) => rt.Int(BigInt(compare(rt, a, b)));
  })()
  """

internal.runtime.replacements.unison_base.Universal_eq.defineEqValues : Runtime -> GlobalReference -> FuncReference ->{TypeCtx, ModuleCtx} FuncReference
internal.runtime.replacements.unison_base.Universal_eq.defineEqValues runtime rt jsEq =
  use func *
  use local get named set tee
  anyValueRef = Runtime.internalRef InternalType.Value runtime
  anyValueType = Runtime.internalType InternalType.Value runtime
  valuesType = Runtime.internalType Values runtime
  valuesRef = Runtime.internalRef Values runtime
  listType = Runtime.valueType VList runtime
  listRef = Runtime.valueRef VList runtime
  compareIds = Runtime.helper CompareIds runtime
  seqAt = ListOps.emitSeqAt listType valuesType anyValueType
  stringsEqual = import.func "wasm:js-string" "equals" (param externref * param externref => result i32)
  (eqValues, defEqValues) = declare.func.named "eqValues" (param.named "lhs" anyValueRef * param.named "rhs" anyValueRef => result i32)
  (eqArgs, defEqArgs) = declare.func.named "eqArgs" (param.named "lhsArgs" valuesRef * param.named "rhsArgs" valuesRef => result i32)
  (eqSeqs, defEqSeqs) = declare.func.named "eqSeqs" (param.named "lhsSeq" listRef * param.named "rhsSeq" listRef => result i32)
  returnIfFalse = do
    i32.eqz()
    ifThen do
      i32.const 0
      return()
  isIntOrNat tagLocal = do
    get tagLocal
    pushTag VNat
    i32.eq()
    get tagLocal
    pushTag VInt
    i32.eq()
    i32.or()
  isFnOrClosure tagLocal = do
    get tagLocal
    pushTag VFunc
    i32.eq()
    get tagLocal
    pushTag VClosure
    i32.eq()
    i32.or()
  defEqValues cases
    (lhs, rhs) ->
      tagA = named "tagA" i32
      tagB = named "tagB" i32
      field vt index side = do
        get side
        ref.cast (Runtime.valueRef vt runtime)
        struct.get (Runtime.valueType vt runtime) index
      whenTag vt body =
        get tagA
        pushTag vt
        i32.eq()
        ifThen do
          body()
          return()
      get lhs
      get rhs
      ref.eq()
      ifThen do
        i32.const 1
        return()
      get lhs
      struct.get anyValueType 0
      tee tagA
      get rhs
      struct.get anyValueType 0
      tee tagB
      i32.eq()
      ifThen do
        whenTag VNat do
          field VNat 1 lhs ()
          field VNat 1 rhs ()
          i64.eq()
        whenTag VInt do
          field VInt 1 lhs ()
          field VInt 1 rhs ()
          i64.eq()
        whenTag VFloat do
          field VFloat 1 lhs ()
          field VFloat 1 rhs ()
          f64.eq()
        whenTag VBoolean do
          field VBoolean 1 lhs ()
          field VBoolean 1 rhs ()
          i32.eq()
        whenTag VText do
          field VText 1 lhs ()
          field VText 1 rhs ()
          instr.call stringsEqual
        whenTag VChar do
          field VChar 1 lhs ()
          field VChar 1 rhs ()
          instr.call stringsEqual
        whenTag VTypeLink do
          field VTypeLink 1 lhs ()
          field VTypeLink 1 rhs ()
          instr.call compareIds
          i32.eqz()
        whenTag VTermLink do
          field VTermLink 1 lhs ()
          field VTermLink 1 rhs ()
          instr.call compareIds
          i32.eqz()
          returnIfFalse()
          field VTermLink 2 lhs ()
          field VTermLink 2 rhs ()
          i32.eq()
        whenTag VData do
          field VData 2 lhs ()
          field VData 2 rhs ()
          i32.eq()
          returnIfFalse()
          field VData 1 lhs ()
          field VData 1 rhs ()
          instr.call compareIds
          i32.eqz()
          returnIfFalse()
          field VData 3 lhs ()
          field VData 3 rhs ()
          instr.call eqArgs
        whenTag VList do
          get lhs
          ref.cast listRef
          get rhs
          ref.cast listRef
          instr.call eqSeqs
        whenTag VArray do
          field VArray 2 lhs ()
          field VArray 2 rhs ()
          instr.call eqArgs
        whenTag VFunc do
          field VFunc 1 lhs ()
          field VFunc 1 rhs ()
          instr.call compareIds
          i32.eqz()
        whenTag VClosure do
          field VClosure 1 lhs ()
          field VClosure 1 rhs ()
          instr.call compareIds
          i32.eqz()
          returnIfFalse()
          field VClosure 4 lhs ()
          field VClosure 4 rhs ()
          instr.call eqArgs
      get tagA
      get tagB
      i32.ne()
      ifThen do
        isIntOrNat tagA ()
        isIntOrNat tagB ()
        i32.and()
        isFnOrClosure tagA ()
        isFnOrClosure tagB ()
        i32.and()
        i32.or()
        i32.eqz()
        ifThen do
          i32.const 0
          return()
      global.get rt
      get lhs
      get rhs
      instr.call jsEq
      ref.cast (Runtime.valueRef VBoolean runtime)
      struct.get (Runtime.valueType VBoolean runtime) 1
  defEqArgs cases
    (lhsArgs, rhsArgs) ->
      index = named "index" i32
      size = named "size" i32
      get lhsArgs
      array.len()
      tee size
      get rhsArgs
      array.len()
      i32.ne()
      ifThen do
        i32.const 0
        return()
      i32.const 0
      set index
      instr.loop cases
        continue ->
          get index
          get size
          i32.geU()
          ifThen do
            i32.const 1
            return()
          get lhsArgs
          get index
          array.get valuesType
          get rhsArgs
          get index
          array.get valuesType
          instr.call eqValues
          returnIfFalse()
          get index
          i32.const 1
          i32.add()
          set index
          br continue
      unreachable()
  defEqSeqs cases
    (lhsSeq, rhsSeq) ->
      size = named "size" i32
      index = named "index" i32
      lhsVals = named "lhsVals" valuesRef
      rhsVals = named "rhsVals" valuesRef
      lhsOff = named "lhsOff" i32
      rhsOff = named "rhsOff" i32
      get lhsSeq
      get rhsSeq
      ref.eq()
      ifThen do
        i32.const 1
        return()
      get lhsSeq
      struct.get listType 1
      tee size
      get rhsSeq
      struct.get listType 1
      i32.ne()
      ifThen do
        i32.const 0
        return()
      get size
      i32.eqz()
      ifThen do
        i32.const 1
        return()
      get lhsSeq
      struct.get listType 2
      get rhsSeq
      struct.get listType 2
      i32.or()
      i32.eqz()
      ifThen do
        get lhsSeq
        struct.get listType 4
        set lhsVals
        get lhsSeq
        struct.get listType 3
        set lhsOff
        get rhsSeq
        struct.get listType 4
        set rhsVals
        get rhsSeq
        struct.get listType 3
        set rhsOff
        i32.const 0
        set index
        instr.loop cases
          continue ->
            get index
            get size
            i32.geU()
            ifThen do
              i32.const 1
              return()
            get lhsVals
            get lhsOff
            get index
            i32.add()
            array.get valuesType
            get rhsVals
            get rhsOff
            get index
            i32.add()
            array.get valuesType
            instr.call eqValues
            returnIfFalse()
            get index
            i32.const 1
            i32.add()
            set index
            br continue
        unreachable()
      i32.const 0
      set index
      instr.loop cases
        continue ->
          get index
          get size
          i32.geU()
          ifThen do
            i32.const 1
            return()
          get lhsSeq
          get index
          instr.call seqAt
          get rhsSeq
          get index
          instr.call seqAt
          instr.call eqValues
          returnIfFalse()
          get index
          i32.const 1
          i32.add()
          set index
          br continue
      unreachable()
  eqValues

internal.runtime.replacements.unison_base.Universal_eq.jsSource : Text
internal.runtime.replacements.unison_base.Universal_eq.jsSource =
  """
  (() => {
    function argsEq(rt, as, bs) {
      let aLen = as ? rt.Args_length(as) : 0;
      let bLen = bs ? rt.Args_length(bs) : 0;
      if (aLen != bLen) return false;
      for (let i = 0; i < aLen; i++) {
        if (!eq(rt, rt.Args_at(as, i), rt.Args_at(bs, i))) return false;
      }
      return true;
    }
    function eq(rt, a, b) {
      if (a === b) return true;
      if (!rt.Value_detect(a) || !rt.Value_detect(b)) return false;
      let aTag = rt.Value_getTag(a);
      let bTag = rt.Value_getTag(b);
      if (!rt.js.valueTagsCompatible(rt, aTag, bTag)) {
        return false;
      }
      switch (aTag) {
        case rt.Nat_TAG.value:
        case rt.Int_TAG.value:
          return rt.Nat_getValue(a) === rt.Nat_getValue(b);
        case rt.Float_TAG.value:
          return rt.Float_getValue(a) === rt.Float_getValue(b);
        case rt.TypeLink_TAG.value:
          return rt.compareIds(rt.TypeLink_getId(a), rt.TypeLink_getId(b)) === 0;
        case rt.TermLink_TAG.value:
          return rt.compareIds(rt.TermLink_getId(a), rt.TermLink_getId(b)) === 0
              && rt.TermLink_getConstructor(a) === rt.TermLink_getConstructor(b);
        case rt.Char_TAG.value:
          return rt.Char_getValue(a) === rt.Char_getValue(b);
        case rt.Text_TAG.value:
          return rt.Text_getValue(a) === rt.Text_getValue(b);
        case rt.Data_TAG.value: {
          if (rt.compareIds(rt.Data_getType(a), rt.Data_getType(b)) !== 0) return false;
          if (rt.Data_getConstructor(a) !== rt.Data_getConstructor(b)) return false;
          return argsEq(rt, rt.Data_getArgs(a), rt.Data_getArgs(b));
        }
        case rt.Request_TAG.value:
          return eq(rt, rt.Request_getData(a), rt.Request_getData(b))
              && eq(rt, rt.Request_getContinue(a), rt.Request_getContinue(b));
        case rt.Function_TAG.value:
        case rt.Closure_TAG.value: {
          if (rt.compareIds(rt.Function_getId(a), rt.Function_getId(b)) !== 0) return false;
          let aBound = aTag === rt.Closure_TAG.value ? rt.Closure_getBound(a) : null;
          let bBound = bTag === rt.Closure_TAG.value ? rt.Closure_getBound(b) : null;
          return argsEq(rt, aBound, bBound);
        }
        case rt.Continuation_TAG.value:
          return argsEq(rt, rt.Continuation_getData(a), rt.Continuation_getData(b));
        case rt.Quote_TAG.value:
          return eq(rt, rt.Quote_getValue(a), rt.Quote_getValue(b));
        case rt.Foreign_TAG.value: {
          let valueA = rt.Foreign_getValue(a);
          let valueB = rt.Foreign_getValue(b);
          if (valueA === valueB) return true;
          if (valueA instanceof rt.js.JSValue && valueB instanceof rt.js.JSValue) {
            return valueA.get() === valueB.get();
          }
          return false;
        }
        case rt.Boolean_TAG.value:
          return rt.Boolean_getValue(a) === rt.Boolean_getValue(b);
        case rt.Array_TAG.value: {
          let aVals = rt.Array_getContents(a);
          let bVals = rt.Array_getContents(b);
          if (rt.Args_length(aVals) !== rt.Args_length(bVals)) return false;
          for (let i = 0, len = rt.Args_length(aVals); i < len; i++) {
            if (!eq(rt, rt.Args_at(aVals, i), rt.Args_at(bVals, i))) return false;
          }
          return true;
        }
        case rt.ByteArray_TAG.value: {
          let aView = rt.ByteArray_getContents(a);
          let bView = rt.ByteArray_getContents(b);
          if (aView.byteLength !== bView.byteLength) return false;
          let aBytes = new Uint8Array(aView.buffer, aView.byteOffset, aView.byteLength);
          let bBytes = new Uint8Array(bView.buffer, bView.byteOffset, bView.byteLength);
          for (let i = 0, len = aBytes.byteLength; i < len; i++) {
            if (aBytes[i] !== bBytes[i]) return false;
          }
          return true;
        }
        case rt.Bytes_TAG.value: {
          if (rt.Bytes_getValue(a).size !== rt.Bytes_getValue(b).size) return false;
          let aBytes = rt.Bytes_getValue(a).toUint8Array();
          let bBytes = rt.Bytes_getValue(b).toUint8Array();
          for (let i = 0, len = aBytes.byteLength; i < len; i++) {
            if (aBytes[i] !== bBytes[i]) return false;
          }
          return true;
        }
        case rt.List_TAG.value: {
          let aLen = rt.List_size(a);
          if (aLen !== rt.List_size(b)) return false;
          for (let i = 0; i < aLen; i++) {
            if (!eq(rt, rt.List_at(a, i), rt.List_at(b, i))) return false;
          }
          return true;
        }
        default:
          return false;
      }
    }
    return (rt, a, b) => rt.Boolean(Number(eq(rt, a, b)));
  })()
  """

internal.javascript.supportJS.listToArrayJS : Text
internal.javascript.supportJS.listToArrayJS =
  """
  (rt, list) => {
    let len = rt.List_size(list);
    let out = Array(len);
    for (let i = 0; i < len; i++) {
      out[i] = rt.List_at(list, i);
    }
    return out;
  }
  """

internal.javascript.supportJS.listFromArrayJS : Text
internal.javascript.supportJS.listFromArrayJS =
  """
  (rt, array) => {
    let len = array.length;
    if (len === 0) return rt.seqEmpty();
    let values = rt.Args_of(array[0], len);
    for (let i = 1; i < len; i++) {
      rt.Args_setAt(values, i, array[i]);
    }
    return rt.buildSeq(values);
  }
  """

internal.javascript.supportJS.buildSeqJS : Text
internal.javascript.supportJS.buildSeqJS =
  "(rt, values) => rt.buildSeq(values)"

internal.javascript.supportJS : [(Text, Text)]
internal.javascript.supportJS =
  [ ("Sequence", supportJS.sequenceJS)
  , ("listToArray", supportJS.listToArrayJS)
  , ("listFromArray", supportJS.listFromArrayJS)
  , ("Pattern", supportJS.patternJS)
  , ("Bytes", supportJS.bytesJS)
  , ("UnisonError", supportJS.unisonErrorJS)
  , ("UnisonValue", supportJS.unisonValueJS)
  , ("JSValue", supportJS.jsValueJS)
  , ("buildSeq", supportJS.buildSeqJS)
  , ("b32id", supportJS.b32idJS)
  , ("lookupName", supportJS.lookupNameJS)
  , ("escapeRegExp", supportJS.escapeRegExpJS)
  , ("base16", supportJS.base16JS)
  , ("base32", supportJS.base32JS)
  , ("base64", supportJS.base64JS)
  , ("valueTagsCompatible", supportJS.valueTagsCompatibleJS)
  , ("toDebugString", supportJS.toDebugStringJS)
  , ("raiseArrayFailure", supportJS.raiseGenericFailureJS)
  , ("log", supportJS.logJS)
  , ("panic", supportJS.panicJS)
  , ("populateCode", supportJS.populateCodeJS)
  , ("buildImports", supportJS.buildImportsJS)
  , ("compileOptions", supportJS.compileOptionsJS)
  ]

internal.javascript.supportJS.toDebugStringJS : Text
internal.javascript.supportJS.toDebugStringJS =
  """
  (() => {
    function tupleToArray(rt, tuple) {
      let items = [];
      let current = tuple;
      while (rt.Value_getTag(current) === rt.Data_TAG.value &&
              rt.Data_getType(current) === rt.Tuple_ID.value) {
        let args = rt.Data_getArgs(current);
        items.push(rt.Args_at(args, 0));
        current = rt.Args_at(args, 1);
      }
      if (rt.Data_getType(current) === rt.Unit_ID.value) {
        return items;
      }
      return null;
    }
    function argsToString(rt, args) {
      let members = [];
      for (let i = 0, len = rt.Args_length(args); i < len; i++) {
        members.push(` ${toDebugString(rt, rt.Args_at(args, i), { parenthesize: true })}`);
      }
      return members.join('');
    }
    function toDebugString(rt, value, { parenthesize = false } = {}) {
      let addParens = (str) => parenthesize ? `(${str})` : str;
      if (!rt.Value_detect(value)) {
        return value && (Object.getPrototypeOf(value) === Object.prototype || Array.isArray(value))
          ? JSON.stringify(value)
          : String(value);
      }
      switch (rt.Value_getTag(value)) {
        case rt.Text_TAG.value:
          return JSON.stringify(rt.Text_getValue(value));
        case rt.Char_TAG.value:
          return `?${rt.Char_getValue(value)}`;
        case rt.Nat_TAG.value:
          return `${BigInt.asUintN(64, rt.Nat_getValue(value))}`;
        case rt.Int_TAG.value: {
          let int = BigInt.asIntN(64, rt.Int_getValue(value));
          return `${int < 0 ? '' : '+'}${int}`;
        }
        case rt.Float_TAG.value: {
          let float = rt.Float_getValue(value);
          return `${float % 1 ? float : float.toFixed(1)}`;
        }
        case rt.Boolean_TAG.value:
          return `${Boolean(rt.Boolean_getValue(value))}`;
        case rt.TypeLink_TAG.value: {
          let id = rt.TypeLink_getId(value);
          let name = rt.js.lookupName(rt, id);
          return addParens(`typeLink ${name}`);
        }
        case rt.TermLink_TAG.value: {
          let id = rt.TermLink_getId(value);
          let ctor = rt.TermLink_getConstructor(value);
          let name = rt.js.lookupName(rt, id, ctor);
          return addParens(`termLink ${name}`);
        }
        case rt.List_TAG.value:
          return `[${rt.js.listToArray(rt, value).map(el => rt.js.toDebugString(rt, el)).join(', ')}]`;
        case rt.Request_TAG.value:
          value = rt.Request_getData(value);
        case rt.Data_TAG.value: {
          switch (rt.Data_getType(value)) {
            case rt.Unit_ID.value:
              return '()';
            case rt.Tuple_ID.value: {
              let items = tupleToArray(rt, value);
              if (!items) break;
              return `(${items.map(el => rt.js.toDebugString(rt, el)).join(', ')})`;
            }
          }
          let type = rt.Data_getType(value);
          let ctor = rt.Data_getConstructor(value);
          let tag = rt.code.names[type]?.ctors[ctor] ?? rt.js.toDebugString(rt, rt.TermLink(type, ctor)).replace('termLink ', '');
          let args = argsToString(rt, rt.Data_getArgs(value));
          return args.length ? addParens(`${tag}${args}`) : tag;
        }
        case rt.Function_TAG.value:
          return rt.js.lookupName(rt, rt.Function_getId(value));
        case rt.Closure_TAG.value: {
          let id = rt.js.lookupName(rt, rt.Closure_getId(value));
          let args = argsToString(rt, rt.Closure_getBound(value));
          return args.length ? addParens(`${id}${args}`) : id;
        }
        case rt.Bytes_TAG.value:
          return `0xs${rt.js.base16.encode(rt.Bytes_getValue(value).toUint8Array())}`;
        case rt.Quote_TAG.value:
          return '(quoted value)';
        case rt.Foreign_TAG.value: {
          let inner = rt.Foreign_getValue(value);
          if (inner instanceof js.JSValue) {
            return addParens(`JSValue ${toDebugString(rt, inner.get(), { parenthesize: true })}`);
          }
          return toDebugString(rt, inner);
        }
      }
      return `(complex Unison value)`;
    }
    return (rt, value) => toDebugString(rt, value);
  })()
  """

internal.javascript.devtoolsJS : Text
internal.javascript.devtoolsJS =
  """
  {
    function commaSepValues(rt, arr, config) {
      return arr.flatMap((el, index) => {
        let child = [formatValue(rt, el, { ...config, parenthesize: false, depth: config.depth + 1 })];
        if (index < arr.length - 1) {
          child.push(span(styles.constructor, ', '));
        }
        return child;
      });
    }

    function argsToArray(rt, args) {
      let len = rt.Args_length(args);
      let items = Array(len);
      for (let i = 0; i < len; i++) {
        items[i] = rt.Args_at(args, i);
      }
      return items;
    }

    function argsToLog(rt, args, config) {
      return argsToArray(rt, args).flatMap(arg =>
        [' ', formatValue(rt, arg, { ...config, parenthesize: true, depth: config.depth + 1 })]
      );
    }

    function tupleToArray(rt, tuple) {
      let items = [];
      let current = tuple;
      while (rt.Value_getTag(current) === rt.Data_TAG.value &&
             rt.Data_getType(current) === rt.Tuple_ID.value) {
        let args = rt.Data_getArgs(current);
        items.push(rt.Args_at(args, 0));
        current = rt.Args_at(args, 1);
      }
      if (rt.Data_getType(current) === rt.Unit_ID.value) {
        return items;
      }
      return null;
    }

    let styles = {
      root: 'padding-top: 4px;',
      base: 'color: #18181c;',
      keyword: 'color: #ff6c78;',
      text: 'color: #27ae60;',
      term: 'color: #734da3;',
      termNamespace: 'color: #9a76c8;',
      constructor: 'color: #225ebe;',
      constructorNamespace: 'color: #5695f4;',
      type: 'color: #225ebe;',
      typeNamespace: 'color: #5695f4;',
      subtle: 'color: #818286;',
    };

    let span = (style, ...children) => ['span', { style }, ...children];
    let object = (obj, config) => ['object', { object: obj, config }];
    let name = (nsStyles, nameStyles) => (name) => {
      if (name.startsWith('#')) {
        return span(nameStyles, name);
      }
      let dot = name.lastIndexOf('.');
      if (dot === -1) {
        return span(nameStyles, name);
      }
      return span(
        styles.base,
        span(nsStyles, name.slice(0, dot + 1)),
        span(nameStyles, name.slice(dot + 1))
      );
    };
    let term = name(styles.termNamespace, styles.term);
    let type = name(styles.typeNamespace, styles.type);
    let constructor = name(styles.constructorNamespace, styles.constructor);

    let brand = Symbol.for('unison.inspectorData');

    function truncate(text, size = 100) {
      if (text.length > size) {
        return ['span', { title: text }, text.slice(0, size / 2) + '…' + text.slice(-size / 2)];
      }
      return text;
    }

    function formatTextualValue(rt, value, config) {
      let text = rt.js.toDebugString(rt, value);
      if (config?.depth > 0) {
        text = truncate(text, 100);
      }
      return span(styles.text, text);
    }

    function formatValue(rt, value, config = { depth: 0 }) {
      let parenthesize = result => config.parenthesize ? span(styles.base, span(styles.subtle, '('), result, span(styles.subtle, ')')) : result;
      let valueTag = rt.Value_getTag(value);
      switch (valueTag) {
        case rt.Text_TAG.value:
        case rt.Char_TAG.value:
          return formatTextualValue(rt, value, config);
        case rt.Nat_TAG.value:
        case rt.Int_TAG.value:
        case rt.Float_TAG.value:
          return span(styles.constructor, rt.js.toDebugString(rt, value));
        case rt.Boolean_TAG.value:
          return span(styles.constructor, rt.js.toDebugString(rt, value));
        case rt.List_TAG.value:
          return span(styles.base, span(styles.constructor, '['), ...commaSepValues(rt, rt.js.listToArray(rt, value), config), span(styles.constructor, ']'));
        case rt.Bytes_TAG.value: {
          let text = rt.js.toDebugString(rt, value).replace(/^0xs/, '');
          return span(styles.base, span(styles.text, '0xs'), span(styles.subtle, text));
        }
        case rt.TypeLink_TAG.value: {
          let typeName = rt.js.toDebugString(rt, value).replace('typeLink ', '');
          return parenthesize(span(styles.base, span(styles.keyword, 'typeLink '), type(typeName)));
        }
        case rt.TermLink_TAG.value: {
          let termName = rt.js.toDebugString(rt, value).replace('termLink ', '');
          return parenthesize(span(styles.base, span(styles.keyword, 'termLink '), term(termName)));
        }
        case rt.Function_TAG.value:
        case rt.Closure_TAG.value: {
          let id = rt.Function_getId(value);
          let name = rt.js.lookupName(rt, id);
          let args = valueTag === rt.Closure_TAG.value ? argsToLog(rt, rt.Closure_getBound(value), config) : [];
          let result = span(styles.base, term(name), ...(config.depth > 0 && args.length > 0 ? [span(styles.subtle, ' …')] : args));
          return args.length ? parenthesize(result) : result;
        }
        case rt.Request_TAG.value:
          value = rt.Request_getData(value);
        case rt.Data_TAG.value: {
          switch (rt.Data_getType(value)) {
            case rt.Unit_ID.value:
              return constructor('()');
            case rt.Tuple_ID.value: {
              let items = tupleToArray(rt, value);
              if (items) return span(styles.base, span(styles.constructor, '('), ...commaSepValues(rt, items, config), span(styles.constructor, ')'));
              break;
            }
            default: {
              let type = rt.Data_getType(value);
              let ctor = rt.Data_getConstructor(value);
              let tag = rt.code.names[type]?.ctors[ctor] ?? rt.js.toDebugString(rt, rt.TermLink(type, ctor)).replace('termLink ', '');
              let args = rt.Data_getArgs(value);
              let argsLen = rt.Args_length(args);
              let formattedArgs =
                config.depth > 0 && argsLen > 1
                  ? [span(styles.subtle, ' …')]
                  : argsToLog(rt, args, config);
              let result = span(styles.base, constructor(tag), ...formattedArgs);
              return formattedArgs.length ? parenthesize(result) : result;
            }
          }
        }
      }
      return ['span', { style: 'color: #333' }, rt.js.toDebugString(rt, value)];
    }

    function hasChildren(rt, value) {
      if (rt.Value_detect(value)) {
        switch (rt.Value_getTag(value)) {
          case rt.Closure_TAG.value:
            return rt.Args_length(rt.Closure_getBound(value)) > 0;
          case rt.List_TAG.value:
            return rt.List_size(value) > 0;
          case rt.Data_TAG.value: {
            let args = rt.Data_getArgs(value);
            let argsLen = rt.Args_length(args);
            return argsLen === 1
              ? hasChildren(rt, rt.Args_at(args, 0))
              : argsLen > 1;
          }
        }
      }
      return false;
    }

    function getChildren(rt, value) {
      switch (rt.Value_getTag(value)) {
        case rt.Closure_TAG.value:
          return argsToArray(rt, rt.Closure_getBound(value));
        case rt.List_TAG.value:
          return rt.js.listToArray(rt, value);
        case rt.Data_TAG.value: {
          if (rt.Data_getType(value) === rt.Tuple_ID.value) {
            let items = tupleToArray(rt, value);
            if (items?.length) return items;
          } else {
            let args = rt.Data_getArgs(value);
            let argsLen = rt.Args_length(args);
            if (argsLen === 1) {
              return getChildren(rt, rt.Args_at(args, 0));
            } else if (argsLen > 1) {
              let pairs = Array(argsLen);
              for (let i = 0; i < argsLen; i++) {
                pairs[i] = rt.Args_at(args, i);
              }
              return pairs;
            }
          }
        }
      }
    }

    function formatChildren(rt, children) {
      return ['div', ...children.map(child => [
        'div',
        { style: `padding-left: ${hasChildren(rt, child) ? 12 : 30}px` },
        ['object', { object: new rt.js.UnisonValue(rt, child) }]
      ])];
    }

    globalThis.devtoolsFormatters ??= [];
    globalThis.devtoolsFormatters.push({
      header: (obj, config) => {
        if (obj && brand in obj) {
          let { value, rt } = obj[brand];
          let formatted = formatValue(rt, value, config);
          return config?.depth > 0 ? formatted : span(styles.root, formatted);
        }
        return null;
      },
      hasBody: ({ [brand]: { rt, value } }, config) => {
        return !config?.depth && !config?.pairMember && hasChildren(rt, value);
      },
      body: ({ [brand]: { rt, value } }) => {
        return formatChildren(rt, getChildren(rt, value));
      },
    });
  }
  """

internal.runtime.replacements.unison_base.Bytes_fromList : Replacement
internal.runtime.replacements.unison_base.Bytes_fromList =
  src =
    """
    (rt, list) => {
      let len = rt.List_size(list);
      let bytes = new Uint8Array(len);
      for (let i = 0; i < len; i++) {
        bytes[i] = Number(rt.Nat_getValue(rt.List_at(list, i)));
      }
      return rt.Bytes(rt.js.Bytes.one(new DataView(bytes.buffer)));
    }
    """
  jsFunction 1 src

internal.runtime.replacements.unison_base.Bytes_toList : Replacement
internal.runtime.replacements.unison_base.Bytes_toList =
  src =
    """
    (rt, bytes) => {
      let array = Array.from(rt.Bytes_getValue(bytes).toUint8Array(), byte => rt.Nat(BigInt(byte)));
      return rt.js.listFromArray(rt, array);
    }
    """
  jsFunction 1 src

internal.runtime.replacements.unison_base.Char_Class_anyOf : Replacement
internal.runtime.replacements.unison_base.Char_Class_anyOf =
  src =
    """
    (rt, charList) => {
      let chars = rt.js.listToArray(rt, charList).map(char => rt.Char_getValue(char));
      return rt.Foreign(new RegExp(`[${rt.js.escapeRegExp(chars.join(''))}]`, 'v'));
    }
    """
  jsFunction 1 src

internal.runtime.replacements.unison_base.Pattern_join : Replacement
internal.runtime.replacements.unison_base.Pattern_join =
  src =
    """
    (rt, patternList) => {
      let patterns = rt.js.listToArray(rt, patternList).map(pattern => rt.Foreign_getValue(pattern));
      return rt.Foreign(rt.js.Pattern.join(patterns));
    }
    """
  jsFunction 1 src

internal.runtime.replacements.unison_base.Pattern_run : Replacement
internal.runtime.replacements.unison_base.Pattern_run =
  src =
    """
    (rt, pattern, text) => {
      let string = rt.Text_getValue(text);
      let result = rt.Foreign_getValue(pattern).run(string, 0);
      if (result) {
        let captures = rt.js.listFromArray(rt, result.captures.map(s => rt.Text(s)));
        let rest = rt.Text(string.slice(result.index));
        return rt.Optional_Some(rt.Tuple_Cons(captures, rt.Tuple_Cons(rest, rt.Unit())));
      } else {
        return rt.Optional_None();
      }
    }
    """
  jsFunction 2 src

internal.runtime.replacements.unison_base.Text_fromCharList : Replacement
internal.runtime.replacements.unison_base.Text_fromCharList =
  src =
    """
    (rt, chars) => {
      let len = rt.List_size(chars);
      let out = Array(len);
      for (let i = 0; i < len; i++) {
        out[i] = rt.Char_getValue(rt.List_at(chars, i));
      }
      return rt.Text(out.join(''));
    }
    """
  jsFunction 1 src

internal.runtime.replacements.unison_base.Text_toCharList : Replacement
internal.runtime.replacements.unison_base.Text_toCharList =
  src =
    """
    (rt, text) => {
      let chars = rt.Text_getValue(text).split('').map(c => rt.Char(c));
      return rt.js.listFromArray(rt, chars);
    }
    """
  jsFunction 1 src

internal.runtime.replacements.warp_js.JSValue_array : Replacement
internal.runtime.replacements.warp_js.JSValue_array =
  src =
    """
    (rt, list) => {
      let len = rt.List_size(list);
      let out = Array(len);
      for (let i = 0; i < len; i++) {
        out[i] = rt.Foreign_getValue(rt.List_at(list, i)).get();
      }
      return rt.Foreign(rt.js.JSValue.unanchored(out));
    }
    """
  jsFunction 1 src

internal.runtime.replacements.warp_js.JSValue_asList : Replacement
internal.runtime.replacements.warp_js.JSValue_asList =
  src =
    """
    (rt, ref) => {
      let value = rt.Foreign_getValue(ref).get();
      if (Array.isArray(value)) {
        let jsValues = value.map(item => rt.Foreign(rt.js.JSValue.unanchored(item)));
        return rt.Optional_Some(rt.js.listFromArray(rt, jsValues));
      } else {
        return rt.Optional_None();
      }
    }
    """
  jsFunction 1 src

internal.runtime.replacements.warp_js.JSValue_call : Replacement
internal.runtime.replacements.warp_js.JSValue_call =
  src =
    """
    (rt, argsValue, refValue) => {
      let ref = rt.Foreign_getValue(refValue);
      if (typeof ref.get() === 'function') {
        let len = rt.List_size(argsValue);
        let args = Array(len);
        for (let i = 0; i < len; i++) {
          args[i] = rt.Foreign_getValue(rt.List_at(argsValue, i)).get();
        }
        return rt.Optional_Some(rt.Foreign(rt.js.JSValue.unanchored(ref.call(args))));
      } else {
        return rt.Optional_None();
      }
    }
    """
  jsFunction 2 src

internal.runtime.replacements.warp_js.JSValue_function : Replacement
internal.runtime.replacements.warp_js.JSValue_function =
  src =
    """
    (rt, func) => {
      return rt.Foreign(rt.js.JSValue.unanchored((...jsArgs) => {
        let argsRefs = jsArgs.map(arg => rt.Foreign(rt.js.JSValue.unanchored(arg)));
        let argsList = rt.js.listFromArray(rt, argsRefs);
        let argsValue = rt.Args_of(argsList, 1);
        let jsValue = rt.Foreign_getValue(rt.callDirect(argsValue, func));
        return jsValue.get();
      }));
    }
    """
  jsFunction 1 src

internal.runtime.replacements.warp_js.JSValue_new : Replacement
internal.runtime.replacements.warp_js.JSValue_new =
  src =
    """
    (rt, argsValue, refValue) => {
      let value = rt.Foreign_getValue(refValue).get();
      if (typeof value === 'function') {
        let len = rt.List_size(argsValue);
        let args = Array(len);
        for (let i = 0; i < len; i++) {
          args[i] = rt.Foreign_getValue(rt.List_at(argsValue, i)).get();
        }
        return rt.Optional_Some(rt.Foreign(rt.js.JSValue.unanchored(new value(...args))));
      } else {
        return rt.Optional_None();
      }
    }
    """
  jsFunction 2 src

internal.runtime.replacements.warp_js.JSValue_object : Replacement
internal.runtime.replacements.warp_js.JSValue_object =
  src =
    """
    (rt, props) => {
      let obj = {};
      let len = rt.List_size(props);
      for (let i = 0; i < len; i++) {
        let pair = rt.List_at(props, i);
        let headArgs = rt.Data_getArgs(pair);
        let tailArgs = rt.Data_getArgs(rt.Args_at(headArgs, 1));
        let key = rt.Text_getValue(rt.Args_at(headArgs, 0));
        let value = rt.Foreign_getValue(rt.Args_at(tailArgs, 0)).get();
        obj[key] = value;
      }
      return rt.Foreign(rt.js.JSValue.unanchored(obj));
    }
    """
  jsFunction 1 src

internal.runtime.replacements.unison_base.Value_load : Replacement
internal.runtime.replacements.unison_base.Value_load =
  src =
    """
    (() => {
      function hydrateId(rt, ref) {
        if (rt.Data_getConstructor(ref) === rt.refl_Reference_Builtin_IDX.value) {
          return `##${rt.Text_getValue(rt.Args_at(rt.Data_getArgs(ref), 0))}`;
        } else {
          let idArgs = rt.Data_getArgs(rt.Args_at(rt.Data_getArgs(ref), 0));
          let dataView = rt.ByteArray_getContents(rt.Args_at(idArgs, 0));
          let ctor = Number(rt.Nat_getValue(rt.Args_at(idArgs, 1)));
          return [...new Uint8Array(dataView.buffer)].map(b => String.fromCharCode(b)).join('') + String.fromCharCode(ctor);
        }
      }
      function hydrateArgs(rt, missing, list) {
        let values = rt.js.listToArray(rt, list);
        let args = rt.Args_of(rt.Unit(), values.length);
        for (let i = 0, len = values.length; i < len; i++) {
          rt.Args_setAt(args, i, hydrate(rt, missing, values[i]));
        }
        return args;
      }
      function hydrate(rt, missing, value) {
        switch (rt.Data_getConstructor(value)) {
          case rt.refl_Value_Data_IDX.value: {
            let args = rt.Data_getArgs(value);
            let id = hydrateId(rt, rt.Args_at(args, 0));
            let ctor = Number(rt.Nat_getValue(rt.Args_at(args, 1)));
            if (id === '##Boolean') {
              return rt.Boolean(ctor);
            }
            return rt.Data(id, ctor, hydrateArgs(rt, missing, rt.Args_at(args, 2)));
          }
          case rt.refl_Value_Partial_IDX.value: {
            let args = rt.Data_getArgs(value);
            let groupRefArgs = rt.Data_getArgs(rt.Args_at(args, 0));
            if (rt.Nat_getValue(rt.Args_at(groupRefArgs, 1)) !== 0n) {
              return rt.js.panic(rt,
                "bug",
                rt.Tuple_Cons(
                  rt.Text("Encountered non-zero term ref"),
                  rt.Tuple_Cons(value, rt.Unit()),
                ),
              );
            }
            let id = hydrateId(rt, rt.Args_at(groupRefArgs, 0));
            let fun = rt.code.terms[id];
            if (!fun) {
              missing.add(id);
              return rt.Unit();
            }
            return rt.Closure(
              rt.Function_getId(fun),
              rt.Function_getArity(fun),
              rt.Function_getImpl(fun),
              hydrateArgs(rt, missing, rt.Args_at(args, 1)),
            );
          }
          case rt.refl_Value_VLit_IDX.value: {
            let inner = rt.Args_at(rt.Data_getArgs(value), 0);
            let lit = rt.Args_at(rt.Data_getArgs(inner), 0);
            switch (rt.Data_getConstructor(inner)) {
              case rt.refl_VLit_VT_IDX.value:
                return lit;
              case rt.refl_VLit_VCH_IDX.value:
                return lit;
              case rt.refl_VLit_VP_IDX.value:
                return lit;
              case rt.refl_VLit_VN_IDX.value:
                return rt.Int(-rt.Nat_getValue(lit));
              case rt.refl_VLit_VF_IDX.value:
                return lit;
              case rt.refl_VLit_VLY_IDX.value:
                return rt.TypeLink(hydrateId(rt, lit));
              case rt.refl_VLit_VLM_IDX.value: {
                let referentArgs = rt.Data_getArgs(lit);
                let ref = hydrateId(rt, rt.Args_at(referentArgs, 0));
                let ctor =
                  rt.Data_getConstructor(lit) === rt.refl_Referent_Ref_IDX.value
                    ? -1
                    : Number(rt.Nat_getValue(rt.Args_at(referentArgs, 1)));
                return rt.TermLink(ref, ctor);
              }
              case rt.refl_VLit_VB_IDX.value:
                return lit;
              case rt.refl_VLit_VQ_IDX.value:
                return rt.Quote(lit);
              case rt.refl_VLit_VC_IDX.value:
                return rt.Code(lit);
              case rt.refl_VLit_VLS_IDX.value: {
                let values = rt.js.listToArray(rt, lit).map(el => hydrate(rt, missing, el));
                return rt.js.listFromArray(rt, values);
              }
              case rt.refl_VLit_VA_IDX.value: {
                let values = rt.Array_getContents(lit);
                let hydrated = rt.Args_of(rt.Unit(), rt.Args_length(values));
                for (let i = 0, len = rt.Args_length(values); i < len; i++) {
                  rt.Args_setAt(hydrated, i, hydrate(rt, missing, rt.Args_at(values, i)));
                }
                return rt.Array(0, hydrated);
              }
              case rt.refl_VLit_VBA_IDX.value: {
                let byteArrayArgs = rt.Data_getArgs(lit);
                let offset = Number(rt.Nat_getValue(rt.Args_at(byteArrayArgs, 0)));
                let length = Number(rt.Nat_getValue(rt.Args_at(byteArrayArgs, 1)));
                let view = rt.ByteArray_getContents(rt.Args_at(byteArrayArgs, 2));
                return rt.ByteArray(0, new DataView(view.buffer, view.byteOffset + offset, length));
              }
            }
          }
        }
        return rt.js.panic(rt,
          "builtin.bug",
          rt.Tuple_Cons(rt.Text("Unknown value type"), rt.Tuple_Cons(value, rt.Unit())),
        );
      }
      return (rt, value) => {
        let missing = new Set();
        let result = hydrate(rt, missing, rt.Quote_getValue(value));
        if (missing.size > 0) {
          let links = [...missing].map(id => rt.TermLink(id, -1));
          return rt.Either_Left(rt.js.listFromArray(rt, links));
        } else {
          return rt.Either_Right(result);
        }
      };
    })()
    """
  jsFunction 1 src

internal.runtime.replacements.unison_base.Value_value : Replacement
internal.runtime.replacements.unison_base.Value_value =
  src =
    """
    (() => {
      function dehydrateId(rt, id) {
        if (id.startsWith('##')) {
          return rt.refl_Reference_Builtin(rt.Text(id.slice(2)));
        } else {
          return rt.refl_Reference_Derived(
            rt.refl_Id_Id(
              rt.ByteArray(0, new DataView(Uint8Array.from(id.slice(0, -1).split('').map(c => c.charCodeAt(0))).buffer)),
              rt.Nat(BigInt(id.charCodeAt(id.length - 1))),
            )
          );
        }
      }
      function dehydrateArgs(rt, args) {
        let values = [];
        for (let i = 0, len = rt.Args_length(args); i < len; i++) {
          values.push(dehydrate(rt, rt.Args_at(args, i)));
        }
        return rt.js.listFromArray(rt, values);
      }
      function dehydrate(rt, value) {
        switch (rt.Value_getTag(value)) {
          case rt.Text_TAG.value:
            return rt.refl_Value_VLit(rt.refl_VLit_VT(value));
          case rt.Char_TAG.value:
            return rt.refl_Value_VLit(rt.refl_VLit_VCH(value));
          case rt.Nat_TAG.value:
            return rt.refl_Value_VLit(rt.refl_VLit_VP(value));
          case rt.Int_TAG.value: {
            let n = rt.Int_getValue(value);
            if (n >= 0n) {
              return rt.refl_Value_VLit(rt.refl_VLit_VP(rt.Nat(n)));
            } else {
              return rt.refl_Value_VLit(rt.refl_VLit_VN(rt.Nat(-n)));
            }
          }
          case rt.Float_TAG.value:
            return rt.refl_Value_VLit(rt.refl_VLit_VF(value));
          case rt.Boolean_TAG.value:
            return rt.refl_Value_Data(
              rt.refl_Reference_Builtin(rt.Text("Boolean")),
              rt.Nat(BigInt(rt.Boolean_getValue(value))),
              rt.seqEmpty(),
            );
          case rt.TypeLink_TAG.value:
            return rt.refl_Value_VLit(
              rt.refl_VLit_VLY(dehydrateId(rt, rt.TypeLink_getId(value)))
            );
          case rt.TermLink_TAG.value: {
            let ctor = rt.TermLink_getConstructor(value);
            let ref = dehydrateId(rt, rt.TermLink_getId(value));
            return rt.refl_Value_VLit(
              rt.refl_VLit_VLM(
                ctor === -1
                  ? rt.refl_Referent_Ref(ref)
                  : rt.refl_Referent_Con(ref, rt.Nat(BigInt(ctor)))
              )
            );
          }
          case rt.List_TAG.value: {
            let values = rt.js.listToArray(rt, value).map(el => dehydrate(rt, el));
            return rt.refl_Value_VLit(rt.refl_VLit_VLS(rt.js.listFromArray(rt, values)));
          }
          case rt.Data_TAG.value:
            return rt.refl_Value_Data(
              dehydrateId(rt, rt.Data_getType(value)),
              rt.Nat(BigInt(rt.Data_getConstructor(value))),
              dehydrateArgs(rt, rt.Data_getArgs(value)),
            );
          case rt.Function_TAG.value:
          case rt.Closure_TAG.value: {
            let id = dehydrateId(rt, rt.Function_getId(value));
            let bound = rt.Value_getTag(value) === rt.Closure_TAG.value
              ? dehydrateArgs(rt, rt.Closure_getBound(value))
              : rt.seqEmpty();
            return rt.refl_Value_Partial(
              rt.refl_GroupRef_GR(id, rt.Nat(BigInt(0))),
              bound,
            );
          }
          case rt.Bytes_TAG.value:
            return rt.refl_Value_VLit(rt.refl_VLit_VB(value));
          case rt.Request_TAG.value:
            return rt.js.panic(rt, "builtin.bug", rt.Text("Cannot serialize an ability request"));
          case rt.Quote_TAG.value:
            return rt.refl_Value_VLit(rt.refl_VLit_VQ(rt.Quote_getValue(value)));
          case rt.Code_TAG.value:
            return rt.refl_Value_VLit(rt.refl_VLit_VC(rt.Code_getValue(value)));
          case rt.Array_TAG.value: {
            let contents = rt.Array_getContents(value);
            let dehydrated = rt.Args_of(rt.Unit(), rt.Args_length(contents));
            for (let i = 0, len = rt.Args_length(contents); i < len; i++) {
              rt.Args_setAt(dehydrated, i, dehydrate(rt, rt.Args_at(contents, i)));
            }
            return rt.refl_Value_VLit(rt.refl_VLit_VA(rt.Array(0, dehydrated)));
          }
          case rt.ByteArray_TAG.value: {
            let view = rt.ByteArray_getContents(value);
            let byteArray = rt.data_ByteArray_BArr(
              rt.Nat(BigInt(view.byteOffset)),
              rt.Nat(BigInt(view.byteLength)),
              rt.ByteArray(0, view),
            );
            return rt.refl_Value_VLit(rt.refl_VLit_VBA(byteArray));
          }
          case rt.Foreign_TAG.value:
        }
        return rt.js.panic(rt,
          "builtin.bug",
          rt.Tuple_Cons(rt.Text("Unserializable value"), rt.Tuple_Cons(value, rt.Unit())),
        );
      }
      return (rt, value) => rt.Quote(dehydrate(rt, value));
    })()
    """
  jsFunction 1 src

{{
Exercises Wasm GC `List` builtins across leaf (`<= 32`) and balanced-tree (`> 32`) sizes, including `buildSeq` literals, `cons`, `snoc`, `append`, `take`, `drop`, `at`, `viewl`, `viewr`, equality, and `Universal.compare`.
}}
tests.builtins.list : WasmTest
tests.builtins.list =
  wasmTest "List builtins (Wasm GC Seq)" do
    use List ++ +: :+
    use Nat +
    use test ensure ensureEqual
    lit35 =
      [ 0, 1, 2, 3, 4, 5, 6, 7, 8, 9
      , 10, 11, 12, 13, 14, 15, 16, 17, 18, 19
      , 20, 21, 22, 23, 24, 25, 26, 27, 28, 29
      , 30, 31, 32, 33, 34
      ]
    ensureEqual (List.size lit35) 35
    ensureEqual (List.at 0 lit35) (Some 0)
    ensureEqual (List.at 31 lit35) (Some 31)
    ensureEqual (List.at 32 lit35) (Some 32)
    ensureEqual (List.at 34 lit35) (Some 34)
    ensureEqual (List.at 35 lit35) None
    snocBuilt = Nat.range 0 260
    ensureEqual (List.size snocBuilt) 260
    ensureEqual (List.at 0 snocBuilt) (Some 0)
    ensureEqual (List.at 31 snocBuilt) (Some 31)
    ensureEqual (List.at 32 snocBuilt) (Some 32)
    ensureEqual (List.at 129 snocBuilt) (Some 129)
    ensureEqual (List.at 259 snocBuilt) (Some 259)
    ensureEqual (List.take 35 snocBuilt) lit35
    consBuilt = List.foldRight (el acc -> el +: acc) [] snocBuilt
    ensureEqual consBuilt snocBuilt
    splitA = List.take 97 snocBuilt
    splitB = List.drop 97 snocBuilt
    ensureEqual (List.size splitA) 97
    ensureEqual (List.size splitB) 163
    ensureEqual (splitA ++ splitB) snocBuilt
    ensureEqual (List.take 0 snocBuilt) []
    ensureEqual (List.drop 260 snocBuilt) []
    ensureEqual (List.take 999 snocBuilt) snocBuilt
    ensureEqual (List.drop 0 snocBuilt) snocBuilt
    match consBuilt with
      hd +: tl ->
        ensureEqual hd 0
        ensureEqual (List.size tl) 259
        ensureEqual (List.at 0 tl) (Some 1)
        ensureEqual (List.at 258 tl) (Some 259)
      [] -> ensure false
    match snocBuilt with
      init :+ lastEl ->
        ensureEqual lastEl 259
        ensureEqual (List.size init) 259
        ensureEqual (List.at 0 init) (Some 0)
        ensureEqual (List.at 258 init) (Some 258)
      [] -> ensure false
    ensure (Universal.compare [1, 2] [1, 2, 3] === -1)
    ensure (Universal.compare [1, 2, 3] [1, 2] === +1)
    ensure (Universal.compare snocBuilt (snocBuilt :+ 260) === -1)
    ensure (Any 1 !== Any "one")
    ensure (Universal.compare (Any 1) (Any "one") !== +0)

tests.builtins : [WasmTest]
tests.builtins =
  List.map
    (WasmTest.group "builtins")
    [ universal
    , builtins.list
    , builtins.nat
    , builtins.int
    , builtins.float
    , builtins.bytes
    , builtins.char
    , builtins.text
    , builtins.pattern
    , charClass
    , textPatterns
    , immutableByteArray
    , mutableByteArray
    , immutableArray
    , mutableArray
    ]
'## | save --force ($dest | path join scratch-warp--perf-list.u)
}
