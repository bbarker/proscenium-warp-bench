#!/usr/bin/env nu
# Generate @dfreeman/warp JSValue direct FFI fast-path optimizations (Step 4C Part 1).

def main [] {
    let dest = $env.FILE_PWD | path join ".." ".." ".." "target" "unison" "frontend-bench" | path expand; mkdir $dest
    let out = ($dest | path join "scratch-warp--perf-js.u")

    r##'{{
JavaScript support class wrapping host JS values, caching immutable unanchored
singletons for `undefined`, `null`, `true`, and `false`.
}}
internal.javascript.supportJS.jsValueJS : Text
internal.javascript.supportJS.jsValueJS =
  """
  class JSValue {
    static globalThis = new JSValue(globalThis, null);
    static UNDEFINED = new JSValue(undefined, null);
    static NULL = new JSValue(null, null);
    static TRUE = new JSValue(true, null);
    static FALSE = new JSValue(false, null);
    static unanchored(value) {
      if (value === undefined) return JSValue.UNDEFINED;
      if (value === null) return JSValue.NULL;
      if (value === true) return JSValue.TRUE;
      if (value === false) return JSValue.FALSE;
      return new JSValue(value, null);
    }

    constructor(value, prop) {
      this.value = value;
      this.prop = prop;
    }

    get() {
      return this.prop ? this.value?.[this.prop] : this.value;
    }

    set(value) {
      if (!this.prop || !this.value) return false
      this.value[this.prop] = value;
      return true;
    }

    getProperty(prop) {
      return new JSValue(this.get(), prop);
    }

    call(args) {
      return this.get().apply(this.value, args);
    }
  }
  """

{{
Eagerly reads `ref?.[prop]` and returns an unanchored {type JSValue} in a single
host crossing without allocating an intermediate anchored {type JSValue}.
}}
JSValue.getProperty : Text -> JSValue ->{JS} JSValue
JSValue.getProperty _prop _ref = wasmOnly "JSValue.getProperty"

{{
Sets `ref[prop] = val` directly on `ref` without allocating an anchored
{type JSValue} or {type Optional} result.
}}
JSValue.setProperty : Text -> JSValue -> JSValue ->{JS} ()
JSValue.setProperty _prop _val _ref = wasmOnly "JSValue.setProperty"

{{
Sets `ref[prop] = text` directly using the host JS string backing {type Text}
without wrapping `text` in a temporary {type JSValue}.
}}
JSValue.setPropertyText : Text -> Text -> JSValue ->{JS} ()
JSValue.setPropertyText _prop _text _ref = wasmOnly "JSValue.setPropertyText"

{{
Invokes `ref[method]()` with zero arguments and returns the unanchored
{type JSValue} result.
}}
JSValue.invoke0 : Text -> JSValue ->{JS} JSValue
JSValue.invoke0 _method _ref = wasmOnly "JSValue.invoke0"

{{
Invokes `ref[method]()` with zero arguments and discards the result with zero
heap allocations.
}}
JSValue.invoke0_ : Text -> JSValue ->{JS} ()
JSValue.invoke0_ _method _ref = wasmOnly "JSValue.invoke0_"

{{
Invokes `ref[method](arg0)` and discards the result without allocating a
{type List} or JS argument array.
}}
JSValue.invoke1_ : Text -> JSValue -> JSValue ->{JS} ()
JSValue.invoke1_ _method _arg0 _ref = wasmOnly "JSValue.invoke1_"

{{
Invokes `ref[method](str0)` passing a host JS string directly and returns the
unanchored {type JSValue} result.
}}
JSValue.invokeText1 : Text -> Text -> JSValue ->{JS} JSValue
JSValue.invokeText1 _method _str0 _ref = wasmOnly "JSValue.invokeText1"

{{
Invokes `ref[method](str0)` passing a host JS string directly and discards the
result with zero heap allocations.
}}
JSValue.invokeText1_ : Text -> Text -> JSValue ->{JS} ()
JSValue.invokeText1_ _method _str0 _ref = wasmOnly "JSValue.invokeText1_"

{{
Invokes `ref[method](str0, str1)` passing two host JS strings directly and
returns the unanchored {type JSValue} result.
}}
JSValue.invokeText2 : Text -> Text -> Text -> JSValue ->{JS} JSValue
JSValue.invokeText2 _method _str0 _str1 _ref = wasmOnly "JSValue.invokeText2"

{{
Invokes `ref[method](str0, str1)` passing two host JS strings directly and
discards the result with zero heap allocations.
}}
JSValue.invokeText2_ : Text -> Text -> Text -> JSValue ->{JS} ()
JSValue.invokeText2_ _method _str0 _str1 _ref = wasmOnly "JSValue.invokeText2_"

{{
Invokes `ref[method](str0, str1, str2)` passing three host JS strings directly
and discards the result with zero heap allocations.
}}
JSValue.invokeText3_ : Text -> Text -> Text -> Text -> JSValue ->{JS} ()
JSValue.invokeText3_ _method _str0 _str1 _str2 _ref = wasmOnly "JSValue.invokeText3_"

{{
Invokes `ref[method](str0, val)` passing a host JS string and unwrapped
{type JSValue} directly and discards the result with zero heap allocations.
}}
JSValue.invokeTextVal_ : Text -> Text -> JSValue -> JSValue ->{JS} ()
JSValue.invokeTextVal_ _method _str0 _val _ref = wasmOnly "JSValue.invokeTextVal_"

{{
Creates a 1-argument JavaScript callback from a Unison function, discarding the
Unison return value without allocating rest-argument arrays, Unison lists, or
intermediate wrapper closures.
}}
JSValue.callback1_ : (JSValue ->{JS} a) ->{JS} JSValue
JSValue.callback1_ _callback = wasmOnly "JSValue.callback1_"

{{
Runtime replacement for {JSValue.getProperty}.
}}
internal.runtime.replacements.warp_js.JSValue_getProperty : Replacement
internal.runtime.replacements.warp_js.JSValue_getProperty =
  src =
    "(rt, prop, ref) => rt.Foreign(rt.js.JSValue.unanchored(rt.Foreign_getValue(ref).get()?.[rt.Text_getValue(prop)]))"
  internal.Replacement.jsFunction 2 src

{{
Runtime replacement for {JSValue.setProperty}.
}}
internal.runtime.replacements.warp_js.JSValue_setProperty : Replacement
internal.runtime.replacements.warp_js.JSValue_setProperty =
  src =
    """
    (rt, prop, val, ref) => {
      let obj = rt.Foreign_getValue(ref).get();
      if (obj != null) obj[rt.Text_getValue(prop)] = rt.Foreign_getValue(val).get();
      return rt.Unit();
    }
    """
  internal.Replacement.jsFunction 3 src

{{
Runtime replacement for {JSValue.setPropertyText}.
}}
internal.runtime.replacements.warp_js.JSValue_setPropertyText : Replacement
internal.runtime.replacements.warp_js.JSValue_setPropertyText =
  src =
    """
    (rt, prop, text, ref) => {
      let obj = rt.Foreign_getValue(ref).get();
      if (obj != null) obj[rt.Text_getValue(prop)] = rt.Text_getValue(text);
      return rt.Unit();
    }
    """
  internal.Replacement.jsFunction 3 src

{{
Runtime replacement for {JSValue.invoke0}.
}}
internal.runtime.replacements.warp_js.JSValue_invoke0 : Replacement
internal.runtime.replacements.warp_js.JSValue_invoke0 =
  src =
    """
    (rt, method, ref) => {
      let obj = rt.Foreign_getValue(ref).get();
      return rt.Foreign(rt.js.JSValue.unanchored(obj[rt.Text_getValue(method)]()));
    }
    """
  internal.Replacement.jsFunction 2 src

{{
Runtime replacement for {JSValue.invoke0_}.
}}
internal.runtime.replacements.warp_js.JSValue_invoke0_ : Replacement
internal.runtime.replacements.warp_js.JSValue_invoke0_ =
  src =
    """
    (rt, method, ref) => {
      let obj = rt.Foreign_getValue(ref).get();
      obj[rt.Text_getValue(method)]();
      return rt.Unit();
    }
    """
  internal.Replacement.jsFunction 2 src

{{
Runtime replacement for {JSValue.invoke1_}.
}}
internal.runtime.replacements.warp_js.JSValue_invoke1_ : Replacement
internal.runtime.replacements.warp_js.JSValue_invoke1_ =
  src =
    """
    (rt, method, arg0, ref) => {
      let obj = rt.Foreign_getValue(ref).get();
      obj[rt.Text_getValue(method)](rt.Foreign_getValue(arg0).get());
      return rt.Unit();
    }
    """
  internal.Replacement.jsFunction 3 src

{{
Runtime replacement for {JSValue.invokeText1}.
}}
internal.runtime.replacements.warp_js.JSValue_invokeText1 : Replacement
internal.runtime.replacements.warp_js.JSValue_invokeText1 =
  src =
    """
    (rt, method, str0, ref) => {
      let obj = rt.Foreign_getValue(ref).get();
      return rt.Foreign(rt.js.JSValue.unanchored(obj[rt.Text_getValue(method)](rt.Text_getValue(str0))));
    }
    """
  internal.Replacement.jsFunction 3 src

{{
Runtime replacement for {JSValue.invokeText1_}.
}}
internal.runtime.replacements.warp_js.JSValue_invokeText1_ : Replacement
internal.runtime.replacements.warp_js.JSValue_invokeText1_ =
  src =
    """
    (rt, method, str0, ref) => {
      let obj = rt.Foreign_getValue(ref).get();
      obj[rt.Text_getValue(method)](rt.Text_getValue(str0));
      return rt.Unit();
    }
    """
  internal.Replacement.jsFunction 3 src

{{
Runtime replacement for {JSValue.invokeText2}.
}}
internal.runtime.replacements.warp_js.JSValue_invokeText2 : Replacement
internal.runtime.replacements.warp_js.JSValue_invokeText2 =
  src =
    """
    (rt, method, str0, str1, ref) => {
      let obj = rt.Foreign_getValue(ref).get();
      return rt.Foreign(rt.js.JSValue.unanchored(obj[rt.Text_getValue(method)](rt.Text_getValue(str0), rt.Text_getValue(str1))));
    }
    """
  internal.Replacement.jsFunction 4 src

{{
Runtime replacement for {JSValue.invokeText2_}.
}}
internal.runtime.replacements.warp_js.JSValue_invokeText2_ : Replacement
internal.runtime.replacements.warp_js.JSValue_invokeText2_ =
  src =
    """
    (rt, method, str0, str1, ref) => {
      let obj = rt.Foreign_getValue(ref).get();
      obj[rt.Text_getValue(method)](rt.Text_getValue(str0), rt.Text_getValue(str1));
      return rt.Unit();
    }
    """
  internal.Replacement.jsFunction 4 src

{{
Runtime replacement for {JSValue.invokeText3_}.
}}
internal.runtime.replacements.warp_js.JSValue_invokeText3_ : Replacement
internal.runtime.replacements.warp_js.JSValue_invokeText3_ =
  src =
    """
    (rt, method, str0, str1, str2, ref) => {
      let obj = rt.Foreign_getValue(ref).get();
      obj[rt.Text_getValue(method)](rt.Text_getValue(str0), rt.Text_getValue(str1), rt.Text_getValue(str2));
      return rt.Unit();
    }
    """
  internal.Replacement.jsFunction 5 src

{{
Runtime replacement for {JSValue.invokeTextVal_}.
}}
internal.runtime.replacements.warp_js.JSValue_invokeTextVal_ : Replacement
internal.runtime.replacements.warp_js.JSValue_invokeTextVal_ =
  src =
    """
    (rt, method, str0, val, ref) => {
      let obj = rt.Foreign_getValue(ref).get();
      obj[rt.Text_getValue(method)](rt.Text_getValue(str0), rt.Foreign_getValue(val).get());
      return rt.Unit();
    }
    """
  internal.Replacement.jsFunction 4 src

{{
Runtime replacement for {JSValue.callback1_}.
}}
internal.runtime.replacements.warp_js.JSValue_callback1_ : Replacement
internal.runtime.replacements.warp_js.JSValue_callback1_ =
  src =
    """
    (rt, func) => {
      return rt.Foreign(rt.js.JSValue.unanchored((arg0) => {
        let argVal = rt.Foreign(rt.js.JSValue.unanchored(arg0));
        let argsValue = rt.Args_of(argVal, 1);
        rt.callDirect(argsValue, func);
      }));
    }
    """
  internal.Replacement.jsFunction 1 src

{{
Full Warp runtime replacement map including direct {type JSValue} property,
method, and callback fast paths.
}}
internal.runtime.replacements :
  BuildConfig ->{IO, Exception} Map Reference Replacement
internal.runtime.replacements config =
  use Reference Builtin
  reflectionSupport = BuildConfig.reflectionSupport config
  Map.fromList
    [ (termReference JS.ref, Scope_ref)
    , (termReference JS.randomBytes, JS_randomBytes)
    , (termReference JSValue.any, JSValue_any)
    , (termReference JSValue.array, JSValue_array)
    , (termReference JSValue.arrayBuffer, JSValue_arrayBuffer)
    , (termReference JSValue.asAny, JSValue_asAny)
    , (termReference JSValue.asBoolean, JSValue_asBoolean)
    , (termReference JSValue.asBytes, JSValue_asBytes)
    , (termReference JSValue.asFloat, JSValue_asFloat)
    , (termReference JSValue.asInt, JSValue_asInt)
    , (termReference JSValue.asList, JSValue_asList)
    , (termReference JSValue.asNat, JSValue_asNat)
    , (termReference JSValue.assign, JSValue_assign)
    , (termReference JSValue.asText, JSValue_asText)
    , (termReference JSValue.bigint, JSValue_bigint)
    , (termReference JSValue.biguint, JSValue_biguint)
    , (termReference JSValue.boolean, JSValue_boolean)
    , (termReference JSValue.call, JSValue_call)
    , (termReference JSValue.callback1_, JSValue_callback1_)
    , (termReference JSValue.function, JSValue_function)
    , (termReference JSValue.getProperty, JSValue_getProperty)
    , (termReference JSValue.global, JSValue_global)
    , (termReference JSValue.invoke0, JSValue_invoke0)
    , (termReference JSValue.invoke0_, JSValue_invoke0_)
    , (termReference JSValue.invoke1_, JSValue_invoke1_)
    , (termReference JSValue.invokeText1, JSValue_invokeText1)
    , (termReference JSValue.invokeText1_, JSValue_invokeText1_)
    , (termReference JSValue.invokeText2, JSValue_invokeText2)
    , (termReference JSValue.invokeText2_, JSValue_invokeText2_)
    , (termReference JSValue.invokeText3_, JSValue_invokeText3_)
    , (termReference JSValue.invokeTextVal_, JSValue_invokeTextVal_)
    , (termReference JSValue.isNull, JSValue_isNull)
    , (termReference JSValue.isUndefined, JSValue_isUndefined)
    , (termReference JSValue.new, JSValue_new)
    , (termReference JSValue.null, JSValue_null)
    , (termReference JSValue.number, JSValue_number)
    , (termReference JSValue.object, JSValue_object)
    , (termReference JSValue.property, JSValue_property)
    , (termReference JSValue.setProperty, JSValue_setProperty)
    , (termReference JSValue.setPropertyText, JSValue_setPropertyText)
    , (termReference JSValue.string, JSValue_string)
    , (termReference JSValue.undefined, JSValue_undefined)
    , (termReference fromBuiltin, Value_fromBuiltin)
    , (termReference toBuiltin, Value_toBuiltin)
    , (termReference CacheCode.fromCode, CacheCode_fromCode)
    , (termReference CacheCode.toCode, CacheCode_toCode)
    , ( termReference lookupArity
      , includeIf
          (requiresTermReferences reflectionSupport)
          build_jit_lookupArity
      )
    , ( termReference instantiateModule
      , includeIf
          (requiresTermReferences reflectionSupport)
          build_jit_instantiateModule
      )
    , ( termReference JS.catchRuntimeErrors
      , JS_catchRuntimeErrors
      )
    , ( termReference Async.catchRuntimeErrors
      , Async_catchRuntimeErrors
      )
    , (Builtin "Any.Any", Any_Any)
    , (Builtin "Any.unsafeExtract", Any_unsafeExtract)
    , (Builtin "Boolean.and", Boolean_and)
    , (Builtin "Boolean.not", Boolean_not)
    , (Builtin "Boolean.or", Boolean_or)
    , (Builtin "bug", panicWithLabel "builtin.bug")
    , (Builtin "Bytes.++", Bytes_append)
    , (Builtin "Bytes.at", Bytes_at)
    , (Builtin "Bytes.decodeNat16be", Bytes_decodeNat16be)
    , (Builtin "Bytes.decodeNat16le", Bytes_decodeNat16le)
    , (Builtin "Bytes.decodeNat32be", Bytes_decodeNat32be)
    , (Builtin "Bytes.decodeNat32le", Bytes_decodeNat32le)
    , (Builtin "Bytes.decodeNat64be", Bytes_decodeNat64be)
    , (Builtin "Bytes.decodeNat64le", Bytes_decodeNat64le)
    , (Builtin "Bytes.drop", Bytes_drop)
    , (Builtin "Bytes.empty", Bytes_empty)
    , (Builtin "Bytes.encodeNat16be", Bytes_encodeNat16be)
    , (Builtin "Bytes.encodeNat16le", Bytes_encodeNat16le)
    , (Builtin "Bytes.encodeNat32be", Bytes_encodeNat32be)
    , (Builtin "Bytes.encodeNat32le", Bytes_encodeNat32le)
    , (Builtin "Bytes.encodeNat64be", Bytes_encodeNat64be)
    , (Builtin "Bytes.encodeNat64le", Bytes_encodeNat64le)
    , (Builtin "Bytes.flatten", Bytes_flatten)
    , (Builtin "Bytes.fromBase16", Bytes_fromBase16)
    , (Builtin "Bytes.fromBase32", Bytes_fromBase32)
    , (Builtin "Bytes.fromBase64", Bytes_fromBase64)
    , ( Builtin "Bytes.fromBase64UrlUnpadded"
      , Bytes_fromBase64UrlUnpadded
      )
    , (Builtin "Bytes.fromList", Bytes_fromList)
    , (Builtin "Bytes.indexOf", Bytes_indexOf)
    , (Builtin "Bytes.size", Bytes_size)
    , (Builtin "Bytes.take", Bytes_take)
    , (Builtin "Bytes.toBase16", Bytes_toBase16)
    , (Builtin "Bytes.toBase32", Bytes_toBase32)
    , (Builtin "Bytes.toBase64", Bytes_toBase64)
    , ( Builtin "Bytes.toBase64UrlUnpadded"
      , Bytes_toBase64UrlUnpadded
      )
    , (Builtin "Bytes.toList", Bytes_toList)
    , ( Builtin "Char.Class.alphanumeric"
      , Char_Class_alphanumeric
      )
    , (Builtin "Char.Class.and", Char_Class_and)
    , (Builtin "Char.Class.any", Char_Class_any)
    , (Builtin "Char.Class.anyOf", Char_Class_anyOf)
    , (Builtin "Char.Class.control", Char_Class_control)
    , (Builtin "Char.Class.is", Char_Class_is)
    , (Builtin "Char.Class.letter", Char_Class_letter)
    , (Builtin "Char.Class.lower", Char_Class_lower)
    , (Builtin "Char.Class.mark", Char_Class_mark)
    , (Builtin "Char.Class.not", Char_Class_not)
    , (Builtin "Char.Class.number", Char_Class_number)
    , (Builtin "Char.Class.or", Char_Class_or)
    , (Builtin "Char.Class.printable", Char_Class_printable)
    , ( Builtin "Char.Class.punctuation"
      , Char_Class_punctuation
      )
    , (Builtin "Char.Class.range", Char_Class_range)
    , (Builtin "Char.Class.separator", Char_Class_separator)
    , (Builtin "Char.Class.symbol", Char_Class_symbol)
    , (Builtin "Char.Class.upper", Char_Class_upper)
    , (Builtin "Char.Class.whitespace", Char_Class_whitespace)
    , (Builtin "Char.fromNat", Char_fromNat)
    , (Builtin "Char.toNat", Char_toNat)
    , (Builtin "Char.toText", Char_toText)
    , ( Builtin "Code.cache_"
      , Unimplemented "Reflection needs some design work"
      )
    , ( Builtin "Code.dependencies"
      , Unimplemented "Reflection needs some design work"
      )
    , ( Builtin "Code.deserialize"
      , includeIf
          (requiresSerialization reflectionSupport)
          Code_deserialize
      )
    , ( Builtin "Code.display"
      , Unimplemented "Reflection needs some design work"
      )
    , ( Builtin "Code.isMissing"
      , includeIf
          (requiresTermReferences reflectionSupport)
          Code_isMissing
      )
    , ( Builtin "Code.lookup"
      , Unimplemented "Reflection needs some design work"
      )
    , ( Builtin "Code.serialize"
      , Unimplemented "Reflection needs some design work"
      )
    , ( Builtin "Code.validate"
      , Unimplemented "Reflection needs some design work"
      )
    , ( Builtin "Code.validateLinks"
      , Unimplemented "Reflection needs some design work"
      )
    , (Builtin "Debug.toText", Debug_toText)
    , (Builtin "Debug.trace", Debug_trace)
    , (Builtin "Debug.watch", Debug_watch)
    , (Builtin "Float.-", Float_minus)
    , (Builtin "Float.!=", Float_ne)
    , (Builtin "Float.*", Float_times)
    , (Builtin "Float./", Float_div)
    , (Builtin "Float.+", Float_plus)
    , (Builtin "Float.<", Float_lt)
    , (Builtin "Float.<=", Float_lte)
    , (Builtin "Float.==", Float_eq)
    , (Builtin "Float.>", Float_gt)
    , (Builtin "Float.>=", Float_gte)
    , (Builtin "Float.abs", Float_abs)
    , (Builtin "Float.acos", Float_acos)
    , (Builtin "Float.acosh", Float_acosh)
    , (Builtin "Float.asin", Float_asin)
    , (Builtin "Float.asinh", Float_asinh)
    , (Builtin "Float.atan", Float_atan)
    , (Builtin "Float.atan2", Float_atan2)
    , (Builtin "Float.atanh", Float_atanh)
    , (Builtin "Float.ceiling", Float_ceiling)
    , (Builtin "Float.cos", Float_cos)
    , (Builtin "Float.cosh", Float_cosh)
    , (Builtin "Float.exp", Float_exp)
    , (Builtin "Float.floor", Float_floor)
    , ( Builtin "Float.fromRepresentation"
      , Float_fromRepresentation
      )
    , (Builtin "Float.fromText", Float_fromText)
    , (Builtin "Float.log", Float_log)
    , (Builtin "Float.logBase", Float_logBase)
    , (Builtin "Float.max", Float_max)
    , (Builtin "Float.min", Float_min)
    , (Builtin "Float.pow", Float_pow)
    , (Builtin "Float.round", Float_round)
    , (Builtin "Float.sin", Float_sin)
    , (Builtin "Float.sinh", Float_sinh)
    , (Builtin "Float.sqrt", Float_sqrt)
    , (Builtin "Float.tan", Float_tan)
    , (Builtin "Float.tanh", Float_tanh)
    , ( Builtin "Float.toRepresentation"
      , Float_toRepresentation
      )
    , (Builtin "Float.toText", Float_toText)
    , (Builtin "Float.truncate", Float_truncate)
    , (Builtin "ImmutableArray.copyTo!", RawArray_copyTo!)
    , (Builtin "ImmutableArray.read", RawArray_read)
    , (Builtin "ImmutableArray.size", RawArray_size)
    , ( Builtin "ImmutableByteArray.copyTo!"
      , RawByteArray_copyTo!
      )
    , ( Builtin "ImmutableByteArray.fromBytes"
      , RawByteArray_fromBytes
      )
    , ( Builtin "ImmutableByteArray.read16be"
      , RawByteArray_read16be
      )
    , ( Builtin "ImmutableByteArray.read24be"
      , RawByteArray_read24be
      )
    , ( Builtin "ImmutableByteArray.read32be"
      , RawByteArray_read32be
      )
    , ( Builtin "ImmutableByteArray.read40be"
      , RawByteArray_read40be
      )
    , ( Builtin "ImmutableByteArray.read64be"
      , RawByteArray_read64be
      )
    , (Builtin "ImmutableByteArray.read8", RawByteArray_read8)
    , (Builtin "ImmutableByteArray.size", RawByteArray_size)
    , ( Builtin "ImmutableByteArray.toBytes"
      , RawByteArray_toBytes
      )
    , (Builtin "Int.-", Int_minus)
    , (Builtin "Int.*", Int_times)
    , (Builtin "Int./", Int_div)
    , (Builtin "Int.+", Int_plus)
    , (Builtin "Int.<", Int_lt)
    , (Builtin "Int.<=", Int_lte)
    , (Builtin "Int.==", Int_eq)
    , (Builtin "Int.>", Int_gt)
    , (Builtin "Int.>=", Int_gte)
    , (Builtin "Int.and", Int_and)
    , (Builtin "Int.complement", Int_complement)
    , ( Builtin "Int.fromRepresentation"
      , Int_fromRepresentation
      )
    , (Builtin "Int.fromText", Int_fromText)
    , (Builtin "Int.increment", Int_increment)
    , (Builtin "Int.isEven", Int_isEven)
    , (Builtin "Int.isOdd", Int_isOdd)
    , (Builtin "Int.leadingZeros", Int_leadingZeroes)
    , (Builtin "Int.mod", Int_mod)
    , (Builtin "Int.negate", Int_negate)
    , (Builtin "Int.or", Int_or)
    , (Builtin "Int.popCount", Int_popCount)
    , (Builtin "Int.pow", Int_pow)
    , (Builtin "Int.shiftLeft", Int_shiftLeft)
    , (Builtin "Int.shiftRight", Int_shiftRight)
    , (Builtin "Int.signum", Int_signum)
    , (Builtin "Int.toFloat", Int_toFloat)
    , (Builtin "Int.toRepresentation", Int_toRepresentation)
    , (Builtin "Int.toText", Int_toText)
    , (Builtin "Int.trailingZeros", Int_trailingZeroes)
    , (Builtin "Int.truncate0", Int_truncate0)
    , (Builtin "Int.xor", Int_xor)
    , (Builtin "jumpCont", jumpCont)
    , (Builtin "Link.Term.toText", Link_Term_toText)
    , (Builtin "List.++", List_append)
    , (Builtin "List.at", List_at)
    , (Builtin "List.cons", List_cons)
    , (Builtin "List.drop", List_drop)
    , (Builtin "List.empty", List_empty)
    , (Builtin "List.size", List_size)
    , (Builtin "List.snoc", List_snoc)
    , (Builtin "List.take", List_take)
    , (Builtin "List.viewl", List_viewl)
    , (Builtin "List.viewr", List_viewr)
    , (Builtin "MutableArray.copyTo!", RawArray_copyTo!)
    , (Builtin "MutableArray.freeze!", RawArray_freeze!)
    , (Builtin "MutableArray.freeze", RawArray_freeze)
    , (Builtin "MutableArray.read", RawArray_read)
    , (Builtin "MutableArray.size", RawArray_size)
    , (Builtin "MutableArray.write", RawArray_write)
    , ( Builtin "MutableByteArray.copyTo!"
      , RawByteArray_copyTo!
      )
    , ( Builtin "MutableByteArray.freeze!"
      , RawByteArray_freeze!
      )
    , (Builtin "MutableByteArray.freeze", RawByteArray_freeze)
    , ( Builtin "MutableByteArray.read16be"
      , RawByteArray_read16be
      )
    , ( Builtin "MutableByteArray.read24be"
      , RawByteArray_read24be
      )
    , ( Builtin "MutableByteArray.read32be"
      , RawByteArray_read32be
      )
    , ( Builtin "MutableByteArray.read40be"
      , RawByteArray_read40be
      )
    , ( Builtin "MutableByteArray.read64be"
      , RawByteArray_read64be
      )
    , (Builtin "MutableByteArray.read8", RawByteArray_read8)
    , (Builtin "MutableByteArray.size", RawByteArray_size)
    , ( Builtin "MutableByteArray.write16be"
      , RawByteArray_write16be
      )
    , ( Builtin "MutableByteArray.write32be"
      , RawByteArray_write32be
      )
    , ( Builtin "MutableByteArray.write64be"
      , RawByteArray_write64be
      )
    , (Builtin "MutableByteArray.write8", RawByteArray_write8)
    , (Builtin "Nat.*", Nat_times)
    , (Builtin "Nat./", Nat_div)
    , (Builtin "Nat.+", Nat_plus)
    , (Builtin "Nat.<", Nat_lt)
    , (Builtin "Nat.<=", Nat_lte)
    , (Builtin "Nat.==", Nat_eq)
    , (Builtin "Nat.>", Nat_gt)
    , (Builtin "Nat.>=", Nat_gte)
    , (Builtin "Nat.and", Nat_and)
    , (Builtin "Nat.complement", Nat_complement)
    , (Builtin "Nat.drop", Nat_drop)
    , (Builtin "Nat.fromText", Nat_fromText)
    , (Builtin "Nat.increment", Nat_increment)
    , (Builtin "Nat.isEven", Nat_isEven)
    , (Builtin "Nat.isOdd", Nat_isOdd)
    , (Builtin "Nat.leadingZeros", Nat_leadingZeroes)
    , (Builtin "Nat.mod", Nat_mod)
    , (Builtin "Nat.or", Nat_or)
    , (Builtin "Nat.popCount", Nat_popCount)
    , (Builtin "Nat.pow", Nat_pow)
    , (Builtin "Nat.shiftLeft", Nat_shiftLeft)
    , (Builtin "Nat.shiftRight", Nat_shiftRight)
    , (Builtin "Nat.sub", Nat_sub)
    , (Builtin "Nat.toFloat", Nat_toFloat)
    , (Builtin "Nat.toInt", Int_fromRepresentation)
    , (Builtin "Nat.toText", Nat_toText)
    , (Builtin "Nat.trailingZeros", Nat_trailingZeroes)
    , (Builtin "Nat.xor", Nat_xor)
    , (Builtin "Pattern.capture", Pattern_capture)
    , (Builtin "Pattern.captureAs", Pattern_captureAs)
    , (Builtin "Pattern.isMatch", Pattern_isMatch)
    , (Builtin "Pattern.join", Pattern_join)
    , (Builtin "Pattern.lookahead", Pattern_lookahead)
    , (Builtin "Pattern.many.corrected", Pattern_many)
    , ( Builtin "Pattern.many"
      , Unimplemented
          "Your code relies on a broken version of `Pattern.many` (you probably need to upgrade `@unison/base`)"
      )
    , ( Builtin "Pattern.negativeLookahead"
      , Pattern_negativeLookahead
      )
    , (Builtin "Pattern.or", Pattern_or)
    , (Builtin "Pattern.replicate", Pattern_replicate)
    , (Builtin "Pattern.run", Pattern_run)
    , (Builtin "Ref.read", Ref_read)
    , (Builtin "Ref.write", Ref_write)
    , (Builtin "Scope.array", Scope_array)
    , (Builtin "Scope.arrayOf", Scope_arrayOf)
    , (Builtin "Scope.bytearray", Scope_bytearray)
    , (Builtin "Scope.bytearrayOf", Scope_bytearrayOf)
    , (Builtin "Scope.ref", Scope_ref)
    , (Builtin "Scope.run", Scope_run)
    , (Builtin "Text.!=", Text_ne)
    , (Builtin "Text.++", Text_concat)
    , (Builtin "Text.<", Text_lt)
    , (Builtin "Text.<=", Text_lte)
    , (Builtin "Text.==", Text_eq)
    , (Builtin "Text.>", Text_gt)
    , (Builtin "Text.>=", Text_gte)
    , (Builtin "Text.drop", Text_drop)
    , (Builtin "Text.empty", Text_empty)
    , (Builtin "Text.fromCharList", Text_fromCharList)
    , (Builtin "Text.fromUtf8.impl.v3", Text_fromUtf8_impl_v3)
    , (Builtin "Text.indexOf", Text_indexOf)
    , (Builtin "Text.patterns.anyChar", Text_patterns_anyChar)
    , (Builtin "Text.patterns.char", Text_patterns_char)
    , (Builtin "Text.patterns.charIn", Text_patterns_charIn)
    , ( Builtin "Text.patterns.charRange"
      , Text_patterns_charRange
      )
    , (Builtin "Text.patterns.digit", Text_patterns_digit)
    , (Builtin "Text.patterns.eof", Text_patterns_eof)
    , (Builtin "Text.patterns.letter", Text_patterns_letter)
    , (Builtin "Text.patterns.literal", Text_patterns_literal)
    , ( Builtin "Text.patterns.lookbehind"
      , Text_patterns_lookbehind
      )
    , ( Builtin "Text.patterns.negativeLookbehind"
      , Text_patterns_negativeLookbehind
      )
    , ( Builtin "Text.patterns.notCharIn"
      , Text_patterns_notCharIn
      )
    , ( Builtin "Text.patterns.notCharRange"
      , Text_patterns_notCharRange
      )
    , ( Builtin "Text.patterns.punctuation"
      , Text_patterns_punctuation
      )
    , (Builtin "Text.patterns.space", Text_patterns_space)
    , (Builtin "Text.repeat", Text_repeat)
    , (Builtin "Text.reverse", Text_reverse)
    , (Builtin "Text.size", Text_size)
    , (Builtin "Text.take", Text_take)
    , (Builtin "Text.toCharList", Text_toCharList)
    , (Builtin "Text.toLowercase", Text_toLowercase)
    , (Builtin "Text.toUppercase", Text_toUppercase)
    , (Builtin "Text.toUtf8", Text_toUtf8)
    , (Builtin "Text.uncons", Text_uncons)
    , (Builtin "Text.unsnoc", Text_unsnoc)
    , (Builtin "todo", panicWithLabel "builtin.todo")
    , (Builtin "Universal.<", Universal_lt)
    , (Builtin "Universal.<=", Universal_lte)
    , (Builtin "Universal.==", Universal_eq)
    , (Builtin "Universal.>", Universal_gt)
    , (Builtin "Universal.>=", Universal_gte)
    , (Builtin "Universal.compare", Universal_compare)
    , ( Builtin "unsafe.coerceAbilities"
      , unsafe_coerceAbilities
      )
    , ( Builtin "Value.dependencies"
      , includeIf
          (requiresSerialization reflectionSupport)
          Value_dependencies
      )
    , ( Builtin "Value.deserialize"
      , includeIf
          (requiresSerialization reflectionSupport)
          Value_deserialize
      )
    , ( Builtin "Value.load"
      , includeIf
          (requiresSerialization reflectionSupport) Value_load
      )
    , ( Builtin "Value.serialize"
      , includeIf
          (requiresSerialization reflectionSupport)
          Value_serialize
      )
    , ( Builtin "Value.value"
      , includeIf
          (requiresSerialization reflectionSupport)
          Value_value
      )
    ]

{{
Wasm test exercising direct {type JSValue} property, method, callback, and
singleton fast paths.
}}
tests.js.jsDirectFastPaths : WasmTest
tests.js.jsDirectFastPaths =
  wasmTest "JSValue direct fast paths" do
    use JSValue asBoolean! asText! boolean callback1_ getProperty global invoke0 invoke0_ invoke1_ invokeText1 invokeText1_ invokeText2 invokeText2_ invokeText3_ invokeTextVal_ isNull isUndefined object setProperty setPropertyText string
    use test ensure ensureEqual
    box = object []
    setPropertyText "label" "initial" box
    ensureEqual (asText! (getProperty "label" box)) "initial"
    setProperty "flag" (boolean true) box
    ensureEqual (asBoolean! (getProperty "flag" box)) true
    setProperty "flag" (boolean false) box
    ensureEqual (asBoolean! (getProperty "flag" box)) false
    ensure (isUndefined (getProperty "missing" box))
    setProperty "empty" (JSValue.null()) box
    ensure (isNull (getProperty "empty" box))
    ensure (JSValue.null() === JSValue.null())
    ensure (JSValue.undefined() === JSValue.undefined())
    ensure (boolean true === boolean true)
    ensure (boolean false === boolean false)
    ensure (boolean true !== boolean false)

    hostFactory =
      global "Function"
        :$ [ string
               """
               return {
                 items: [],
                 attrs: {},
                 zero() { this.items.push('z'); return 'z-ret'; },
                 pushVal(val) { this.items.push(val); },
                 upper(str) { return str.toUpperCase(); },
                 tag1(str) { this.items.push(str); },
                 join2(aa, bb) { return aa + ':' + bb; },
                 set2(kk, vv) { this.attrs[kk] = vv; },
                 set3(ns, kk, vv) { this.attrs[ns + ':' + kk] = vv; },
                 on(ev, fn) { this.cb = fn; this.ev = ev; },
                 fire(arg) { this.cb(arg); }
               };
               """
           ]
    host = hostFactory :$ []
    ensureEqual (asText! (invoke0 "zero" host)) "z-ret"
    invoke0_ "zero" host
    invoke1_ "pushVal" (string "v1") host
    ensureEqual (asText! (invokeText1 "upper" "warp" host)) "WARP"
    invokeText1_ "tag1" "t1" host
    ensureEqual (asText! (invokeText2 "join2" "left" "right" host)) "left:right"
    invokeText2_ "set2" "class" "danger" host
    invokeText3_ "set3" "svg" "viewBox" "0 0 10 10" host
    attrs = getProperty "attrs" host
    ensureEqual (asText! (getProperty "class" attrs)) "danger"
    ensureEqual (asText! (getProperty "svg:viewBox" attrs)) "0 0 10 10"

    seenRef = JS.ref "none"
    cb = callback1_ (ev -> Ref.write seenRef (asText! ev))
    invokeTextVal_ "on" "click" cb host
    invokeText1_ "fire" "clicked!" host
    ensureEqual (Ref.read seenRef) "clicked!"

{{
JS interface Wasm test suite including direct fast-path coverage.
}}
tests.js : [WasmTest]
tests.js =
  List.map
    (WasmTest.group "JS interface")
    [ jsValueRoundtrip
    , jsComparison
    , jsFunctions
    , jsDirectFastPaths
    , jsErrorCatching
    ]
'## | save --force $out
    print $out
}
