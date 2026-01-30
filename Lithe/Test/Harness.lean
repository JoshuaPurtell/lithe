import Lithe.Runtime.Dispatch
import Lithe.Core.Context

namespace Lithe

@[inline] def run (r : Router) (req : Request) : IO Response :=
  dispatch r (RequestCtx.ofRequest req)

end Lithe
