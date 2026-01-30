import Lithe.Prelude
import Lithe.Core.Error
import Lithe.Core.CancelToken
import Lithe.Runtime.StreamQueue
import Init.System.IO

namespace Lithe

structure BodyStream where
  next : ExceptT HttpError IO (Option ByteArray)

structure BodyWriter where
  push  : ByteArray → ExceptT HttpError IO Bool
  close : ExceptT HttpError IO Unit

private def deadlineExceeded (deadline : Option Nat) : IO Bool := do
  match deadline with
  | none => pure false
  | some d =>
      let now ← IO.monoNanosNow
      pure (now > d)

namespace BodyStream

@[inline] def empty : BodyStream :=
  { next := pure none }

private def readChunk (h : IO.FS.Handle) (n : Nat) : ExceptT HttpError IO ByteArray :=
  ExceptT.mk do
    try
      let chunk ← h.read (USize.ofNat n)
      pure (Except.ok chunk)
    catch e =>
      pure (Except.error { status := 500, code := "io_error", message := s!"file read error: {e}" })

private partial def nextFileRange
    (handleRef : IO.Ref (Option IO.FS.Handle))
    (skipRef : IO.Ref Nat)
    (remainingRef : IO.Ref Nat)
    (chunkSize : Nat) : ExceptT HttpError IO (Option ByteArray) := do
  match (← handleRef.get) with
  | none => pure none
  | some h =>
      let skip ← skipRef.get
      if skip > 0 then
        let toRead := Nat.min skip chunkSize
        let chunk ← readChunk h toRead
        if chunk.isEmpty then
          handleRef.set none
          pure none
        else
          skipRef.set (skip - chunk.size)
          nextFileRange handleRef skipRef remainingRef chunkSize
      else
        let remaining ← remainingRef.get
        if remaining = 0 then
          handleRef.set none
          pure none
        else
          let toRead := Nat.min remaining chunkSize
          let chunk ← readChunk h toRead
          if chunk.isEmpty then
            handleRef.set none
            pure none
          else
            remainingRef.set (remaining - chunk.size)
            pure (some chunk)

@[inline] def ofBytes (bytes : ByteArray) : IO BodyStream := do
  let ref ← IO.mkRef (some bytes)
  pure {
    next := do
      let cur ← ref.get
      match cur with
      | none => pure none
      | some b =>
          ref.set none
          pure (some b)
  }

@[inline] def ofFile (path : System.FilePath) (chunkSize : Nat := 65536) : IO BodyStream := do
  let handle ← IO.FS.Handle.mk path .read
  let handleRef ← IO.mkRef (some handle)
  let next : ExceptT HttpError IO (Option ByteArray) :=
    ExceptT.mk do
      match (← handleRef.get) with
      | none => pure (Except.ok none)
      | some h =>
          let res := (readChunk h chunkSize)
          match (← res.run) with
          | .error err =>
              handleRef.set none
              pure (Except.error err)
          | .ok chunk =>
              if chunk.isEmpty then
                handleRef.set none
                pure (Except.ok none)
              else
                pure (Except.ok (some chunk))
  pure { next := next }

@[inline] def ofFileRange
    (path : System.FilePath)
    (start stop : Nat)
    (chunkSize : Nat := 65536) : IO BodyStream := do
  let handle ← IO.FS.Handle.mk path .read
  let handleRef ← IO.mkRef (some handle)
  let skipRef ← IO.mkRef start
  let remainingRef ← IO.mkRef (stop - start + 1)
  pure { next := nextFileRange handleRef skipRef remainingRef chunkSize }

@[inline] def prepend (bytes : ByteArray) (stream : BodyStream) : IO BodyStream := do
  if bytes.isEmpty then
    pure stream
  else
    let ref ← IO.mkRef (some bytes)
    pure {
      next := do
        let cur ← ref.get
        match cur with
        | some b =>
            ref.set none
            pure (some b)
        | none =>
            stream.next
    }

/--
Wrap a stream with cooperative cancellation and deadline checks.
- `onCancel` and `onTimeout` are raised when the token is canceled or deadline exceeded.
-/
@[inline] def withCancel
    (stream : BodyStream)
    (cancel : CancelToken)
    (deadline : Option Nat := none)
    (onCancel : HttpError := { status := 499, code := "canceled", message := "request canceled" })
    (onTimeout : HttpError := { status := 504, code := "timeout", message := "request timed out" })
    : BodyStream :=
  { next := do
      let canceled ← cancel.isCanceled
      if canceled then
        throw onCancel
      let expired ← deadlineExceeded deadline
      if expired then
        throw onTimeout
      stream.next
  }

partial def fromQueue (q : StreamQueue) (pollMs : Nat := 5) : BodyStream :=
  { next := do
      let rec loop : ExceptT HttpError IO (Option ByteArray) := do
        match (← q.pop?) with
        | some chunk => pure (some chunk)
        | none =>
            let closed ← q.isClosed
            if closed then
              pure none
            else
              IO.sleep (UInt32.ofNat pollMs)
              loop
      loop
  }

@[inline] def newQueuePair (capacity : Nat) (pollMs : Nat := 5) : IO (BodyStream × BodyWriter) := do
  let q ← StreamQueue.new capacity
  let stream := fromQueue q pollMs
  let writer : BodyWriter :=
    { push := fun chunk => do
        StreamQueue.push q chunk
    , close := StreamQueue.close q
    }
  pure (stream, writer)

end BodyStream

namespace BodyWriter

@[inline] def discard : BodyWriter :=
  { push := fun _ => pure false
  , close := pure ()
  }

/--
Wrap a writer with cooperative cancellation and deadline checks.
- `onCancel` and `onTimeout` are raised when the token is canceled or deadline exceeded.
-/
@[inline] def withCancel
    (writer : BodyWriter)
    (cancel : CancelToken)
    (deadline : Option Nat := none)
    (onCancel : HttpError := { status := 499, code := "canceled", message := "request canceled" })
    (onTimeout : HttpError := { status := 504, code := "timeout", message := "request timed out" })
    : BodyWriter :=
  { push := fun chunk => do
      let canceled ← cancel.isCanceled
      if canceled then
        throw onCancel
      let expired ← deadlineExceeded deadline
      if expired then
        throw onTimeout
      writer.push chunk
  , close := do
      let canceled ← cancel.isCanceled
      if canceled then
        throw onCancel
      let expired ← deadlineExceeded deadline
      if expired then
        throw onTimeout
      writer.close
  }

end BodyWriter

end Lithe
