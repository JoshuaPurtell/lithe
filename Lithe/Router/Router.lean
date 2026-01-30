import Lithe.Router.Path
import Lithe.Core.Handler
import Lithe.Http.Method

namespace Lithe

structure Route where
  method  : Method
  pattern : RoutePattern
  handler : Handler

structure Router where
  routes   : Array Route
  fallback : Handler

namespace Router

@[inline] def defaultFallback : Handler :=
  fun _ => throw (HttpError.notFound "Not Found")

@[inline] def empty : Router :=
  { routes := #[], fallback := defaultFallback }

@[inline] def add (method : Method) (path : String) (h : Handler) (r : Router) : Router :=
  let pattern := RoutePattern.parse path
  { r with routes := r.routes.push { method := method, pattern := pattern, handler := h } }

end Router

end Lithe
