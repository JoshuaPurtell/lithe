import Lithe.Core.Middleware
import Lithe.Core.Error

namespace Lithe

structure LogExtConfig where
  logFn : String → IO Unit := IO.println
  includeRequestId : Bool := true
  requestIdHeader : String := "x-request-id"
  includeRemote : Bool := true
  includeBodyBytes : Bool := true

private def nanosToMs (nanos : Nat) : Nat :=
  nanos / 1000000

private def optPart (label : String) (val : Option String) : String :=
  match val with
  | some v => s!" {label}={v}"
  | none => ""

private def optNat (label : String) (val : Option Nat) : String :=
  match val with
  | some v => s!" {label}={v}"
  | none => ""

/--
Logging with optional request-id, remote, and response body size.
-/
def loggingExt (cfg : LogExtConfig := {}) : Middleware :=
  fun h ctx =>
    ExceptT.mk do
      let start ← IO.monoNanosNow
      let result ← (h ctx).run
      let stop ← IO.monoNanosNow
      let elapsed := nanosToMs (stop - start)
      let statusCode :=
        match result with
        | .ok resp => resp.status.code.toNat
        | .error err => err.status.toNat
      let bodyBytes :=
        match result with
        | .ok resp => if resp.bodyStream.isSome then none else some resp.body.size
        | .error _ => none
      let rid := if cfg.includeRequestId then ctx.req.header? cfg.requestIdHeader else none
      let remote := if cfg.includeRemote then ctx.req.remote else none
      let line := s!"{ctx.req.method} {ctx.req.path} {statusCode} {elapsed}ms" ++
        optPart "rid" rid ++ optPart "remote" remote ++
        (if cfg.includeBodyBytes then optNat "bytes" bodyBytes else "")
      cfg.logFn line
      pure result

end Lithe
