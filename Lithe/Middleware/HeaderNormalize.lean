import Lithe.Core.Middleware
import Lithe.Http.Request
import Lithe.Http.Response

namespace Lithe

private def normalizeName (s : String) : String :=
  s.trimAscii.toString.toLower

/--
Lowercase and trim all request header names; response headers are untouched.
-/
def normalizeRequestHeaders : Middleware :=
  fun h ctx => do
    let headers := ctx.req.headers.map (fun (k, v) => (normalizeName k, v.trimAscii.toString))
    let req := { ctx.req with headers := headers }
    h { ctx with req := req }

/--
Lowercase and trim all response header names and values.
-/
def normalizeResponseHeaders : Middleware :=
  fun h ctx => do
    let resp ← h ctx
    let headers := resp.headers.map (fun (k, v) => (normalizeName k, v.trimAscii.toString))
    pure { resp with headers := headers }

end Lithe
