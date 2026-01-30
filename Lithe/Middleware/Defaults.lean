import Lithe.Core.Middleware
import Lithe.Http.Response

namespace Lithe

/--
Set a default `content-type` if the response has no body-aware header.
- If body is empty: no header added
- If body non-empty: defaults to `text/plain; charset=utf-8`
-/
def defaultContentType (value : String := "text/plain; charset=utf-8") : Middleware :=
  fun h ctx => do
    let resp ← h ctx
    if resp.bodyStream.isSome || resp.body.isEmpty then
      pure resp
    else
      let hasCt := resp.headers.any (fun hv => hv.fst.trimAscii.toString.toLower = "content-type")
      if hasCt then
        pure resp
      else
        pure (Response.withHeader resp "content-type" value)

/--
Add a `content-length` header if missing.
- Uses `resp.body.size`.
-/
def contentLength : Middleware :=
  fun h ctx => do
    let resp ← h ctx
    if resp.bodyStream.isSome then
      pure resp
    else
      let hasCl := resp.headers.any (fun hv => hv.fst.trimAscii.toString.toLower = "content-length")
      if hasCl then
        pure resp
      else
        pure (Response.withHeader resp "content-length" (toString resp.body.size))

end Lithe
