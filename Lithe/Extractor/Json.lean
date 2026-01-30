import Lithe.Extractor.Extractor
import Lithe.Http.Request
import Lithe.Validation

namespace Lithe

@[inline] def JsonBody (α : Type) [Lean.FromJson α] : Extractor α :=
  fun ctx => do
    let body ← ctx.req.readBodyAll
    let s ←
      match bytesToString? body with
      | some v => pure v
      | none => throw (HttpError.badRequest "invalid utf-8 body")
    let j ←
      match Lean.Json.parse s with
      | .ok v => pure v
      | .error err => throw (HttpError.badRequest err)
    match Lean.fromJson? (α := α) j with
    | .ok v => pure v
    | .error err => throw (HttpError.badRequest err)

@[inline] def JsonBodyValidated (α : Type) [Lean.FromJson α] [Validate α]
    (message : String := "validation failed")
    (status : UInt16 := 422) : Extractor α :=
  fun ctx => do
    let v ← JsonBody α ctx
    validateOrThrow v message status

end Lithe
