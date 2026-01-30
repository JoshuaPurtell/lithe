import Lithe.Router.Router
import Init.Dynamic

namespace Lithe

structure AppInstance where
  router : Router
  state  : Std.HashMap String Dynamic

initialize registryRef : IO.Ref (Std.HashMap UInt64 AppInstance) ← IO.mkRef Std.HashMap.emptyWithCapacity
initialize nextIdRef : IO.Ref UInt64 ← IO.mkRef 1

@[inline] def newInstance (router : Router) (state : Std.HashMap String Dynamic := Std.HashMap.emptyWithCapacity) : IO UInt64 := do
  let id ← nextIdRef.get
  nextIdRef.set (id + 1)
  registryRef.modify (fun m => m.insert id { router := router, state := state })
  pure id

@[inline] def getInstance (id : UInt64) : IO AppInstance := do
  let m ← registryRef.get
  match m.get? id with
  | some inst => pure inst
  | none => throw (IO.userError s!"unknown app id {id}")

@[inline] def freeInstance (id : UInt64) : IO Unit := do
  registryRef.modify (fun m => m.erase id)

end Lithe
