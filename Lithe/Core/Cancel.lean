import Lithe.Core.Context
import Lithe.Core.Error

namespace Lithe

private def deadlineExceeded (deadline : Option Nat) : IO Bool := do
  match deadline with
  | none => pure false
  | some d =>
      let now ← IO.monoNanosNow
      pure (now > d)

/--
Check whether the given cancellation token has been canceled or its deadline exceeded.
Throws the provided HttpError on cancellation/timeout.
-/
def checkToken
    (cancel : CancelToken)
    (deadline : Option Nat)
    (onCancel : HttpError := { status := 499, code := "canceled", message := "request canceled" })
    (onTimeout : HttpError := { status := 504, code := "timeout", message := "request timed out" })
    : ExceptT HttpError IO Unit := do
  let canceled ← cancel.isCanceled
  if canceled then
    throw onCancel
  let expired ← deadlineExceeded deadline
  if expired then
    throw onTimeout
  pure ()

/--
Check whether the request has been canceled or its deadline exceeded.
Throws the provided HttpError on cancellation/timeout.
-/
def checkCancel
    (ctx : RequestCtx)
    (onCancel : HttpError := { status := 499, code := "canceled", message := "request canceled" })
    (onTimeout : HttpError := { status := 504, code := "timeout", message := "request timed out" })
    : ExceptT HttpError IO Unit := do
  checkToken ctx.cancel ctx.deadlineNanos onCancel onTimeout

/--
Sleep for the given duration, checking for cancellation or deadline expiry.
The sleep is broken into small intervals to allow cooperative cancellation.
-/
partial def sleepWithCancel (ctx : RequestCtx) (ms : Nat) (tickMs : Nat := 10)
    (onCancel : HttpError := { status := 499, code := "canceled", message := "request canceled" })
    (onTimeout : HttpError := { status := 504, code := "timeout", message := "request timed out" })
    : ExceptT HttpError IO Unit := do
  let rec loop (remaining : Nat) : ExceptT HttpError IO Unit := do
    checkToken ctx.cancel ctx.deadlineNanos onCancel onTimeout
    if remaining = 0 then
      pure ()
    else
      let step := min tickMs remaining
      IO.sleep (UInt32.ofNat step)
      loop (remaining - step)
  loop ms

/--
Run an IO action while periodically checking for cancellation or deadline expiry.
Returns early with an error if canceled/timed out. The underlying action continues running.
-/
partial def awaitWithCancel (ctx : RequestCtx) (action : IO α) (pollMs : Nat := 10)
    (onCancel : HttpError := { status := 499, code := "canceled", message := "request canceled" })
    (onTimeout : HttpError := { status := 504, code := "timeout", message := "request timed out" })
    : ExceptT HttpError IO α := do
  let ref ← IO.mkRef (none : Option (Except IO.Error α))
  let _ ← IO.asTask (do
    let res ← (try
      let v ← action
      pure (.ok v)
    catch e =>
      pure (.error e))
    ref.set (some res)
  )
  let rec loop : ExceptT HttpError IO α := do
    checkToken ctx.cancel ctx.deadlineNanos onCancel onTimeout
    let val ← ref.get
    match val with
    | some (.ok v) => pure v
    | some (.error e) => throw (HttpError.internal s!"io error: {e}")
    | none =>
        IO.sleep (UInt32.ofNat pollMs)
        loop
  loop

end Lithe
