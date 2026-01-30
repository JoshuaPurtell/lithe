import Lithe.Prelude

namespace Lithe

inductive Method
| GET | POST | PUT | PATCH | DELETE | OPTIONS | HEAD
  deriving BEq, DecidableEq, Repr

namespace Method

def toString : Method → String
  | GET => "GET"
  | POST => "POST"
  | PUT => "PUT"
  | PATCH => "PATCH"
  | DELETE => "DELETE"
  | OPTIONS => "OPTIONS"
  | HEAD => "HEAD"

@[inline] def ofString? (s : String) : Option Method :=
  match s.trimAscii.toString.toUpper with
  | "GET" => some GET
  | "POST" => some POST
  | "PUT" => some PUT
  | "PATCH" => some PATCH
  | "DELETE" => some DELETE
  | "OPTIONS" => some OPTIONS
  | "HEAD" => some HEAD
  | _ => none

@[inline] def toUInt8 : Method → UInt8
  | GET => 0
  | POST => 1
  | PUT => 2
  | PATCH => 3
  | DELETE => 4
  | OPTIONS => 5
  | HEAD => 6

@[inline] def ofUInt8? (n : UInt8) : Option Method :=
  match n.toNat with
  | 0 => some GET
  | 1 => some POST
  | 2 => some PUT
  | 3 => some PATCH
  | 4 => some DELETE
  | 5 => some OPTIONS
  | 6 => some HEAD
  | _ => none

end Method

instance : ToString Method := ⟨Method.toString⟩

instance : Lean.ToJson Method := ⟨fun m => (Method.toString m : String)⟩

instance : Lean.FromJson Method := ⟨fun j => do
  let s ← j.getStr?
  match Method.ofString? s with
  | some m => pure m
  | none => throw s!"unknown method '{s}'"
⟩

end Lithe
