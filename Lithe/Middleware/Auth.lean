import Lithe.Core.Middleware
import Lithe.Core.Auth
import Lithe.Core.Error
import Lithe.Core.Context
import Lithe.Http.Request
import Lithe.Http.Cookie
import Init.Dynamic

namespace Lithe

structure AuthConfig where
  stateKey : String := authStateKey
  onMissing : HttpError := { status := 401, code := "unauthorized", message := "missing credentials" }
  onInvalid : HttpError := { status := 403, code := "forbidden", message := "invalid credentials" }

abbrev AuthValidator := RequestCtx → ExceptT HttpError IO AuthInfo

/--
Attach authentication info to the request context.
- The validator should throw on failures.
- The auth info is stored in ctx.state under `stateKey`.
-/
def auth (validate : AuthValidator) (cfg : AuthConfig := {}) : Middleware :=
  fun h ctx => do
    let info ← validate ctx
    let ctx := { ctx with state := ctx.state.insert cfg.stateKey (Dynamic.mk info) }
    h ctx

private def parseBearerToken? (value : String) : Option String :=
  let v := value.trimAscii.toString
  let lower := v.toLower
  if lower.startsWith "bearer " then
    some ((v.drop 7).trimAscii.toString)
  else
    none

/--
API key auth using a validator that returns AuthInfo.
- Reads the key from `header` (default: x-api-key).
-/
def apiKeyWith
    (validate : String → ExceptT HttpError IO AuthInfo)
    (header : String := "x-api-key")
    (cfg : AuthConfig := {}) : Middleware :=
  auth (fun ctx =>
    match ctx.req.header? header with
    | none => throw cfg.onMissing
    | some key => validate key
  ) cfg

/--
API key auth using a boolean validator.
- Returns AuthInfo.apiKey on success.
-/
def apiKey
    (isValid : String → IO Bool)
    (header : String := "x-api-key")
    (cfg : AuthConfig := {}) : Middleware :=
  apiKeyWith (fun key => do
    let ok ← isValid key
    if ok then
      pure (AuthInfo.apiKey key)
    else
      throw cfg.onInvalid
  ) header cfg

/--
Bearer auth using a validator that returns AuthInfo.
- Reads token from Authorization: Bearer <token>.
-/
def bearerWith
    (validate : String → ExceptT HttpError IO AuthInfo)
    (cfg : AuthConfig := {}) : Middleware :=
  auth (fun ctx =>
    match ctx.req.header? "authorization" with
    | none => throw cfg.onMissing
    | some value =>
        match parseBearerToken? value with
        | none => throw cfg.onInvalid
        | some token => validate token
  ) cfg

/--
Bearer auth using a boolean validator.
- Returns AuthInfo.bearer on success.
-/
def bearer
    (isValid : String → IO Bool)
    (cfg : AuthConfig := {}) : Middleware :=
  bearerWith (fun token => do
    let ok ← isValid token
    if ok then
      pure (AuthInfo.bearer token)
    else
      throw cfg.onInvalid
  ) cfg

/--
JWT auth helper (alias of bearer).
- Provide a validator that verifies and returns AuthInfo.
-/
def jwtWith
    (validate : String → ExceptT HttpError IO AuthInfo)
    (cfg : AuthConfig := {}) : Middleware :=
  bearerWith validate cfg

/--
JWT auth helper (alias of bearer).
-/
def jwt
    (isValid : String → IO Bool)
    (cfg : AuthConfig := {}) : Middleware :=
  bearer isValid cfg

/--
Session auth using a validator that returns AuthInfo.
- Reads the session id from the cookie named `cookieName`.
-/
def sessionWith
    (cookieName : String)
    (validate : String → ExceptT HttpError IO AuthInfo)
    (cfg : AuthConfig := {}) : Middleware :=
  auth (fun ctx =>
    match ctx.req.header? "cookie" with
    | none => throw cfg.onMissing
    | some header =>
        match cookieValue? header cookieName with
        | none => throw cfg.onMissing
        | some token => validate token
  ) cfg

/--
Session auth using a boolean validator.
- Returns AuthInfo.session on success.
-/
def session
    (cookieName : String)
    (isValid : String → IO Bool)
    (cfg : AuthConfig := {}) : Middleware :=
  sessionWith cookieName (fun token => do
    let ok ← isValid token
    if ok then
      pure (AuthInfo.session token)
    else
      throw cfg.onInvalid
  ) cfg

end Lithe
