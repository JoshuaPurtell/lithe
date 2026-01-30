import Lithe.Extractor.Extractor
import Lithe.Http.Request

namespace Lithe
namespace Extractor

@[inline] def header (name : String) (α : Type) [FromString α] : Extractor α :=
  fun ctx => do
    match ctx.req.header? name with
    | some v =>
        match FromString.fromString? v with
        | some parsed => return parsed
        | none => throw (HttpError.badRequest s!"invalid header '{name}'")
    | none => throw (HttpError.badRequest s!"missing header '{name}'")

@[inline] def Header (name : String) (α : Type) [FromString α] : Extractor α :=
  header name α

end Extractor
end Lithe
