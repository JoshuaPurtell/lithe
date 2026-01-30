import Lithe.Prelude

namespace Lithe

structure Status where
  code : UInt16
  reason : String
  deriving BEq, DecidableEq, Repr

namespace Status

@[inline] def ofCode (code : UInt16) (reason := "") : Status :=
  { code := code, reason := reason }

@[inline] def ok : Status := { code := 200, reason := "OK" }
@[inline] def created : Status := { code := 201, reason := "Created" }
@[inline] def noContent : Status := { code := 204, reason := "No Content" }
@[inline] def movedPermanently : Status := { code := 301, reason := "Moved Permanently" }
@[inline] def found : Status := { code := 302, reason := "Found" }
@[inline] def seeOther : Status := { code := 303, reason := "See Other" }
@[inline] def temporaryRedirect : Status := { code := 307, reason := "Temporary Redirect" }
@[inline] def permanentRedirect : Status := { code := 308, reason := "Permanent Redirect" }
@[inline] def badRequest : Status := { code := 400, reason := "Bad Request" }
@[inline] def unauthorized : Status := { code := 401, reason := "Unauthorized" }
@[inline] def forbidden : Status := { code := 403, reason := "Forbidden" }
@[inline] def notFound : Status := { code := 404, reason := "Not Found" }
@[inline] def requestTimeout : Status := { code := 408, reason := "Request Timeout" }
@[inline] def conflict : Status := { code := 409, reason := "Conflict" }
@[inline] def unprocessable : Status := { code := 422, reason := "Unprocessable Entity" }
@[inline] def tooManyRequests : Status := { code := 429, reason := "Too Many Requests" }
@[inline] def internalError : Status := { code := 500, reason := "Internal Server Error" }
@[inline] def gatewayTimeout : Status := { code := 504, reason := "Gateway Timeout" }

end Status

end Lithe
