(module
  (type $chars (array (mut i16)))
  (import "wasm:js-string" "fromCharCodeArray" (func $fromArray (param (ref null $chars) i32 i32) (result (ref extern))))
  (import "wasm:js-string" "intoCharCodeArray" (func $intoArray (param externref (ref null $chars) i32) (result i32)))
  (import "wasm:js-string" "length" (func $length (param externref) (result i32)))
  (import "env" "sink" (func $sink (param externref)))
  (global $keep (mut externref) (ref.null extern))
  ;; n strings of `len` characters, each built from a fresh i16 array and handed to JS
  (func (export "toJS") (param $n i32) (param $len i32)
    (local $i i32) (local $j i32) (local $a (ref null $chars))
    (loop $outer
      (local.set $a (array.new_default $chars (local.get $len)))
      (local.set $j (i32.const 0))
      (loop $inner
        (array.set $chars (local.get $a) (local.get $j) (i32.add (i32.const 97) (i32.rem_u (i32.add (local.get $i) (local.get $j)) (i32.const 26))))
        (local.set $j (i32.add (local.get $j) (i32.const 1)))
        (br_if $inner (i32.lt_u (local.get $j) (local.get $len))))
      (call $sink (call $fromArray (local.get $a) (i32.const 0) (local.get $len)))
      (local.set $i (i32.add (local.get $i) (i32.const 1)))
      (br_if $outer (i32.lt_u (local.get $i) (local.get $n)))))
  ;; the same strings already JS strings (option A): only the hand-over
  (func (export "passJS") (param $s externref) (param $n i32)
    (local $i i32)
    (loop $l
      (call $sink (local.get $s))
      (local.set $i (i32.add (local.get $i) (i32.const 1)))
      (br_if $l (i32.lt_u (local.get $i) (local.get $n)))))
  ;; a JS string copied into a fresh i16 array, as text coming from the DOM would be
  (func (export "fromJS") (param $s externref) (param $n i32) (result i32)
    (local $i i32) (local $a (ref null $chars)) (local $total i32)
    (loop $l
      (local.set $a (array.new_default $chars (call $length (local.get $s))))
      (local.set $total (i32.add (local.get $total) (call $intoArray (local.get $s) (local.get $a) (i32.const 0))))
      (local.set $i (i32.add (local.get $i) (i32.const 1)))
      (br_if $l (i32.lt_u (local.get $i) (local.get $n))))
    (local.get $total)))
