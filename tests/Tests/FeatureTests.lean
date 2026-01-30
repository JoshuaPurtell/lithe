import Lithe
import Tests.Util

open Lithe

private def mkReq (method : Method) (path : String) (headers : Headers := #[]) (body : ByteArray := ByteArray.empty) : Request :=
  { method := method
  , path := path
  , query := ""
  , headers := headers
  , body := body
  }

def testFormParse : IO Unit := do
  let body := stringToBytes "name=Lean+4&tag=web&tag=framework&empty=&encoded=a%2Bb%20c"
  let req := mkReq Method.POST "/submit" #[("content-type", "application/x-www-form-urlencoded")] body
  let ctx := RequestCtx.ofRequest req
  let res ← ((Form.params (limit := none)) ctx).run
  match res with
  | .error err => throw (IO.userError s!"form parse failed: {err.message}")
  | .ok params =>
      match params.get? "name" with
      | some values =>
          assertEqString values[0]! "Lean 4" "form name"
      | none => throw (IO.userError "missing form name")
      match params.get? "tag" with
      | some values =>
          assertEqNat values.size 2 "form tag count"
          assertEqString values[0]! "web" "form tag[0]"
          assertEqString values[1]! "framework" "form tag[1]"
      | none => throw (IO.userError "missing form tag")
      match params.get? "empty" with
      | some values =>
          assertEqString values[0]! "" "form empty"
      | none => throw (IO.userError "missing form empty")
      match params.get? "encoded" with
      | some values =>
          assertEqString values[0]! "a+b c" "form encoded"
      | none => throw (IO.userError "missing form encoded")

def testFormInvalid : IO Unit := do
  let body := stringToBytes "name=%ZZ"
  let req := mkReq Method.POST "/submit" #[("content-type", "application/x-www-form-urlencoded")] body
  let ctx := RequestCtx.ofRequest req
  let res ← ((Form.params (limit := none)) ctx).run
  match res with
  | .ok _ => throw (IO.userError "expected form parse failure")
  | .error err =>
      assertEqNat err.status.toNat 400 "form invalid status"

def testMultipartParse : IO Unit := do
  let boundary := "Boundary123"
  let bodyStr :=
    s!"--{boundary}\r\n" ++
    "Content-Disposition: form-data; name=\"field1\"\r\n\r\n" ++
    "value1\r\n" ++
    s!"--{boundary}\r\n" ++
    "Content-Disposition: form-data; name=\"file\"; filename=\"a.txt\"\r\n" ++
    "Content-Type: text/plain\r\n\r\n" ++
    "hello file\r\n" ++
    s!"--{boundary}--\r\n"
  let req := mkReq Method.POST "/upload" #[("content-type", s!"multipart/form-data; boundary={boundary}")] (stringToBytes bodyStr)
  let ctx := RequestCtx.ofRequest req
  let res ← (Multipart.extract (limit := none) ctx).run
  match res with
  | .error err => throw (IO.userError s!"multipart parse failed: {err.message}")
  | .ok form =>
      assertEqNat form.parts.size 2 "multipart parts count"
      let part0 := form.parts[0]!
      assertEqString (bytesToString part0.body) "value1" "multipart field value"
      let part1 := form.parts[1]!
      assertEqString (part1.filename.getD "") "a.txt" "multipart filename"
      assertEqString (bytesToString part1.body) "hello file" "multipart file body"
  let fileRes ← (Multipart.File "file" (limit := none) ctx).run
  match fileRes with
  | .error err => throw (IO.userError s!"file extractor failed: {err.message}")
  | .ok f =>
      assertEqString f.filename "a.txt" "file extractor filename"

def testMultipartMissingBoundary : IO Unit := do
  let req := mkReq Method.POST "/upload" #[("content-type", "multipart/form-data")] (stringToBytes "ignored")
  let ctx := RequestCtx.ofRequest req
  let res ← (Multipart.extract (limit := none) ctx).run
  match res with
  | .ok _ => throw (IO.userError "expected multipart boundary failure")
  | .error err =>
      assertEqNat err.status.toNat 400 "multipart missing boundary status"

def testStaticFilesServe : IO Unit := do
  let root : System.FilePath := System.FilePath.mk "tests/fixtures/static"
  let handler := StaticFiles.handler root
  let req := mkReq Method.GET "/hello.txt"
  let resp ← Handler.run handler (RequestCtx.ofRequest req)
  assertEqNat resp.status.code.toNat 200 "static file status"
  assertHeader resp "content-type" "text/plain; charset=utf-8"
  let body ← responseBody resp
  assertEqBytes body (stringToBytes "hello static") "static file body"

def testStaticIndex : IO Unit := do
  let root : System.FilePath := System.FilePath.mk "tests/fixtures/static"
  let handler := StaticFiles.handler root
  let req := mkReq Method.GET "/"
  let resp ← Handler.run handler (RequestCtx.ofRequest req)
  assertEqNat resp.status.code.toNat 200 "static index status"
  assertHeader resp "content-type" "text/html; charset=utf-8"
  let body ← responseBody resp
  assertEqBytes body (stringToBytes "<h1>index</h1>") "static index body"

def testStaticTraversal : IO Unit := do
  let root : System.FilePath := System.FilePath.mk "tests/fixtures/static"
  let handler := StaticFiles.handler root
  let req := mkReq Method.GET "/../todos.txt"
  let resp ← Handler.run handler (RequestCtx.ofRequest req)
  assertEqNat resp.status.code.toNat 404 "static traversal status"

def testFileRange : IO Unit := do
  let path : System.FilePath := System.FilePath.mk "tests/fixtures/static/range.txt"
  let respRes ← (Response.fileWithRangeHeader path (some "bytes=2-5")).run
  match respRes with
  | .error err => throw (IO.userError s!"file range error: {err.message}")
  | .ok resp =>
      assertEqNat resp.status.code.toNat 206 "range status"
      assertHeader resp "content-range" "bytes 2-5/10"
      let body ← responseBody resp
      assertEqBytes body (stringToBytes "2345") "range body"

def testFileRangeInvalid : IO Unit := do
  let path : System.FilePath := System.FilePath.mk "tests/fixtures/static/range.txt"
  let respRes ← (Response.fileWithRangeHeader path (some "bytes=200-300")).run
  match respRes with
  | .error err => throw (IO.userError s!"file range invalid error: {err.message}")
  | .ok resp =>
      assertEqNat resp.status.code.toNat 416 "range invalid status"

def testBackgroundTasks : IO Unit := do
  let flag ← IO.mkRef false
  let handler : Handler :=
    fun _ => do
      return (Response.text "ok").withBackground (flag.set true)
  let req := mkReq Method.GET "/"
  let _resp ← Handler.run handler (RequestCtx.ofRequest req)
  IO.sleep 50
  let done ← flag.get
  assert done "background task did not run"
