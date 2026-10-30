;; One-shot handlers three ways, for timing the mechanism warp would use.
;; A body performs `n` operations; each sends a number to the handler, which answers
;; with that number plus one, and the body sums the answers.
(module
  (type $body (func (param i32)))
  (type $k (cont $body))
  (tag $op (param i32) (result i32))

  ;; --- 1. Stack switching: the body suspends, the handler resumes it once. ---
  (global $n (mut i32) (i32.const 0))
  (global $sum (mut i32) (i32.const 0))
  (func $ssBody (param $first i32)
    (local $i i32) (local $acc i32)
    (loop $l
      (local.set $acc (i32.add (local.get $acc) (suspend $op (local.get $i))))
      (local.set $i (i32.add (local.get $i) (i32.const 1)))
      (br_if $l (i32.lt_u (local.get $i) (global.get $n))))
    (global.set $sum (local.get $acc)))
  (elem declare func $ssBody)
  (func (export "stackSwitching") (param $count i32) (result i32)
    (local $k (ref null $k)) (local $v i32) (local $x i32)
    (global.set $n (local.get $count))
    (local.set $k (cont.new $k (ref.func $ssBody)))
    (loop $l
      (block $handle (result i32 (ref $k))
        (resume $k (on $op $handle) (local.get $v) (local.get $k))
        (return (global.get $sum)))
      (local.set $k)
      (local.set $x)
      (local.set $v (i32.add (local.get $x) (i32.const 1)))
      (br $l))
    (unreachable))

  ;; --- 2. Continuation passing, one allocation per operation: the rest of the body is a
  ;; closure (code, index, sum) that the handler calls with its answer. ---
  (rec
    (type $kfn (func (param (ref $kst) i32) (result i32)))
    (type $kst (struct (field (ref $kfn)) (field i32) (field i32))))
  (func $cpsAfter (type $kfn) (param $k (ref $kst)) (param $v i32) (result i32)
    (local $i i32) (local $acc i32)
    (local.set $i (i32.add (struct.get $kst 1 (local.get $k)) (i32.const 1)))
    (local.set $acc (i32.add (struct.get $kst 2 (local.get $k)) (local.get $v)))
    (if (result i32) (i32.lt_u (local.get $i) (global.get $n))
      (then (return_call $cpsPerform (local.get $i) (local.get $acc)))
      (else (local.get $acc))))
  (elem declare func $cpsAfter)
  (func $cpsPerform (param $i i32) (param $acc i32) (result i32)
    (return_call $cpsHandle (local.get $i)
      (struct.new $kst (ref.func $cpsAfter) (local.get $i) (local.get $acc))))
  (func $cpsHandle (param $x i32) (param $k (ref $kst)) (result i32)
    (return_call_ref $kfn (local.get $k) (i32.add (local.get $x) (i32.const 1))
      (struct.get $kst 0 (local.get $k))))
  (func (export "cps1") (param $count i32) (result i32)
    (global.set $n (local.get $count))
    (call $cpsPerform (i32.const 0) (i32.const 0)))

  ;; --- 3. The same, with nine more small allocations per operation, about what warp's
  ;; shift (4), its Request and arguments, and the handler's re-handle (5) cost. ---
  (type $box (struct (field i32)))
  (global $sink (mut (ref null $box)) (ref.null $box))
  (func $cps10After (type $kfn) (param $k (ref $kst)) (param $v i32) (result i32)
    (local $i i32) (local $acc i32)
    (local.set $i (i32.add (struct.get $kst 1 (local.get $k)) (i32.const 1)))
    (local.set $acc (i32.add (struct.get $kst 2 (local.get $k)) (local.get $v)))
    (if (result i32) (i32.lt_u (local.get $i) (global.get $n))
      (then (return_call $cps10Perform (local.get $i) (local.get $acc)))
      (else (local.get $acc))))
  (elem declare func $cps10After)
  (func $cps10Perform (param $i i32) (param $acc i32) (result i32)
    (local $j i32)
    (loop $l
      (global.set $sink (struct.new $box (local.get $j)))
      (local.set $j (i32.add (local.get $j) (i32.const 1)))
      (br_if $l (i32.lt_u (local.get $j) (i32.const 9))))
    (return_call $cpsHandle (local.get $i)
      (struct.new $kst (ref.func $cps10After) (local.get $i) (local.get $acc))))
  (func (export "cps10") (param $count i32) (result i32)
    (global.set $n (local.get $count))
    (call $cps10Perform (i32.const 0) (i32.const 0))))
