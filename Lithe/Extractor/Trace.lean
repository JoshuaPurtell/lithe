import Lithe.Extractor.Extractor
import Lithe.Core.Trace
import Lithe.Core.Error
import Init.Dynamic

namespace Lithe
namespace Extractor

@[inline] def trace? (key : String := traceStateKey) : Extractor (Option TraceInfo) :=
  fun ctx => do
    match ctx.state.get? key with
    | none => return none
    | some dyn =>
        match Dynamic.get? TraceInfo dyn with
        | some v => return some v
        | none => throw (HttpError.internal s!"trace state key '{key}' has wrong type")

@[inline] def trace (key : String := traceStateKey) : Extractor TraceInfo :=
  fun ctx => do
    match (← trace? key ctx) with
    | some v => return v
    | none => throw (HttpError.internal "trace info missing")

@[inline] def Trace (key : String := traceStateKey) : Extractor TraceInfo :=
  trace key

end Extractor
end Lithe
