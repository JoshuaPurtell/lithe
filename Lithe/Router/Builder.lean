import Lithe.Router.Router
import Lithe.Core.Middleware

namespace Lithe

namespace Router

@[inline] def get (path : String) (h : Handler) (r : Router) : Router :=
  add Method.GET path h r

@[inline] def post (path : String) (h : Handler) (r : Router) : Router :=
  add Method.POST path h r

@[inline] def put (path : String) (h : Handler) (r : Router) : Router :=
  add Method.PUT path h r

@[inline] def patch (path : String) (h : Handler) (r : Router) : Router :=
  add Method.PATCH path h r

@[inline] def delete (path : String) (h : Handler) (r : Router) : Router :=
  add Method.DELETE path h r

@[inline] def options (path : String) (h : Handler) (r : Router) : Router :=
  add Method.OPTIONS path h r

@[inline] def head (path : String) (h : Handler) (r : Router) : Router :=
  add Method.HEAD path h r

@[inline] def nest (pref : String) (child : Router) (r : Router) : Router :=
  let parsed := RoutePattern.parse pref
  let adjusted := child.routes.map (fun route =>
    { route with pattern := RoutePattern.prepend parsed route.pattern }
  )
  { r with routes := r.routes ++ adjusted }

@[inline] def withFallback (h : Handler) (r : Router) : Router :=
  { r with fallback := h }

@[inline] def withMiddleware (m : Middleware) (r : Router) : Router :=
  { routes := r.routes.map (fun route => { route with handler := m route.handler })
  , fallback := m r.fallback
  }

end Router

end Lithe
