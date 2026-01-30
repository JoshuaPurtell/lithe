import Lithe.Prelude
import Lithe.Runtime.StreamQueue
import Lithe.Core.CancelToken

namespace Lithe

structure WSSession where
  inQ : StreamQueue
  outQ : StreamQueue
  cancel : CancelToken
  taskRef : IO.Ref (Option (Task (Except IO.Error Unit)))

def wsPushClosed : UInt64 := 0
def wsPushOk : UInt64 := 1
def wsPushFull : UInt64 := 2

initialize wsRef : IO.Ref (Std.HashMap UInt64 WSSession) ←
  IO.mkRef Std.HashMap.emptyWithCapacity

initialize nextWsIdRef : IO.Ref UInt64 ← IO.mkRef 1

@[inline] def registerWS (sess : WSSession) : IO UInt64 := do
  let id ← nextWsIdRef.get
  nextWsIdRef.set (id + 1)
  wsRef.modify (fun m => m.insert id sess)
  pure id

@[inline] def getWS? (id : UInt64) : IO (Option WSSession) := do
  let m ← wsRef.get
  pure (m.get? id)

@[inline] def removeWS (id : UInt64) : IO Unit :=
  wsRef.modify (fun m => m.erase id)

@[inline] def setWSTask (id : UInt64) (task : Task (Except IO.Error Unit)) : IO Unit := do
  let sess? ← getWS? id
  match sess? with
  | none => pure ()
  | some sess => sess.taskRef.set (some task)

@[inline] def finishWS (id : UInt64) : IO Unit := do
  let sess? ← getWS? id
  match sess? with
  | none => pure ()
  | some sess =>
      StreamQueue.close sess.inQ
      StreamQueue.close sess.outQ
      removeWS id

@[inline] def closeWS (id : UInt64) : IO Unit := do
  let sess? ← getWS? id
  match sess? with
  | none => pure ()
  | some sess =>
      sess.cancel.cancel
      StreamQueue.close sess.inQ
      StreamQueue.close sess.outQ
      let task? ← sess.taskRef.get
      match task? with
      | none => pure ()
      | some task => IO.cancel task
      removeWS id

@[inline] def wsPushIn (id : UInt64) (msg : ByteArray) : IO UInt64 := do
  let sess? ← getWS? id
  match sess? with
  | none => pure wsPushClosed
  | some sess =>
      let ok ← StreamQueue.push sess.inQ msg
      if ok then
        pure wsPushOk
      else
        let closed ← StreamQueue.isClosed sess.inQ
        if closed then
          pure wsPushClosed
        else
          pure wsPushFull

@[inline] def wsPopOut (id : UInt64) : IO ByteArray := do
  let sess? ← getWS? id
  match sess? with
  | none => pure ByteArray.empty
  | some sess =>
      match (← StreamQueue.pop? sess.outQ) with
      | none => pure ByteArray.empty
      | some msg => pure msg

end Lithe
