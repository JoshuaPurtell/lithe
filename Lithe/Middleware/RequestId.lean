import Lithe.Core.Middleware
import Lithe.Core.Context
import Lithe.Http.Response
import Lithe.Http.Request

namespace Lithe

initialize requestIdRef : IO.Ref UInt64 ← IO.mkRef 1

@[inline] def nextRequestId : IO String := do
  let id ← requestIdRef.get
  requestIdRef.set (id + 1)
  pure (toString id)

/--
Ensure a request ID header exists and echo it on successful responses.
If the header already exists, it is preserved.
-/
def requestId (headerName : String := "x-request-id") : Middleware :=
  fun h ctx => do
    let existing := ctx.req.header? headerName
    let id ←
      match existing with
      | some v => pure v
      | none => nextRequestId
    let req :=
      match existing with
      | some _ => ctx.req
      | none => { ctx.req with headers := ctx.req.headers.push (headerName, id) }
    let ctx := { ctx with req := req }
    let resp ← h ctx
    pure (Response.withHeader resp headerName id)

end Lithe
