import Lithe.Core.Middleware
import Lithe.Core.Error
import Lithe.Http.Response

namespace Lithe

/-- Map an HttpError before it is converted to a response. -/
def mapError (f : HttpError → HttpError) : Middleware :=
  fun h ctx =>
    ExceptT.mk do
      let result ← (h ctx).run
      match result with
      | .ok resp => pure (.ok resp)
      | .error err => pure (.error (f err))

/-- Convert HttpError into a Response, preventing error propagation. -/
def handleError (f : HttpError → Response) : Middleware :=
  fun h ctx =>
    ExceptT.mk do
      let result ← (h ctx).run
      match result with
      | .ok resp => pure (.ok resp)
      | .error err => pure (.ok (f err))

end Lithe
