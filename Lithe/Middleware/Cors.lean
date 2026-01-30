import Lithe.Core.Middleware
import Lithe.Http.Response
import Lithe.Http.Request

namespace Lithe

structure CorsConfig where
  allowOrigin : String := "*"
  allowMethods : String := "GET, POST, PUT, PATCH, DELETE, OPTIONS"
  allowHeaders : String := "content-type, authorization"
  allowCredentials : Bool := false
  maxAgeSeconds : Nat := 86400

private def corsHeaders (cfg : CorsConfig) : Array (String × String) :=
  let creds := if cfg.allowCredentials then #[("access-control-allow-credentials", "true")] else #[]
  #[
    ("access-control-allow-origin", cfg.allowOrigin),
    ("access-control-allow-methods", cfg.allowMethods),
    ("access-control-allow-headers", cfg.allowHeaders),
    ("access-control-max-age", toString cfg.maxAgeSeconds)
  ] ++ creds

/--
Very small CORS middleware (non-preflight aware by default).
If the request method is OPTIONS, returns a 204 with CORS headers.
-/
def cors (cfg : CorsConfig := {}) : Middleware :=
  fun h ctx => do
    if ctx.req.method == Method.OPTIONS then
      let resp := Response.empty 204
      let resp := (corsHeaders cfg).foldl (fun r hv => Response.withHeader r hv.fst hv.snd) resp
      pure resp
    else
      let resp ← h ctx
      let resp := (corsHeaders cfg).foldl (fun r hv => Response.withHeader r hv.fst hv.snd) resp
      pure resp

end Lithe
