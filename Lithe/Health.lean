import Lithe.Prelude
import Lithe.Core.Handler
import Lithe.Http.Response

namespace Lithe

abbrev HealthCheck := IO (Option String)

structure HealthConfig where
  okStatus : UInt16 := 200
  failStatus : UInt16 := 503
  includeDetails : Bool := true

structure CheckResult where
  name : String
  ok : Bool
  message : Option String := none

namespace CheckResult

@[inline] def toJson (r : CheckResult) : Lean.Json :=
  let base : List (String × Lean.Json) :=
    [ ("name", Lean.Json.str r.name)
    , ("ok", Lean.Json.bool r.ok)
    ]
  match r.message with
  | some msg => Lean.Json.mkObj (base ++ [("message", Lean.Json.str msg)])
  | none => Lean.Json.mkObj base

end CheckResult

structure HealthReport where
  status : String
  checks : Array CheckResult := #[]

namespace HealthReport

@[inline] def toJson (r : HealthReport) : Lean.Json :=
  Lean.Json.mkObj
    [ ("status", Lean.Json.str r.status)
    , ("checks", Lean.Json.arr (r.checks.map CheckResult.toJson))
    ]

end HealthReport

private def statusLabel (ok : Bool) : String :=
  if ok then "ok" else "fail"

private def runChecks (checks : Array (String × HealthCheck)) : IO (Array CheckResult) := do
  checks.mapM (fun (name, check) => do
    let res ← (try check catch e => pure (some s!"exception: {e}"))
    match res with
    | none => pure { name := name, ok := true }
    | some msg => pure { name := name, ok := false, message := some msg }
  )

/--
Readiness handler with optional checks and structured JSON output.
- If `includeDetails` is false, the response body is `{ "status": "ok|fail" }`.
- If true, includes per-check status.
-/
def readinessHandler (checks : Array (String × HealthCheck)) (cfg : HealthConfig := {}) : Handler :=
  fun _ => do
    let results ← runChecks checks
    let ok := results.toList.all (fun r => r.ok)
    let status := statusLabel ok
    let body :=
      if cfg.includeDetails then
        HealthReport.toJson { status := status, checks := results }
      else
        Lean.Json.mkObj [("status", Lean.Json.str status)]
    let resp := Response.json body
    let code := if ok then cfg.okStatus else cfg.failStatus
    pure (resp.withStatus code)

/--
Liveness handler (no checks by default).
- Behaves like readiness with an empty check list.
-/
def healthHandler (cfg : HealthConfig := {}) : Handler :=
  readinessHandler #[] cfg

end Lithe
