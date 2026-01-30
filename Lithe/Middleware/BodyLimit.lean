import Lithe.Core.Middleware
import Lithe.Core.Error
import Lithe.Http.BodyStream

namespace Lithe

/--
Reject requests whose body exceeds the given byte limit.
-/
def bodyLimit (maxBytes : Nat)
    (onTooLarge : HttpError := { status := 413, code := "payload_too_large", message := "payload too large" })
    : Middleware :=
  fun h ctx => do
    let baseSize := ctx.req.body.size
    if baseSize > maxBytes then
      throw onTooLarge
    else
      match ctx.req.bodyStream with
      | none => h ctx
      | some stream => do
          let ref ← IO.mkRef baseSize
          let wrapped : BodyStream :=
            { next := do
                let chunk? ← stream.next
                match chunk? with
                | none => pure none
                | some chunk =>
                    let total ← ref.get
                    let next := total + chunk.size
                    if next > maxBytes then
                      throw onTooLarge
                    else
                      ref.set next
                      pure (some chunk)
            }
          let req := { ctx.req with bodyStream := some wrapped }
          let ctx := { ctx with req := req }
          h ctx

end Lithe
