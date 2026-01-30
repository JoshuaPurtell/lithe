import Lithe.Core.Context
import Lithe.Core.Error
import Lithe.Http.Response
import Lithe.Core.BackgroundTasks

namespace Lithe

abbrev Handler := RequestCtx → ExceptT HttpError IO Response

namespace Handler

@[inline] def run (h : Handler) (ctx : RequestCtx) : IO Response := do
  let res ← (h ctx).run
  let resp :=
    match res with
    | .ok r => r
    | .error err => (Response.json (HttpError.toJson err)).withStatus err.status
  BackgroundTasks.run resp.background
  pure resp

@[inline] def pure (resp : Response) : Handler :=
  fun _ => do
    return resp

end Handler

end Lithe
