import Lithe.Prelude
import Lithe.Http.Method
import Lithe.Http.Header
import Lithe.Http.BodyStream
import Lithe.Core.Error

namespace Lithe

structure Request where
  method  : Method
  path    : String
  query   : String
  headers : Headers
  body    : ByteArray
  bodyStream : Option BodyStream := none
  remote  : Option String := none

namespace Request

@[inline] def header? (req : Request) (name : String) : Option String :=
  let target := name.trimAscii.toString.toLower
  let rec go (hs : List Header) : Option String :=
    match hs with
    | [] => none
    | (k, v) :: rest =>
        if k.trimAscii.toString.toLower = target then some v else go rest
  go req.headers.toList

@[inline] def bodyString? (req : Request) : Option String :=
  bytesToString? req.body

@[inline] def hasBodyStream (req : Request) : Bool :=
  req.bodyStream.isSome

partial def readBodyAll (req : Request) (limit : Option Nat := none) : ExceptT HttpError IO ByteArray := do
  match req.bodyStream with
  | none => pure req.body
  | some stream =>
      let rec loop (acc : ByteArray) (total : Nat) : ExceptT HttpError IO ByteArray := do
        let chunk? ← stream.next
        match chunk? with
        | none => pure acc
        | some chunk =>
            let total' := total + chunk.size
            match limit with
            | some maxBytes =>
                if total' > maxBytes then
                  throw { status := 413, code := "payload_too_large", message := "payload too large" }
                else
                  loop (acc ++ chunk) total'
            | none =>
                loop (acc ++ chunk) total'
      loop req.body req.body.size

private def addQueryValue
    (m : Std.HashMap String (Array String))
    (k v : String) : Std.HashMap String (Array String) :=
  let existing := m.getD k #[]
  m.insert k (existing.push v)

/-- Naive query parser: no percent-decoding, preserves repeated keys. -/
def parseQuery (q : String) : Std.HashMap String (Array String) :=
  let raw := if q.startsWith "?" then (q.drop 1).toString else q
  let parts := raw.splitOn "&"
  parts.foldl (init := Std.HashMap.emptyWithCapacity) (fun m part =>
    if part.isEmpty then
      m
    else
      let kv := part.splitOn "="
      match kv with
      | [] => m
      | k :: rest =>
          let v := if rest.isEmpty then "" else String.intercalate "=" rest
          addQueryValue m k v
  )

@[inline] def queryParams (req : Request) : Std.HashMap String (Array String) :=
  parseQuery req.query

end Request

end Lithe
