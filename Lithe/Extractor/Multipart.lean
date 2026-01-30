import Lithe.Extractor.Extractor
import Lithe.Http.Request
import Lithe.Http.Header

namespace Lithe

structure MultipartPart where
  headers : Headers
  name : Option String := none
  filename : Option String := none
  contentType : Option String := none
  body : ByteArray

structure Multipart where
  parts : Array MultipartPart

structure MultipartFile where
  name : String
  filename : String
  contentType : Option String := none
  headers : Headers
  body : ByteArray

abbrev File := MultipartFile

namespace Multipart

private def isMultipartContentType (ct : String) : Bool :=
  let lower := ct.trimAscii.toString.toLower
  lower.startsWith "multipart/form-data"

private def stripQuotes (s : String) : String :=
  if s.startsWith "\"" && s.endsWith "\"" && s.length >= 2 then
    (s.drop 1).dropEnd 1 |>.toString
  else
    s

private def parseBoundary (ct : String) : Option String :=
  let parts := ct.splitOn ";"
  if parts.isEmpty then
    none
  else
    let base := parts.headD "" |>.trimAscii.toString.toLower
    if base != "multipart/form-data" then
      none
    else
      let rec loop (rest : List String) : Option String :=
        match rest with
        | [] => none
        | p :: tail =>
            let trimmed := p.trimAscii.toString
            let lower := trimmed.toLower
            if lower.startsWith "boundary=" then
              let v := (trimmed.drop 9).toString
              some (stripQuotes v)
            else
              loop tail
      loop parts.tail

private partial def startsWithAt (hay needle : ByteArray) (pos : Nat) : Bool :=
  if pos + needle.size > hay.size then
    false
  else
    let rec loop (i : Nat) : Bool :=
      if i = needle.size then
        true
      else if hay.get! (pos + i) == needle.get! i then
        loop (i + 1)
      else
        false
    loop 0

private partial def findSubarray (hay needle : ByteArray) (start : Nat := 0) : Option Nat :=
  if needle.size = 0 then
    some start
  else if hay.size < needle.size || start > hay.size - needle.size then
    none
  else
    let max := hay.size - needle.size
    let rec loop (i : Nat) : Option Nat :=
      if i > max then
        none
      else if startsWithAt hay needle i then
        some i
      else
        loop (i + 1)
    loop start

private structure BoundaryMatch where
  prefixIndex : Nat
  prefixLen : Nat

private def boundaryStart (m : BoundaryMatch) : Nat :=
  m.prefixIndex + m.prefixLen

private def pickEarliest (cands : List BoundaryMatch) : Option BoundaryMatch :=
  let rec loop (xs : List BoundaryMatch) (best? : Option BoundaryMatch) : Option BoundaryMatch :=
    match xs with
    | [] => best?
    | m :: rest =>
        let best? :=
          match best? with
          | none => some m
          | some b => if m.prefixIndex < b.prefixIndex then some m else some b
        loop rest best?
  loop cands none

private def findFirstBoundary
    (body : ByteArray)
    (boundaryLine : ByteArray)
    (boundaryCRLF : ByteArray)
    (boundaryLF : ByteArray) : Option BoundaryMatch :=
  let base : List BoundaryMatch :=
    if startsWithAt body boundaryLine 0 then
      [{ prefixIndex := 0, prefixLen := 0 }]
    else
      []
  let crlf :=
    match findSubarray body boundaryCRLF 0 with
    | some idx => [{ prefixIndex := idx, prefixLen := 2 }]
    | none => []
  let lf :=
    match findSubarray body boundaryLF 0 with
    | some idx => [{ prefixIndex := idx, prefixLen := 1 }]
    | none => []
  pickEarliest (base ++ crlf ++ lf)

private def findNextBoundary
    (body : ByteArray)
    (boundaryCRLF : ByteArray)
    (boundaryLF : ByteArray)
    (start : Nat) : Option BoundaryMatch :=
  let crlf :=
    match findSubarray body boundaryCRLF start with
    | some idx => [{ prefixIndex := idx, prefixLen := 2 }]
    | none => []
  let lf :=
    match findSubarray body boundaryLF start with
    | some idx => [{ prefixIndex := idx, prefixLen := 1 }]
    | none => []
  pickEarliest (crlf ++ lf)

private def parseHeaders (bytes : ByteArray) : Except String Headers := do
  let s ←
    match bytesToString? bytes with
    | some v => pure v
    | none => throw "invalid header encoding"
  let lines :=
    if s.contains "\r\n" then
      s.splitOn "\r\n"
    else
      s.splitOn "\n"
  let mut headers : Headers := #[]
  for line in lines do
    if line.isEmpty then
      continue
    let parts := line.splitOn ":"
    match parts with
    | [] => pure ()
    | name :: rest =>
        if rest.isEmpty then
          throw s!"invalid header line: {line}"
        else
          let value := String.intercalate ":" rest |>.trimAscii.toString
          headers := headers.push (name.trimAscii.toString, value)
  pure headers

private def headerValue? (headers : Headers) (name : String) : Option String :=
  let target := name.trimAscii.toString.toLower
  let rec loop (hs : List Header) : Option String :=
    match hs with
    | [] => none
    | (k, v) :: rest =>
        if k.trimAscii.toString.toLower = target then some v else loop rest
  loop headers.toList

private def parseContentDisposition (value : String) : Option (Option String × Option String) :=
  let parts := value.splitOn ";"
  if parts.isEmpty then
    none
  else
    let (name?, filename?) := parts.tail.foldl
      (fun (acc : Option String × Option String) part =>
        let (n?, f?) := acc
        let p := part.trimAscii.toString
        if p.toLower.startsWith "name=" then
          let v := (p.drop 5).toString
          (some (stripQuotes v), f?)
        else if p.toLower.startsWith "filename=" then
          let v := (p.drop 9).toString
          (n?, some (stripQuotes v))
        else
          (n?, f?)
      )
      (none, none)
    some (name?, filename?)

private partial def parseParts (body : ByteArray) (boundary : String) : Except String (Array MultipartPart) := do
  let boundaryLine := stringToBytes s!"--{boundary}"
  let boundaryCRLF := stringToBytes s!"\r\n--{boundary}"
  let boundaryLF := stringToBytes s!"\n--{boundary}"
  let headerSepCRLF := stringToBytes "\r\n\r\n"
  let headerSepLF := stringToBytes "\n\n"
  let rec loop (pos : Nat) (acc : Array MultipartPart) : Except String (Array MultipartPart) := do
    let afterBoundary := pos + boundaryLine.size
    if startsWithAt body (stringToBytes "--") afterBoundary then
      pure acc
    else
      let (headerStart, _) ←
        if startsWithAt body (stringToBytes "\r\n") afterBoundary then
          pure (afterBoundary + 2, 2)
        else if startsWithAt body (stringToBytes "\n") afterBoundary then
          pure (afterBoundary + 1, 1)
        else
          throw "invalid multipart boundary line ending"
      let hdrCRLF? := findSubarray body headerSepCRLF headerStart
      let hdrLF? := findSubarray body headerSepLF headerStart
      let (headerEnd, sepLen) ←
        match hdrCRLF?, hdrLF? with
        | some a, some b => pure (if a <= b then (a, 4) else (b, 2))
        | some a, none => pure (a, 4)
        | none, some b => pure (b, 2)
        | none, none => throw "missing multipart headers terminator"
      let headersBytes := body.extract headerStart headerEnd
      let headers ← parseHeaders headersBytes
      let contentStart := headerEnd + sepLen
      let next? := findNextBoundary body boundaryCRLF boundaryLF contentStart
      match next? with
      | none => throw "missing multipart boundary"
      | some m =>
          let contentEnd := m.prefixIndex
          let content := body.extract contentStart contentEnd
          let name? : Option String :=
            match headerValue? headers "content-disposition" with
            | some v =>
                match parseContentDisposition v with
                | some (n?, _) => n?
                | none => none
            | none => none
          let filename? : Option String :=
            match headerValue? headers "content-disposition" with
            | some v =>
                match parseContentDisposition v with
                | some (_, f?) => f?
                | none => none
            | none => none
          let contentType? := headerValue? headers "content-type"
          let part : MultipartPart :=
            { headers := headers
            , name := name?
            , filename := filename?
            , contentType := contentType?
            , body := content
            }
          let nextPos := boundaryStart m
          loop nextPos (acc.push part)
  match findFirstBoundary body boundaryLine boundaryCRLF boundaryLF with
  | none => throw "multipart boundary not found"
  | some m => loop (boundaryStart m) #[]

def extract (limit : Option Nat := none) : Extractor Multipart :=
  fun ctx => do
    let ct? := ctx.req.header? "content-type"
    match ct? with
    | none => throw (HttpError.badRequest "missing content-type")
    | some ct =>
        if !isMultipartContentType ct then
          throw { status := 415, code := "unsupported_media_type", message := "expected multipart/form-data" }
        match parseBoundary ct with
        | none => throw (HttpError.badRequest "missing multipart boundary")
        | some boundary =>
            let body ← ctx.req.readBodyAll limit
            match parseParts body boundary with
            | .ok parts => pure { parts := parts }
            | .error err => throw (HttpError.badRequest err)

def file? (form : Multipart) (name : String) : Option MultipartFile :=
  let rec loop (parts : List MultipartPart) : Option MultipartFile :=
    match parts with
    | [] => none
    | p :: rest =>
        match p.name, p.filename with
        | some n, some fn =>
            if n = name then
              some { name := n, filename := fn, contentType := p.contentType, headers := p.headers, body := p.body }
            else
              loop rest
        | _, _ => loop rest
  loop form.parts.toList

def field? (form : Multipart) (name : String) : Option String :=
  let rec loop (parts : List MultipartPart) : Option String :=
    match parts with
    | [] => none
    | p :: rest =>
        match p.name, p.filename with
        | some n, none =>
            if n = name then
              bytesToString? p.body
            else
              loop rest
        | _, _ => loop rest
  loop form.parts.toList

def File (name : String) (limit : Option Nat := none) : Extractor MultipartFile :=
  fun ctx => do
    let form ← extract limit ctx
    match file? form name with
    | some f => pure f
    | none => throw (HttpError.badRequest s!"missing file field '{name}'")

end Multipart

end Lithe
