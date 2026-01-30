import Lithe.Router.Router
import Lithe.Router.Builder
import Lithe.Runtime.Dispatch
import Lithe.Core.Context
import Lithe.Core.Middleware
import Lithe.Http.Request
import Lithe.Http.Response
import Init.Dynamic

namespace Lithe

structure App where
  router : Router
  state  : Std.HashMap String Dynamic
  middleware : Array Middleware

namespace App

@[inline] def empty : App :=
  { router := Router.empty
  , state := Std.HashMap.emptyWithCapacity
  , middleware := #[]
  }

@[inline] def withMiddleware (m : Middleware) (app : App) : App :=
  { app with middleware := app.middleware.push m }

@[inline] def withMiddlewareAll (ms : Array Middleware) (app : App) : App :=
  { app with middleware := app.middleware ++ ms }

@[inline] def use (m : Middleware) (app : App) : App :=
  withMiddleware m app

@[inline] def useAll (ms : Array Middleware) (app : App) : App :=
  withMiddlewareAll ms app

@[inline] def withState (key : String) (val : α) [TypeName α] (app : App) : App :=
  let st := app.state.insert key (Dynamic.mk val)
  { app with state := st }

@[inline] def get (path : String) (h : Handler) (app : App) : App :=
  { app with router := Router.get path h app.router }

@[inline] def post (path : String) (h : Handler) (app : App) : App :=
  { app with router := Router.post path h app.router }

@[inline] def put (path : String) (h : Handler) (app : App) : App :=
  { app with router := Router.put path h app.router }

@[inline] def patch (path : String) (h : Handler) (app : App) : App :=
  { app with router := Router.patch path h app.router }

@[inline] def delete (path : String) (h : Handler) (app : App) : App :=
  { app with router := Router.delete path h app.router }

@[inline] def options (path : String) (h : Handler) (app : App) : App :=
  { app with router := Router.options path h app.router }

@[inline] def head (path : String) (h : Handler) (app : App) : App :=
  { app with router := Router.head path h app.router }

@[inline] def nest (pref : String) (child : Router) (app : App) : App :=
  { app with router := Router.nest pref child app.router }

@[inline] def fallback (h : Handler) (app : App) : App :=
  { app with router := Router.withFallback h app.router }

private def applyMiddleware (r : Router) (mws : Array Middleware) : Router :=
  mws.foldl (init := r) (fun acc m => Router.withMiddleware m acc)

@[inline] def toRouter (app : App) : Router :=
  applyMiddleware app.router app.middleware

@[inline] def handle (app : App) (req : Request) : IO Response :=
  let ctx := RequestCtx.ofRequest req app.state
  dispatch (toRouter app) ctx

end App

end Lithe
