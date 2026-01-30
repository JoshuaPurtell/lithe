import Lithe.Core.Middleware
import Lithe.Http.Response
import Init.Data.String.TakeDrop
import Init.Data.String.Modify

namespace Lithe

/--
Ensure a fixed set of headers are present on every response.
Existing headers are preserved.
-/
def defaultHeaders (defaults : Array (String × String)) : Middleware :=
  fun h ctx => do
    let resp ← h ctx
    let mut out := resp
    for (k, v) in defaults do
      if out.headers.any (fun hv => hv.fst.trimAscii.toString.toLower = k.trimAscii.toString.toLower) then
        continue
      else
        out := Response.withHeader out k v
    pure out

/--
Adds a default `server` header if not present.
-/
def serverHeader (value : String := "lithe") : Middleware :=
  defaultHeaders #[("server", value)]

end Lithe
