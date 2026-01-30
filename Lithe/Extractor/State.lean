import Lithe.Extractor.Extractor
import Init.Dynamic

namespace Lithe
namespace Extractor

@[inline] def state (key : String) (α : Type) [TypeName α] : Extractor α :=
  fun ctx => do
    match ctx.state.get? key with
    | some dyn =>
        match Dynamic.get? α dyn with
        | some v => return v
        | none => throw (HttpError.internal s!"state key '{key}' has wrong type")
    | none => throw (HttpError.internal s!"state key '{key}' missing")

@[inline] def State (key : String) (α : Type) [TypeName α] : Extractor α :=
  state key α

end Extractor
end Lithe
