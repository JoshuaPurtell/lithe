import Lithe.Prelude
import Lithe.Runtime.StreamQueue
import Lithe.Core.CancelToken
import Lithe.Http.Response

namespace Lithe

structure StreamSession where
  task      : Task (Except IO.Error Response)
  cancel    : CancelToken
  reqQueue  : StreamQueue
  respRef   : IO.Ref (Option Response)
  respQueue : IO.Ref (Option StreamQueue)
  headSent  : IO.Ref Bool

initialize streamRef : IO.Ref (Std.HashMap UInt64 StreamSession) ←
  IO.mkRef Std.HashMap.emptyWithCapacity

initialize nextStreamIdRef : IO.Ref UInt64 ← IO.mkRef 1

@[inline] def registerStream (sess : StreamSession) : IO UInt64 := do
  let id ← nextStreamIdRef.get
  nextStreamIdRef.set (id + 1)
  streamRef.modify (fun m => m.insert id sess)
  pure id

@[inline] def getStream? (id : UInt64) : IO (Option StreamSession) := do
  let m ← streamRef.get
  pure (m.get? id)

@[inline] def removeStream (id : UInt64) : IO Unit :=
  streamRef.modify (fun m => m.erase id)

@[inline] def cancelStream (id : UInt64) : IO Unit := do
  let sess? ← getStream? id
  match sess? with
  | none => pure ()
  | some sess =>
      sess.cancel.cancel
      StreamQueue.close sess.reqQueue
      let respQ? ← sess.respQueue.get
      match respQ? with
      | none => pure ()
      | some q => StreamQueue.close q
      IO.cancel sess.task
      removeStream id

end Lithe
