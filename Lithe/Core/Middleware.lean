import Lithe.Core.Handler

namespace Lithe

abbrev Middleware := Handler → Handler

namespace Middleware

@[inline] def compose (m₁ m₂ : Middleware) : Middleware :=
  fun h => m₁ (m₂ h)

@[inline] def identity : Middleware :=
  fun h => h

@[inline] def stack (mws : Array Middleware) : Middleware :=
  fun h => mws.foldr (fun m acc => m acc) h

@[inline] def stackList (mws : List Middleware) : Middleware :=
  fun h => mws.foldr (fun m acc => m acc) h

end Middleware

end Lithe
