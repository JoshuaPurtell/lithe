import Lithe.App

namespace Lithe

initialize appRegistryRef : IO.Ref (Std.HashMap String (IO App)) ←
  IO.mkRef (Std.HashMap.emptyWithCapacity)

@[inline] def registerApp (name : String) (mk : IO App) : IO Unit := do
  appRegistryRef.modify (fun m => m.insert name mk)

@[inline] def getApp (name : String) : IO App := do
  let m ← appRegistryRef.get
  match m.get? name with
  | some mk => mk
  | none => throw (IO.userError s!"unknown app '{name}'")

@[inline] def listApps : IO (Array String) := do
  let m ← appRegistryRef.get
  pure (m.keys.toArray)

end Lithe
