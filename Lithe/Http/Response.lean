import Lithe.Prelude
import Lithe.Http.Status
import Lithe.Http.Header
import Lithe.Http.BodyStream
import Lithe.Core.BackgroundTasks

namespace Lithe

structure Response where
  status  : Status
  headers : Headers
  body    : ByteArray
  bodyStream : Option BodyStream := none
  background : BackgroundTasks := {}

namespace Response

@[inline] def withHeader (r : Response) (name value : String) : Response :=
  { r with headers := r.headers.push (name, value) }

private def normalizeHeaderName (s : String) : String :=
  s.trimAscii.toString.toLower

@[inline] def header? (r : Response) (name : String) : Option String :=
  let target := normalizeHeaderName name
  let rec go (hs : List Header) : Option String :=
    match hs with
    | [] => none
    | (k, v) :: rest =>
        if normalizeHeaderName k = target then some v else go rest
  go r.headers.toList

@[inline] def hasHeader (r : Response) (name : String) : Bool :=
  (header? r name).isSome

@[inline] def setHeader (r : Response) (name value : String) : Response :=
  let target := normalizeHeaderName name
  let headers := r.headers.toList.foldr (fun (k, v) acc =>
    if normalizeHeaderName k = target then
      acc
    else
      (k, v) :: acc
  ) []
  { r with headers := (headers ++ [(name, value)]).toArray }

@[inline] def removeHeader (r : Response) (name : String) : Response :=
  let target := normalizeHeaderName name
  let headers := r.headers.toList.filter (fun (k, _) => normalizeHeaderName k != target)
  { r with headers := headers.toArray }

@[inline] def withHeaders (r : Response) (hs : Array Header) : Response :=
  { r with headers := r.headers ++ hs }

@[inline] def withBackground (r : Response) (task : IO Unit) : Response :=
  { r with background := BackgroundTasks.add r.background task }

@[inline] def withBackgroundAll (r : Response) (tasks : Array (IO Unit)) : Response :=
  { r with background := BackgroundTasks.addAll r.background tasks }

@[inline] def withStatus (r : Response) (code : UInt16) : Response :=
  { r with status := Status.ofCode code }

@[inline] def withStatusObj (r : Response) (status : Status) : Response :=
  { r with status := status }

@[inline] def text (s : String) : Response :=
  { status := Status.ok
  , headers := #[ ("content-type", "text/plain; charset=utf-8") ]
  , body := stringToBytes s
  , bodyStream := none
  }

@[inline] def textWithStatus (status : Status) (s : String) : Response :=
  { status := status
  , headers := #[ ("content-type", "text/plain; charset=utf-8") ]
  , body := stringToBytes s
  , bodyStream := none
  }

@[inline] def html (s : String) : Response :=
  { status := Status.ok
  , headers := #[ ("content-type", "text/html; charset=utf-8") ]
  , body := stringToBytes s
  , bodyStream := none
  }

@[inline] def bytes (b : ByteArray) : Response :=
  { status := Status.ok
  , headers := #[ ("content-type", "application/octet-stream") ]
  , body := b
  , bodyStream := none
  }

@[inline] def json (j : Lean.Json) : Response :=
  { status := Status.ok
  , headers := #[ ("content-type", "application/json; charset=utf-8") ]
  , body := stringToBytes (Lean.Json.compress j)
  , bodyStream := none
  }

@[inline] def jsonOf (a : α) [Lean.ToJson α] : Response :=
  json (Lean.toJson a)

@[inline] def empty (status : UInt16 := 204) : Response :=
  { status := Status.ofCode status
  , headers := #[]
  , body := ByteArray.empty
  , bodyStream := none
  }

@[inline] def statusOnly (status : Status) : Response :=
  { status := status, headers := #[], body := ByteArray.empty, bodyStream := none }

@[inline] def redirectWithStatus (status : Status) (location : String) : Response :=
  { status := status
  , headers := #[ ("location", location) ]
  , body := ByteArray.empty
  , bodyStream := none
  }

@[inline] def redirect (location : String) : Response :=
  redirectWithStatus Status.found location

@[inline] def stream (status : Status) (headers : Headers := #[]) (stream : BodyStream) : Response :=
  { status := status
  , headers := headers
  , body := ByteArray.empty
  , bodyStream := some stream
  }

@[inline] def sse (stream : BodyStream) : Response :=
  { status := Status.ok
  , headers := #[
      ("content-type", "text/event-stream; charset=utf-8"),
      ("cache-control", "no-cache"),
      ("connection", "keep-alive"),
      ("x-accel-buffering", "no")
    ]
  , body := ByteArray.empty
  , bodyStream := some stream
  }

@[inline] def isStreaming (r : Response) : Bool :=
  r.bodyStream.isSome

end Response

end Lithe
