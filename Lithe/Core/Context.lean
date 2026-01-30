import Lithe.Prelude
import Lithe.Http.Request
import Lithe.Core.CancelToken
import Init.Dynamic

namespace Lithe

structure RequestCtx where
  req          : Request
  params       : Std.HashMap String String
  state        : Std.HashMap String Dynamic
  cancel       : CancelToken
  deadlineNanos : Option Nat

namespace RequestCtx

@[inline] def ofRequest (req : Request) (state : Std.HashMap String Dynamic := Std.HashMap.emptyWithCapacity) : RequestCtx :=
  { req := req
  , params := Std.HashMap.emptyWithCapacity
  , state := state
  , cancel := CancelToken.never
  , deadlineNanos := none
  }

@[inline] def withParams (ctx : RequestCtx) (params : Std.HashMap String String) : RequestCtx :=
  { ctx with params := params }

@[inline] def withCancelToken (ctx : RequestCtx) (token : CancelToken) : RequestCtx :=
  { ctx with cancel := token }

@[inline] def withDeadline (ctx : RequestCtx) (deadline : Option Nat) : RequestCtx :=
  { ctx with deadlineNanos := deadline }

end RequestCtx

end Lithe
