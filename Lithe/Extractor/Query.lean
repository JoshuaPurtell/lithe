import Lithe.Extractor.Extractor
import Lithe.Http.Request

namespace Lithe

structure Query (α : Type) where
  decode : Std.HashMap String (Array String) → Except String α

namespace Query

@[inline] def extract (q : Query α) : Extractor α :=
  fun ctx =>
    let params := Request.queryParams ctx.req
    match q.decode params with
    | .ok v => pure v
    | .error err => throw (HttpError.badRequest err)

@[inline] def param (name : String) (α : Type) [FromString α] : Extractor α :=
  fun ctx => do
    let params := Request.queryParams ctx.req
    match params.get? name with
    | some arr =>
        match arr[0]? with
        | some v =>
            match FromString.fromString? v with
            | some parsed => return parsed
            | none => throw (HttpError.badRequest s!"invalid query param '{name}'")
        | none => throw (HttpError.badRequest s!"missing query param '{name}'")
    | none => throw (HttpError.badRequest s!"missing query param '{name}'")

end Query

end Lithe
