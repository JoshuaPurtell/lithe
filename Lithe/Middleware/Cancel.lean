import Lithe.Core.Middleware
import Lithe.Core.Context
import Lithe.Core.CancelToken

namespace Lithe

/--
Attach a fresh cancellation token to each request context.
If a token is already present, it is preserved.
Handlers can use `checkCancel`, `sleepWithCancel`, or `awaitWithCancel`.
-/
def cancelToken : Middleware :=
  fun h ctx => do
    if ctx.cancel.isNever then
      let token ← CancelToken.new
      let ctx := RequestCtx.withCancelToken ctx token
      h ctx
    else
      h ctx

end Lithe
