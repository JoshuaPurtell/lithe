import Lithe.Prelude

namespace Lithe

namespace UrlEncoded

private def hexVal (c : Char) : Option Nat :=
  if c >= '0' && c <= '9' then
    some (c.toNat - '0'.toNat)
  else if c >= 'a' && c <= 'f' then
    some (10 + (c.toNat - 'a'.toNat))
  else if c >= 'A' && c <= 'F' then
    some (10 + (c.toNat - 'A'.toNat))
  else
    none

private partial def decodeBytes (s : String) : Except String ByteArray := do
  let rec loop (cs : List Char) (acc : ByteArray) : Except String ByteArray := do
    match cs with
    | [] => pure acc
    | '%' :: a :: b :: rest =>
        match hexVal a, hexVal b with
        | some hi, some lo =>
            let byte := UInt8.ofNat (hi * 16 + lo)
            loop rest (acc.push byte)
        | _, _ => throw "invalid percent-encoding"
    | '%' :: _ => throw "incomplete percent-encoding"
    | '+' :: rest =>
        loop rest (acc.push (UInt8.ofNat 32))
    | c :: rest =>
        let bytes := stringToBytes (String.singleton c)
        loop rest (acc ++ bytes)
  loop s.toList ByteArray.empty

def decode (s : String) : Except String String := do
  let bytes ← decodeBytes s
  match bytesToString? bytes with
  | some out => pure out
  | none => throw "invalid utf-8 after decoding"

private def addValue
    (m : Std.HashMap String (Array String))
    (k v : String) : Std.HashMap String (Array String) :=
  let existing := m.getD k #[]
  m.insert k (existing.push v)

def parse (s : String) : Except String (Std.HashMap String (Array String)) := do
  let parts := s.splitOn "&"
  let mut m : Std.HashMap String (Array String) := Std.HashMap.emptyWithCapacity
  for part in parts do
    if part.isEmpty then
      continue
    let kv := part.splitOn "="
    match kv with
    | [] => pure ()
    | k :: rest =>
        let v := if rest.isEmpty then "" else String.intercalate "=" rest
        let k' ← decode k
        let v' ← decode v
        m := addValue m k' v'
  pure m

end UrlEncoded

end Lithe
