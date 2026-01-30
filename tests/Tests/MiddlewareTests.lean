import Lithe.Core.Middleware
import Lithe.Core.Context
import Lithe.Http.Request
import Lithe.Http.Method
import Lithe.Http.Response
import Lithe.Core.Error
import Tests.Util

def sampleRequest : Lithe.Request :=
  { method := Lithe.Method.GET
  , path := "/health"
  , query := ""
  , headers := #[]
  , body := ByteArray.empty
  }

def sampleCtx : Lithe.RequestCtx :=
  Lithe.RequestCtx.ofRequest sampleRequest

def baseHandler : Lithe.Handler := fun _ => do
  return Lithe.Response.text "ok"

def errorHandler : Lithe.Handler := fun _ => do
  throw (Lithe.HttpError.badRequest "bad")

def addHeader (name value : String) : Lithe.Middleware := fun h => fun ctx => do
  let resp ← h ctx
  return resp.withHeader name value

def testIdentity : IO Unit := do
  let resp ← (Lithe.Middleware.identity baseHandler sampleCtx).run
  match resp with
  | .ok okResp =>
      let body ← bodyString okResp
      assertEqString body "ok" "identity body"
  | .error _ => throw (IO.userError "identity middleware should not error")

def testComposeAddsHeaders : IO Unit := do
  let m1 := addHeader "x-a" "1"
  let m2 := addHeader "x-b" "2"
  let resp ← ((Lithe.Middleware.compose m1 m2) baseHandler sampleCtx).run
  match resp with
  | .ok okResp =>
      assertHeader okResp "x-a" "1"
      assertHeader okResp "x-b" "2"
  | .error _ => throw (IO.userError "composed middleware should not error")

def testErrorPropagation : IO Unit := do
  let m := addHeader "x-test" "1"
  let resp ← (m errorHandler sampleCtx).run
  match resp with
  | .ok _ => throw (IO.userError "middleware should not swallow errors")
  | .error err =>
      assertEqString err.code "bad_request" "error code"
