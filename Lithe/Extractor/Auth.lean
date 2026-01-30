import Lithe.Extractor.Extractor
import Lithe.Core.Auth
import Lithe.Core.Error
import Init.Dynamic

namespace Lithe
namespace Extractor

@[inline] def auth? (key : String := authStateKey) : Extractor (Option AuthInfo) :=
  fun ctx => do
    match ctx.state.get? key with
    | none => return none
    | some dyn =>
        match Dynamic.get? AuthInfo dyn with
        | some v => return some v
        | none => throw (HttpError.internal s!"auth state key '{key}' has wrong type")

@[inline] def auth (key : String := authStateKey)
    (onMissing : HttpError := { status := 401, code := "unauthorized", message := "missing credentials" })
    : Extractor AuthInfo :=
  fun ctx => do
    match (← auth? key ctx) with
    | some v => return v
    | none => throw onMissing

@[inline] def Auth (key : String := authStateKey)
    (onMissing : HttpError := { status := 401, code := "unauthorized", message := "missing credentials" })
    : Extractor AuthInfo :=
  auth key onMissing

@[inline] def requireScope (scope : String)
    (key : String := authStateKey)
    (onMissing : HttpError := { status := 401, code := "unauthorized", message := "missing credentials" })
    (onForbidden : HttpError := { status := 403, code := "forbidden", message := "missing scope" })
    : Extractor AuthInfo :=
  fun ctx => do
    let info ← auth key onMissing ctx
    if info.scopes.contains scope then
      return info
    else
      throw onForbidden

@[inline] def requireRole (role : String)
    (key : String := authStateKey)
    (onMissing : HttpError := { status := 401, code := "unauthorized", message := "missing credentials" })
    (onForbidden : HttpError := { status := 403, code := "forbidden", message := "missing role" })
    : Extractor AuthInfo :=
  fun ctx => do
    let info ← auth key onMissing ctx
    if info.roles.contains role then
      return info
    else
      throw onForbidden

end Extractor
end Lithe
