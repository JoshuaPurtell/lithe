import Lithe.Core.Middleware
import Lithe.Core.Context
import Lithe.Core.Error
import Lithe.Core.Trace
import Lithe.Http.Response
import Lithe.Http.Request
import Init.Dynamic

namespace Lithe

structure TraceConfig where
  traceHeader : String := "x-trace-id"
  spanHeader : String := "x-span-id"
  traceparentHeader : String := "traceparent"
  useTraceparent : Bool := true
  echoHeaders : Bool := true
  handleErrors : Bool := false
  stateKey : String := traceStateKey
  onStart : TraceInfo → RequestCtx → IO Unit := fun _ _ => pure ()
  onEnd : TraceInfo → RequestCtx → UInt16 → Nat → IO Unit := fun _ _ _ _ => pure ()

initialize traceIdRef : IO.Ref UInt64 ← IO.mkRef 1
initialize spanIdRef : IO.Ref UInt64 ← IO.mkRef 1

@[inline] def nextTraceId : IO String := do
  let id ← traceIdRef.get
  traceIdRef.set (id + 1)
  pure (toString id)

@[inline] def nextSpanId : IO String := do
  let id ← spanIdRef.get
  spanIdRef.set (id + 1)
  pure (toString id)

private def parseTraceparent? (value : String) : Option (String × String × Bool) :=
  let parts := value.trimAscii.toString.splitOn "-"
  match parts with
  | _ver :: traceId :: parentId :: flags :: [] =>
      let sampled := flags.trimAscii.toString != "00"
      if traceId.isEmpty || parentId.isEmpty then none else some (traceId, parentId, sampled)
  | _ => none

private def nanosToMs (nanos : Nat) : Nat :=
  nanos / 1000000

private def normalizeHeaderName (s : String) : String :=
  s.trimAscii.toString.toLower

private def setRequestHeader (req : Request) (name value : String) : Request :=
  let target := normalizeHeaderName name
  let headers := req.headers.toList.filter (fun (k, _) => normalizeHeaderName k != target)
  { req with headers := (headers ++ [(name, value)]).toArray }

/--
Attach trace/span IDs to the request context and optionally echo them on responses.
If `traceparent` is present and `useTraceparent` is true, it seeds the trace id.
-/
def tracing (cfg : TraceConfig := {}) : Middleware :=
  fun h ctx =>
    ExceptT.mk do
      let start ← IO.monoNanosNow
      let tp? := if cfg.useTraceparent then ctx.req.header? cfg.traceparentHeader else none
      let parsed := tp?.bind parseTraceparent?
      let existingTrace := ctx.req.header? cfg.traceHeader
      let (traceId, parentSpan, sampled) ←
        match parsed with
        | some (tid, parentId, sampled) => pure (tid, some parentId, sampled)
        | none =>
            match existingTrace with
            | some tid => pure (tid, none, true)
            | none => do
                let tid ← nextTraceId
                pure (tid, none, true)
      let spanId ← nextSpanId
      let info : TraceInfo :=
        { traceId := traceId
        , spanId := spanId
        , parentSpanId := parentSpan
        , sampled := sampled
        , startNanos := start
        }
      let req := setRequestHeader ctx.req cfg.traceHeader traceId
      let req := setRequestHeader req cfg.spanHeader spanId
      let ctx := { ctx with
        req := req
        state := ctx.state.insert cfg.stateKey (Dynamic.mk info)
      }
      cfg.onStart info ctx
      let result ← (h ctx).run
      let stop ← IO.monoNanosNow
      let elapsed := nanosToMs (stop - start)
      let statusCode :=
        match result with
        | .ok resp => resp.status.code
        | .error err => err.status
      cfg.onEnd info ctx statusCode elapsed
      match result with
      | .ok resp =>
          let resp :=
            if cfg.echoHeaders then
              resp
              |>.withHeader cfg.traceHeader traceId
              |>.withHeader cfg.spanHeader spanId
            else
              resp
          pure (.ok resp)
      | .error err =>
          if cfg.handleErrors then
            let resp := (Response.json (HttpError.toJson err)).withStatus err.status
            let resp :=
              if cfg.echoHeaders then
                resp
                |>.withHeader cfg.traceHeader traceId
                |>.withHeader cfg.spanHeader spanId
              else
                resp
            pure (.ok resp)
          else
            pure (.error err)

end Lithe
