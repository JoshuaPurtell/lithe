import Lithe.Core.Middleware
import Lithe.Core.Error
import Lithe.Http.Request
import Lithe.Http.Response
import Lean.Data.Json

namespace Lithe

structure MetricsEvent where
  method : Method
  path : String
  status : Nat
  durationMs : Nat
  responseBytes : Option Nat
  requestId : Option String
  remote : Option String
  errorCode : Option String := none

structure MetricsConfig where
  includeRequestId : Bool := true
  requestIdHeader : String := "x-request-id"
  includeRemote : Bool := true
  onResult : MetricsEvent → IO Unit := fun _ => pure ()

private def nanosToMs (nanos : Nat) : Nat :=
  nanos / 1000000

/--
Emit a metrics event on every request.
-/
def metrics (cfg : MetricsConfig := {}) : Middleware :=
  fun h ctx =>
    ExceptT.mk do
      let start ← IO.monoNanosNow
      let result ← (h ctx).run
      let stop ← IO.monoNanosNow
      let duration := nanosToMs (stop - start)
      let rid := if cfg.includeRequestId then ctx.req.header? cfg.requestIdHeader else none
      let remote := if cfg.includeRemote then ctx.req.remote else none
      let event :=
        match result with
        | .ok resp =>
            let bytes := if resp.bodyStream.isSome then none else some resp.body.size
            { method := ctx.req.method
            , path := ctx.req.path
            , status := resp.status.code.toNat
            , durationMs := duration
            , responseBytes := bytes
            , requestId := rid
            , remote := remote
            }
        | .error err =>
            { method := ctx.req.method
            , path := ctx.req.path
            , status := err.status.toNat
            , durationMs := duration
            , responseBytes := none
            , requestId := rid
            , remote := remote
            , errorCode := some err.code
            }
      cfg.onResult event
      pure result

namespace MetricsEvent

@[inline] def toJson (e : MetricsEvent) : Lean.Json :=
  let base : List (String × Lean.Json) :=
    [ ("method", (toString e.method : Lean.Json))
    , ("path", (e.path : Lean.Json))
    , ("status", (toString e.status : Lean.Json))
    , ("duration_ms", (toString e.durationMs : Lean.Json))
    ]
  let base :=
    match e.responseBytes with
    | some n => base ++ [("response_bytes", (toString n : Lean.Json))]
    | none => base
  let base :=
    match e.requestId with
    | some v => base ++ [("request_id", (v : Lean.Json))]
    | none => base
  let base :=
    match e.remote with
    | some v => base ++ [("remote", (v : Lean.Json))]
    | none => base
  let base :=
    match e.errorCode with
    | some v => base ++ [("error_code", (v : Lean.Json))]
    | none => base
  Lean.Json.mkObj base

end MetricsEvent

@[inline] def metricsJsonLogger (logFn : String → IO Unit := IO.println) (cfg : MetricsConfig := {}) : Middleware :=
  metrics { cfg with onResult := fun e => logFn (Lean.Json.compress (MetricsEvent.toJson e)) }

end Lithe
