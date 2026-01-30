import Lithe.App
import Lithe.Core.Middleware

namespace Lithe

namespace App

@[inline] def prependMiddleware (m : Middleware) (app : App) : App :=
  { app with middleware := #[m] ++ app.middleware }

@[inline] def prependMiddlewareAll (ms : Array Middleware) (app : App) : App :=
  { app with middleware := ms ++ app.middleware }

end App

end Lithe
