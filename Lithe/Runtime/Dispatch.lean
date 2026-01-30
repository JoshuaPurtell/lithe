import Lithe.Router.Router
import Lithe.Router.Match
import Lithe.Core.Context
import Lithe.Core.Handler

namespace Lithe

private def findMatch (routes : List Route) (req : Request) : Option (Handler × Std.HashMap String String) :=
  match routes with
  | [] => none
  | route :: rest =>
      if route.method == req.method then
        match matchRoute route.pattern req.path with
        | some params => some (route.handler, params)
        | none => findMatch rest req
      else
        findMatch rest req

/-- Run a request through the router and middleware chain. -/
def dispatch (r : Router) (ctx : RequestCtx) : IO Response :=
  match findMatch r.routes.toList ctx.req with
  | some (h, params) =>
      Handler.run h (RequestCtx.withParams ctx params)
  | none =>
      Handler.run r.fallback ctx

end Lithe
