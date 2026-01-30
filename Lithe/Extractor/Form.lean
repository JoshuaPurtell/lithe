import Lithe.Extractor.Extractor
import Lithe.Http.Request
import Lithe.Http.UrlEncoded

namespace Lithe

structure Form (α : Type) where
  decode : Std.HashMap String (Array String) → Except String α

namespace Form

private def isFormContentType (ct : String) : Bool :=
  let lower := ct.trimAscii.toString.toLower
  lower.startsWith "application/x-www-form-urlencoded"

private def parseForm (ctx : RequestCtx) (limit : Option Nat) : ExceptT HttpError IO (Std.HashMap String (Array String)) := do
  match ctx.req.header? "content-type" with
  | some ct =>
      if !isFormContentType ct then
        throw { status := 415, code := "unsupported_media_type", message := "expected application/x-www-form-urlencoded" }
  | none => pure ()
  let body ← ctx.req.readBodyAll limit
  let s ←
    match bytesToString? body with
    | some v => pure v
    | none => throw (HttpError.badRequest "invalid utf-8 body")
  match UrlEncoded.parse s with
  | .ok params => pure params
  | .error err => throw (HttpError.badRequest err)

@[inline] def extract (f : Form α) (limit : Option Nat := none) : Extractor α :=
  fun ctx => do
    let params ← parseForm ctx limit
    match f.decode params with
    | .ok v => pure v
    | .error err => throw (HttpError.badRequest err)

@[inline] def params (limit : Option Nat := none) : Extractor (Std.HashMap String (Array String)) :=
  fun ctx => parseForm ctx limit

@[inline] def param (name : String) (α : Type) [FromString α] (limit : Option Nat := none) : Extractor α :=
  fun ctx => do
    let params ← parseForm ctx limit
    match params.get? name with
    | some arr =>
        match arr[0]? with
        | some v =>
            match FromString.fromString? v with
            | some parsed => return parsed
            | none => throw (HttpError.badRequest s!"invalid form field '{name}'")
        | none => throw (HttpError.badRequest s!"missing form field '{name}'")
    | none => throw (HttpError.badRequest s!"missing form field '{name}'")

end Form

end Lithe
