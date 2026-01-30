import Lithe.Http.Response
import Lithe.Http.BodyStream
import Lithe.Http.Mime
import Lithe.Core.Error
import Init.System.IO

namespace Lithe

structure FileRange where
  start : Nat
  stop  : Nat
  deriving Repr

namespace FileRange

@[inline] def length (r : FileRange) : Nat :=
  r.stop - r.start + 1

end FileRange

def parseRangeHeader (header : String) (size : Nat) : Option FileRange :=
  if size = 0 then
    none
  else
    let h := header.trimAscii.toString
    let lower := h.toLower
    if !lower.startsWith "bytes=" then
      none
    else
      let spec := (h.drop 6).toString
      let pieces := spec.splitOn ","
      if pieces.length != 1 then
        none
      else
        let rangeSpec := pieces.headD ""
        match rangeSpec.splitOn "-" with
        | [startStr, endStr] =>
            if startStr.isEmpty then
              if endStr.isEmpty then
                none
              else
                match String.toNat? endStr with
                | none => none
                | some suffix =>
                    if suffix = 0 then
                      none
                    else if suffix >= size then
                      some { start := 0, stop := size - 1 }
                    else
                      some { start := size - suffix, stop := size - 1 }
            else
              match String.toNat? startStr with
              | none => none
              | some start =>
                  if start >= size then
                    none
                  else if endStr.isEmpty then
                    some { start := start, stop := size - 1 }
                  else
                    match String.toNat? endStr with
                    | none => none
                    | some endPos =>
                        let endPos := if endPos >= size then size - 1 else endPos
                        if endPos < start then none else some { start := start, stop := endPos }
        | _ => none

private def ioToHttpError (io : IO α) (err : HttpError) : ExceptT HttpError IO α :=
  ExceptT.mk do
    try
      let v ← io
      pure (Except.ok v)
    catch _ =>
      pure (Except.error err)

namespace Response

@[inline] def rangeNotSatisfiable (size : Nat) : Response :=
  { status := Status.ofCode 416
  , headers := #[ ("content-range", s!"bytes */{size}") ]
  , body := ByteArray.empty
  }

private def fileWithMeta
    (path : System.FilePath)
    (size : Nat)
    (contentType : String)
    (range? : Option FileRange)
    (chunkSize : Nat) : ExceptT HttpError IO Response := do
  let baseHeaders :=
    #[ ("content-type", contentType)
     , ("accept-ranges", "bytes")
     ]
  match range? with
  | none =>
      let stream ← BodyStream.ofFile path chunkSize
      let headers := baseHeaders.push ("content-length", toString size)
      pure
        { status := Status.ok
        , headers := headers
        , body := ByteArray.empty
        , bodyStream := some stream
        }
  | some r =>
      let stream ← BodyStream.ofFileRange path r.start r.stop chunkSize
      let headers := baseHeaders ++ #[
        ("content-length", toString (FileRange.length r)),
        ("content-range", s!"bytes {r.start}-{r.stop}/{size}")
      ]
      pure
        { status := Status.ofCode 206
        , headers := headers
        , body := ByteArray.empty
        , bodyStream := some stream
        }

def file (path : System.FilePath) (range? : Option FileRange := none) (chunkSize : Nat := 65536) : ExceptT HttpError IO Response := do
  let pathExists ← path.pathExists
  if !pathExists then
    throw (HttpError.notFound "file not found")
  else
    pure ()
  let pathMeta ← ioToHttpError (path.metadata) (HttpError.notFound "file not found")
  if pathMeta.type != IO.FS.FileType.file then
    throw (HttpError.notFound "file not found")
  else
    pure ()
  let size := pathMeta.byteSize.toNat
  let contentType := Mime.forPath path
  fileWithMeta path size contentType range? chunkSize

def fileWithRangeHeader (path : System.FilePath) (rangeHeader? : Option String) (chunkSize : Nat := 65536) : ExceptT HttpError IO Response := do
  let pathExists ← path.pathExists
  if !pathExists then
    throw (HttpError.notFound "file not found")
  else
    pure ()
  let pathMeta ← ioToHttpError (path.metadata) (HttpError.notFound "file not found")
  if pathMeta.type != IO.FS.FileType.file then
    throw (HttpError.notFound "file not found")
  else
    pure ()
  let size := pathMeta.byteSize.toNat
  let contentType := Mime.forPath path
  match rangeHeader? with
  | none => fileWithMeta path size contentType none chunkSize
  | some header =>
      match parseRangeHeader header size with
      | some r => fileWithMeta path size contentType (some r) chunkSize
      | none => pure (rangeNotSatisfiable size)

end Response

end Lithe
