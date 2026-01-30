import Lithe.Prelude
import Lithe.Core.CancelToken

namespace Lithe

structure PendingRequest where
  task   : Task (Except IO.Error ByteArray)
  cancel : CancelToken

initialize pendingRef : IO.Ref (Std.HashMap UInt64 PendingRequest) ←
  IO.mkRef Std.HashMap.emptyWithCapacity

initialize nextReqIdRef : IO.Ref UInt64 ← IO.mkRef 1

@[inline] def registerPending (pending : PendingRequest) : IO UInt64 := do
  let id ← nextReqIdRef.get
  nextReqIdRef.set (id + 1)
  pendingRef.modify (fun m => m.insert id pending)
  pure id

@[inline] def getPending? (id : UInt64) : IO (Option PendingRequest) := do
  let m ← pendingRef.get
  pure (m.get? id)

@[inline] def removePending (id : UInt64) : IO Unit :=
  pendingRef.modify (fun m => m.erase id)

@[inline] def cancelPending (id : UInt64) : IO Unit := do
  let pending? ← getPending? id
  match pending? with
  | none => pure ()
  | some p =>
      p.cancel.cancel
      IO.cancel p.task
      removePending id

end Lithe
