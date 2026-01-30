import Lithe.Prelude
import Lithe.Core.Error

namespace Lithe

structure ValidationError where
  path : String
  message : String
  code : String := "invalid"

namespace ValidationError

@[inline] def toJson (e : ValidationError) : Lean.Json :=
  Lean.Json.mkObj
    [ ("path", e.path)
    , ("message", e.message)
    , ("code", e.code)
    ]

end ValidationError

class Validate (α : Type) where
  validate : α → Array ValidationError

namespace Validate

@[inline] def ok {α} [Validate α] (value : α) : Bool :=
  (Validate.validate value).isEmpty

end Validate

@[inline] def validationDetails (errors : Array ValidationError) : Lean.Json :=
  Lean.Json.arr (errors.map ValidationError.toJson)

@[inline] def validationError
    (errors : Array ValidationError)
    (message : String := "validation failed")
    (status : UInt16 := 422)
    : HttpError :=
  { status := status
  , code := "validation_error"
  , message := message
  , details := some (validationDetails errors)
  }

/--
Validate a value and throw a structured HttpError if invalid.
-/
@[inline] def validateOrThrow
    (value : α)
    [Validate α]
    (message : String := "validation failed")
    (status : UInt16 := 422)
    : ExceptT HttpError IO α := do
  let errors := Validate.validate value
  if errors.isEmpty then
    pure value
  else
    throw (validationError errors message status)

end Lithe
