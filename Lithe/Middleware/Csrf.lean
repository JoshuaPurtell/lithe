import Lithe.Core.Middleware
import Lithe.Core.Error
import Lithe.Core.Auth
import Lithe.Core.Context
import Lithe.Http.Method
import Lithe.Http.Cookie
import Init.Dynamic

namespace Lithe

structure CsrfConfig where
  headerName : String := "x-csrf-token"
  cookieName : String := "csrf_token"
  unsafeMethods : Array Method := #[Method.POST, Method.PUT, Method.PATCH, Method.DELETE]
  authStateKey : String := authStateKey
  onlyIfSession : Bool := true
  onMissing : HttpError := { status := 403, code := "csrf_missing", message := "missing csrf token" }
  onInvalid : HttpError := { status := 403, code := "csrf_invalid", message := "csrf token invalid" }

private def shouldCheck (ctx : RequestCtx) (cfg : CsrfConfig) : ExceptT HttpError IO Bool := do
  if !cfg.unsafeMethods.contains ctx.req.method then
    return false
  if cfg.onlyIfSession then
    match ctx.state.get? cfg.authStateKey with
    | none => return false
    | some dyn =>
        match Dynamic.get? AuthInfo dyn with
        | none => throw (HttpError.internal s!"auth state key '{cfg.authStateKey}' has wrong type")
        | some info => return (info.scheme == "session")
  else
    return true

/--
Double-submit cookie CSRF protection.
- Compares the CSRF header with a cookie value.
- By default, only applies when `AuthInfo.scheme == "session"`.
-/
def csrfDoubleSubmit (cfg : CsrfConfig := {}) : Middleware :=
  fun h ctx => do
    let check ← shouldCheck ctx cfg
    if !check then
      h ctx
    else
      let headerToken? := ctx.req.header? cfg.headerName
      let cookieToken? := requestCookie? ctx.req cfg.cookieName
      match headerToken?, cookieToken? with
      | some headerToken, some cookieToken =>
          if headerToken == cookieToken then
            h ctx
          else
            throw cfg.onInvalid
      | _, _ =>
          throw cfg.onMissing

@[inline] def csrf (cfg : CsrfConfig := {}) : Middleware :=
  csrfDoubleSubmit cfg

end Lithe
