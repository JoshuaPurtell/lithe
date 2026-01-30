import Lithe.Prelude

namespace Lithe

structure CancelToken where
  flag : IO.Ref Bool
  isNever : Bool := false

initialize cancelNeverRef : IO.Ref Bool ← IO.mkRef false

namespace CancelToken

@[inline] def never : CancelToken := { flag := cancelNeverRef, isNever := true }

@[inline] def new : IO CancelToken := do
  let ref ← IO.mkRef false
  pure { flag := ref, isNever := false }

@[inline] def cancel (t : CancelToken) : IO Unit :=
  t.flag.set true

@[inline] def isCanceled (t : CancelToken) : IO Bool :=
  t.flag.get

end CancelToken

end Lithe
