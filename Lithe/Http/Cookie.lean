import Lithe.Prelude
import Lithe.Http.Request

namespace Lithe

/-- Parse a Cookie header value and return the named cookie value. -/
@[inline] def cookieValue? (cookieHeader : String) (name : String) : Option String :=
  let parts := cookieHeader.splitOn ";"
  let rec loop (xs : List String) : Option String :=
    match xs with
    | [] => none
    | p :: rest =>
        let trimmed := p.trimAscii.toString
        let kv := trimmed.splitOn "="
        match kv with
        | [] => loop rest
        | k :: vs =>
            if k == name then
              some (String.intercalate "=" vs)
            else
              loop rest
  loop parts

/-- Read a cookie value by name from the request headers. -/
@[inline] def requestCookie? (req : Request) (name : String) : Option String :=
  match req.header? "cookie" with
  | none => none
  | some header => cookieValue? header name

end Lithe
