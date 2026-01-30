import Lithe.Prelude

namespace Lithe

/--
Tracing metadata stored in the request context.
- `traceId` groups spans across services.
- `spanId` identifies this request within the trace.
- `parentSpanId` is optional linkage to an upstream span.
-/
structure TraceInfo where
  traceId : String
  spanId : String
  parentSpanId : Option String := none
  sampled : Bool := true
  startNanos : Nat := 0
  deriving Inhabited, TypeName

@[inline] def traceStateKey : String := "lithe.trace"

end Lithe
