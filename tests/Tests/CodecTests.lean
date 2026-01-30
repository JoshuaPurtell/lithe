import Lithe.Codec.Wire
import Lithe.Http.WebSocket
import Tests.Util

def assertEqHeaders (actual expected : Array (String × String)) : IO Unit := do
  assert (decide (actual.toList = expected.toList)) s!"headers mismatch: expected {expected}, got {actual}"

def testWireRequestRoundTrip : IO Unit := do
  let req : Lithe.WireRequest :=
    { method := Lithe.Method.POST
    , path := "/api/items"
    , query := "q=lean&tag=web"
    , headers := #[("x-one", "1"), ("x-two", "2")]
    , body := Lithe.stringToBytes "payload"
    , remote := some "127.0.0.1"
    }
  let bytes := Lithe.encodeWireRequest req
  match Lithe.decodeWireRequest bytes with
  | .error err => throw (IO.userError s!"decodeWireRequest failed: {err}")
  | .ok decoded =>
      assert (decide (decoded.method = req.method)) "method mismatch"
      assertEqString decoded.path req.path "path"
      assertEqString decoded.query req.query "query"
      assertEqHeaders decoded.headers req.headers
      assertEqBytes decoded.body req.body "body"
      assert (decide (decoded.remote = req.remote)) "remote mismatch"

def testWireResponseRoundTrip : IO Unit := do
  let resp : Lithe.Response :=
    (Lithe.Response.text "ok")
      |>.withStatus 201
      |>.withHeader "x-test" "true"
  let wire := Lithe.WireResponse.ofResponse resp
  let bytes := Lithe.encodeWireResponse wire
  match Lithe.decodeWireResponse bytes with
  | .error err => throw (IO.userError s!"decodeWireResponse failed: {err}")
  | .ok decoded =>
      assertEqNat decoded.status wire.status "status"
      assertEqHeaders decoded.headers wire.headers
      assertEqBytes decoded.body wire.body "body"

def testStreamMessageRoundTrip : IO Unit := do
  let headBytes := Lithe.encodeStreamHead 200 #[("x-stream", "yes")] true (Lithe.stringToBytes "head")
  match Lithe.decodeStreamMsg headBytes with
  | .ok (Lithe.StreamMsg.head status headers isStream body) =>
      assertEqNat status 200 "stream head status"
      assertEqHeaders headers #[("x-stream", "yes")]
      assert (isStream = true) "stream head isStream mismatch"
      assertEqBytes body (Lithe.stringToBytes "head") "stream head body"
  | _ => throw (IO.userError "stream head decode mismatch")

  let chunkBytes := Lithe.encodeStreamChunk (Lithe.stringToBytes "chunk")
  match Lithe.decodeStreamMsg chunkBytes with
  | .ok (Lithe.StreamMsg.chunk body) =>
      assertEqBytes body (Lithe.stringToBytes "chunk") "stream chunk body"
  | _ => throw (IO.userError "stream chunk decode mismatch")

  let endBytes := Lithe.encodeStreamEnd
  match Lithe.decodeStreamMsg endBytes with
  | .ok Lithe.StreamMsg.finish => pure ()
  | _ => throw (IO.userError "stream end decode mismatch")

def testWebSocketMessageRoundTrip : IO Unit := do
  let msgText := Lithe.WSMessage.text "hello"
  match Lithe.WSMessage.decode (Lithe.WSMessage.encode msgText) with
  | .ok decoded =>
      assert (decide (decoded.kind = msgText.kind)) "ws text kind mismatch"
      assertEqBytes decoded.data msgText.data "ws text data"
  | .error err => throw (IO.userError s!"ws text decode failed: {err}")

  let msgBin := Lithe.WSMessage.binary (Lithe.stringToBytes "bin")
  match Lithe.WSMessage.decode (Lithe.WSMessage.encode msgBin) with
  | .ok decoded =>
      assert (decide (decoded.kind = msgBin.kind)) "ws binary kind mismatch"
      assertEqBytes decoded.data msgBin.data "ws binary data"
  | .error err => throw (IO.userError s!"ws binary decode failed: {err}")

  let msgPing := Lithe.WSMessage.ping (Lithe.stringToBytes "ping")
  match Lithe.WSMessage.decode (Lithe.WSMessage.encode msgPing) with
  | .ok decoded =>
      assert (decide (decoded.kind = msgPing.kind)) "ws ping kind mismatch"
      assertEqBytes decoded.data msgPing.data "ws ping data"
  | .error err => throw (IO.userError s!"ws ping decode failed: {err}")

  let msgPong := Lithe.WSMessage.pong (Lithe.stringToBytes "pong")
  match Lithe.WSMessage.decode (Lithe.WSMessage.encode msgPong) with
  | .ok decoded =>
      assert (decide (decoded.kind = msgPong.kind)) "ws pong kind mismatch"
      assertEqBytes decoded.data msgPong.data "ws pong data"
  | .error err => throw (IO.userError s!"ws pong decode failed: {err}")

  let msgClose := Lithe.WSMessage.close
  match Lithe.WSMessage.decode (Lithe.WSMessage.encode msgClose) with
  | .ok decoded =>
      assert (decide (decoded.kind = msgClose.kind)) "ws close kind mismatch"
  | .error err => throw (IO.userError s!"ws close decode failed: {err}")
