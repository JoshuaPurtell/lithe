import Std
import Init.Data.String.Modify
import Init.Data.String.TakeDrop
import Init.Data.String.Search
import Init.Data.List.ToArray
import Lean.Data.Json
import Lean.Data.Json.FromToJson
import Lean.Data.Json.Printer

namespace Lithe

@[inline] def bytesToString? (b : ByteArray) : Option String :=
  String.fromUTF8? b

@[inline] def bytesToString (b : ByteArray) : String :=
  match bytesToString? b with
  | some s => s
  | none => ""

@[inline] def stringToBytes (s : String) : ByteArray :=
  s.toUTF8

@[inline] def byteArrayToNatArray (b : ByteArray) : Array Nat :=
  (b.toList.map (fun u => u.toNat)).toArray

@[inline] def byteArrayOfNatArray (arr : Array Nat) : ByteArray :=
  (arr.toList.map UInt8.ofNat).toByteArray

end Lithe
