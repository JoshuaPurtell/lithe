import Lithe.Prelude

namespace Lithe

structure HttpError where
  status  : UInt16
  code    : String
  message : String
  details : Option Lean.Json := none

namespace HttpError

@[inline] def notFound (msg := "Not Found") : HttpError :=
  { status := 404, code := "not_found", message := msg }

@[inline] def badRequest (msg := "Bad Request") : HttpError :=
  { status := 400, code := "bad_request", message := msg }

@[inline] def internal (msg := "Internal Server Error") : HttpError :=
  { status := 500, code := "internal_error", message := msg }

@[inline] def toJson (e : HttpError) : Lean.Json :=
  let base : List (String × Lean.Json) :=
    [ ("status", toString e.status)
    , ("code", e.code)
    , ("message", e.message)
    ]
  match e.details with
  | some d => Lean.Json.mkObj (base ++ [("details", d)])
  | none => Lean.Json.mkObj base

end HttpError

end Lithe
