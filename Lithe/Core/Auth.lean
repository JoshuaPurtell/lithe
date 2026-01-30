import Lithe.Prelude
import Lean.Data.Json

namespace Lithe

/--
Authentication information stored in the request context.
- `scheme` identifies the auth mechanism ("api_key", "bearer", "session").
- `token` holds the raw credential (API key, bearer token, session id).
- `subject` is an optional principal identifier.
- `scopes` carries optional scope strings.
- `claims` carries optional structured metadata (e.g., decoded JWT claims).
-/
structure AuthInfo where
  scheme  : String
  token   : String
  subject : Option String := none
  scopes  : Array String := #[]
  roles   : Array String := #[]
  claims  : Option Lean.Json := none
  deriving Inhabited, TypeName

@[inline] def authStateKey : String := "lithe.auth"

namespace AuthInfo

@[inline] def apiKey (key : String) (subject : Option String := none) : AuthInfo :=
  { scheme := "api_key", token := key, subject := subject }

@[inline] def bearer (token : String) (subject : Option String := none) : AuthInfo :=
  { scheme := "bearer", token := token, subject := subject }

@[inline] def session (token : String) (subject : Option String := none) : AuthInfo :=
  { scheme := "session", token := token, subject := subject }

@[inline] def withScopes (info : AuthInfo) (scopes : Array String) : AuthInfo :=
  { info with scopes := scopes }

@[inline] def withRoles (info : AuthInfo) (roles : Array String) : AuthInfo :=
  { info with roles := roles }

@[inline] def addScope (info : AuthInfo) (scope : String) : AuthInfo :=
  { info with scopes := info.scopes.push scope }

@[inline] def addRole (info : AuthInfo) (role : String) : AuthInfo :=
  { info with roles := info.roles.push role }

@[inline] def hasScope (info : AuthInfo) (scope : String) : Bool :=
  info.scopes.contains scope

@[inline] def hasRole (info : AuthInfo) (role : String) : Bool :=
  info.roles.contains role

@[inline] def hasAllScopes (info : AuthInfo) (scopes : Array String) : Bool :=
  scopes.toList.all (fun s => info.scopes.contains s)

@[inline] def hasAnyScope (info : AuthInfo) (scopes : Array String) : Bool :=
  scopes.toList.any (fun s => info.scopes.contains s)

@[inline] def hasAllRoles (info : AuthInfo) (roles : Array String) : Bool :=
  roles.toList.all (fun r => info.roles.contains r)

@[inline] def hasAnyRole (info : AuthInfo) (roles : Array String) : Bool :=
  roles.toList.any (fun r => info.roles.contains r)

end AuthInfo

end Lithe
