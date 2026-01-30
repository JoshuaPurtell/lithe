import Lithe.Extractor.Extractor

namespace Lithe

structure Path (α : Type) where
  parse : Std.HashMap String String → Except String α

namespace Path

@[inline] def extract (p : Path α) : Extractor α :=
  fun ctx =>
    match p.parse ctx.params with
    | .ok v => pure v
    | .error err => throw (HttpError.badRequest err)

@[inline] def param (name : String) (α : Type) [FromString α] : Extractor α :=
  fun ctx =>
    match ctx.params.get? name with
    | some v =>
        match FromString.fromString? v with
        | some parsed => pure parsed
        | none => throw (HttpError.badRequest s!"invalid path param '{name}'")
    | none => throw (HttpError.badRequest s!"missing path param '{name}'")

end Path

end Lithe
