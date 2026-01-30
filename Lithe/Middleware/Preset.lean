import Lithe.Core.Middleware
import Lithe.Middleware.RequestId
import Lithe.Middleware.Logging
import Lithe.Middleware.Tracing
import Lithe.Middleware.Timeout
import Lithe.Middleware.BodyLimit
import Lithe.Middleware.DefaultHeaders
import Lithe.Middleware.Defaults
import Lithe.Middleware.Cancel

namespace Lithe

/--
A reasonable default middleware stack:
- request id
- tracing
- logging
- timeout
- body size limit
- server header
- default content-type
- content-length
-/
def defaultStack
    (timeoutMs : Nat := 10_000)
    (maxBodyBytes : Nat := 1_048_576)
    (server : String := "lithe")
    : Array Middleware :=
  #[(cancelToken), (requestId), (tracing {}), (logging {}), (timeout timeoutMs), (bodyLimit maxBodyBytes), (serverHeader server), (defaultContentType), (contentLength)]

end Lithe
