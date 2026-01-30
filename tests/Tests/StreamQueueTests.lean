import Lithe.Runtime.StreamQueue
import Tests.Util

def testStreamQueueOrder : IO Unit := do
  let q ← Lithe.StreamQueue.new 10
  let ok1 ← Lithe.StreamQueue.push q (Lithe.stringToBytes "a")
  let ok2 ← Lithe.StreamQueue.push q (Lithe.stringToBytes "bb")
  assert ok1 "push 1 should succeed"
  assert ok2 "push 2 should succeed"
  let sz ← Lithe.StreamQueue.sizeBytes q
  assertEqNat sz 3 "queue size"

  let c1 ← Lithe.StreamQueue.pop? q
  match c1 with
  | some chunk => assertEqBytes chunk (Lithe.stringToBytes "a") "queue chunk 1"
  | none => throw (IO.userError "missing first chunk")

  let c2 ← Lithe.StreamQueue.pop? q
  match c2 with
  | some chunk => assertEqBytes chunk (Lithe.stringToBytes "bb") "queue chunk 2"
  | none => throw (IO.userError "missing second chunk")

  let c3 ← Lithe.StreamQueue.pop? q
  match c3 with
  | none => pure ()
  | some _ => throw (IO.userError "expected empty queue")

def testStreamQueueCapacity : IO Unit := do
  let q ← Lithe.StreamQueue.new 3
  let ok1 ← Lithe.StreamQueue.push q (Lithe.stringToBytes "aa")
  let ok2 ← Lithe.StreamQueue.push q (Lithe.stringToBytes "bb")
  assert ok1 "push within capacity should succeed"
  assert (!ok2) "push over capacity should fail"

  let _ ← Lithe.StreamQueue.pop? q
  let ok3 ← Lithe.StreamQueue.push q (Lithe.stringToBytes "bb")
  assert ok3 "push after pop should succeed"

def testStreamQueueClose : IO Unit := do
  let q ← Lithe.StreamQueue.new 4
  let ok1 ← Lithe.StreamQueue.push q (Lithe.stringToBytes "a")
  assert ok1 "push before close should succeed"
  Lithe.StreamQueue.close q
  let ok2 ← Lithe.StreamQueue.push q (Lithe.stringToBytes "b")
  assert (!ok2) "push after close should fail"
  let closed ← Lithe.StreamQueue.isClosed q
  assert closed "queue should be closed"
