import Lithe.Core.Middleware
import Lithe.Core.Error
import Lithe.Http.Response
import Lithe.Core.Context

namespace Lithe

private def nanosToMs (nanos : Nat) : Nat :=
  nanos / 1000000

/--
Best-effort timeout. If the handler exceeds the deadline, returns a timeout error.
Note: the underlying handler is not cancelled and may continue running.
This middleware also sets `ctx.deadlineNanos` for cooperative cancellation helpers.
-/
def timeout (ms : Nat) (onTimeout : HttpError := { status := 504, code := "timeout", message := "request timed out" }) : Middleware :=
  fun h ctx =>
    ExceptT.mk do
      let start ← IO.monoNanosNow
      let deadline := some (start + ms * 1000000)
      let ctx := RequestCtx.withDeadline ctx deadline
      let res ← (h ctx).run
      let stop ← IO.monoNanosNow
      let elapsed := nanosToMs (stop - start)
      if elapsed > ms then
        pure (.error onTimeout)
      else
        pure res

end Lithe
