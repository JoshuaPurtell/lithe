import Lithe.Core.Middleware
import Lithe.Core.Error
import Lithe.Http.Request
import Lithe.Http.Response
import Lithe.Codec.Json

namespace Lithe

structure JsonLogConfig where
  logFn : String → IO Unit := IO.println
  includeRequestId : Bool := true
  requestIdHeader : String := "x-request-id"
  includeRemote : Bool := true
  includeHeaders : Bool := false

private def headersToJson (headers : Array (String × String)) : Lean.Json :=
  let fields := headers.toList.map (fun (k, v) => (k, (v : Lean.Json)))
  Lean.Json.mkObj fields

/--
Structured JSON logging for requests.
-/
def loggingJson (cfg : JsonLogConfig := {}) : Middleware :=
  fun h ctx =>
    ExceptT.mk do
      let start ← IO.monoNanosNow
      let result ← (h ctx).run
      let stop ← IO.monoNanosNow
      let elapsedMs := (stop - start) / 1000000
      let statusCode :=
        match result with
        | .ok resp => resp.status.code.toNat
        | .error err => err.status.toNat
      let rid := if cfg.includeRequestId then ctx.req.header? cfg.requestIdHeader else none
      let remote := if cfg.includeRemote then ctx.req.remote else none
      let mut fields : List (String × Lean.Json) :=
        [ ("method", (toString ctx.req.method : Lean.Json))
        , ("path", (ctx.req.path : Lean.Json))
        , ("status", (toString statusCode : Lean.Json))
        , ("elapsed_ms", (toString elapsedMs : Lean.Json))
        ]
      match rid with
      | some v => fields := fields ++ [("request_id", (v : Lean.Json))]
      | none => pure ()
      match remote with
      | some v => fields := fields ++ [("remote", (v : Lean.Json))]
      | none => pure ()
      if cfg.includeHeaders then
        fields := fields ++ [("headers", headersToJson ctx.req.headers)]
      let line := Lean.Json.compress (Lean.Json.mkObj fields)
      cfg.logFn line
      pure result

end Lithe
