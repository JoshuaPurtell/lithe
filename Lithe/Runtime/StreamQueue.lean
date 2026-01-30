import Lithe.Prelude

namespace Lithe

private structure ByteQueue where
  front : List ByteArray
  back  : List ByteArray

namespace ByteQueue

@[inline] def empty : ByteQueue := { front := [], back := [] }

@[inline] def isEmpty (q : ByteQueue) : Bool :=
  q.front.isEmpty && q.back.isEmpty

@[inline] def push (q : ByteQueue) (b : ByteArray) : ByteQueue :=
  { q with back := b :: q.back }

@[inline] def pop? (q : ByteQueue) : Option (ByteArray × ByteQueue) :=
  match q.front with
  | x :: xs => some (x, { q with front := xs })
  | [] =>
      match q.back.reverse with
      | [] => none
      | x :: xs => some (x, { front := xs, back := [] })

end ByteQueue

structure StreamQueue where
  capacity : Nat
  buf      : IO.Ref ByteQueue
  bytes    : IO.Ref Nat
  closed   : IO.Ref Bool

namespace StreamQueue

@[inline] def new (capacity : Nat) : IO StreamQueue := do
  let buf ← IO.mkRef ByteQueue.empty
  let bytes ← IO.mkRef 0
  let closed ← IO.mkRef false
  pure { capacity := capacity, buf := buf, bytes := bytes, closed := closed }

@[inline] def isClosed (q : StreamQueue) : IO Bool :=
  q.closed.get

@[inline] def close (q : StreamQueue) : IO Unit :=
  q.closed.set true

@[inline] def push (q : StreamQueue) (chunk : ByteArray) : IO Bool := do
  let isClosed ← q.closed.get
  if isClosed then
    pure false
  else
    let sz ← q.bytes.get
    let next := sz + chunk.size
    if next > q.capacity then
      pure false
    else
      q.buf.modify (fun bq => ByteQueue.push bq chunk)
      q.bytes.set next
      pure true

@[inline] def pop? (q : StreamQueue) : IO (Option ByteArray) := do
  let bq ← q.buf.get
  match ByteQueue.pop? bq with
  | none => pure none
  | some (chunk, bq') =>
      q.buf.set bq'
      let sz ← q.bytes.get
      let next := if sz >= chunk.size then sz - chunk.size else 0
      q.bytes.set next
      pure (some chunk)

@[inline] def sizeBytes (q : StreamQueue) : IO Nat :=
  q.bytes.get

@[inline] def isEmpty (q : StreamQueue) : IO Bool := do
  let bq ← q.buf.get
  pure (ByteQueue.isEmpty bq)

end StreamQueue

end Lithe
