import Lithe.Core.Context
import Lithe.Core.Error

namespace Lithe

class FromString (α : Type) where
  fromString? : String → Option α

instance : FromString String := ⟨fun s => some s⟩
instance : FromString Nat := ⟨String.toNat?⟩
instance : FromString Int := ⟨String.toInt?⟩
instance : FromString Bool := ⟨fun s =>
  match s.trimAscii.toString.toLower with
  | "true" => some true
  | "false" => some false
  | _ => none
⟩

abbrev Extractor (α : Type) := RequestCtx → ExceptT HttpError IO α

namespace Extractor

@[inline] def map (f : α → β) (e : Extractor α) : Extractor β :=
  fun ctx => do
    let a ← e ctx
    pure (f a)

@[inline] def bind (e : Extractor α) (f : α → Extractor β) : Extractor β :=
  fun ctx => do
    let a ← e ctx
    f a ctx

@[inline] def pure (a : α) : Extractor α :=
  fun _ => do
    return a

end Extractor

end Lithe
