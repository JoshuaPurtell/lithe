import Lithe.Http.Response
import Lithe.Core.Error
import Lithe.Core.Context
import Lithe.Core.Handler

namespace Lithe

class ToResponse (α : Type) where
  toResponse : α → Response

instance : ToResponse Response := ⟨id⟩

instance : ToResponse HttpError := ⟨fun e =>
  (Response.json (HttpError.toJson e)).withStatus e.status
⟩

instance : ToResponse Status := ⟨Response.statusOnly⟩

instance : ToResponse Unit := ⟨fun _ => Response.empty 204⟩

instance : ToResponse String := ⟨Response.text⟩

instance : ToResponse ByteArray := ⟨fun b =>
  { status := Status.ok
  , headers := #[ ("content-type", "application/octet-stream") ]
  , body := b
  }
⟩

instance : ToResponse Lean.Json := ⟨Response.json⟩

instance [ToResponse α] : ToResponse (Status × α) := ⟨fun (st, v) =>
  (ToResponse.toResponse v).withStatusObj st
⟩

instance [ToResponse α] : ToResponse (UInt16 × α) := ⟨fun (code, v) =>
  (ToResponse.toResponse v).withStatus code
⟩

instance [ToResponse α] : ToResponse (Except HttpError α) := ⟨fun r =>
  match r with
  | .ok v => ToResponse.toResponse v
  | .error e => (Response.json (HttpError.toJson e)).withStatus e.status
⟩

namespace Handler

@[inline] def of (f : RequestCtx → IO α) [ToResponse α] : Handler :=
  fun ctx =>
    ExceptT.mk (m := IO) (ε := HttpError) (α := Response) <|
      (fun v => Except.ok (ToResponse.toResponse v)) <$> f ctx

end Handler

end Lithe
