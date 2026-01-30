import Lithe.Prelude

namespace Lithe

namespace Json

@[inline] def encode (j : Lean.Json) : ByteArray :=
  stringToBytes (Lean.Json.compress j)

@[inline] def decode (b : ByteArray) : Except String Lean.Json := do
  let s ←
    match bytesToString? b with
    | some v => pure v
    | none => throw "invalid utf-8"
  Lean.Json.parse s

end Json

end Lithe
