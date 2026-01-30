import Lithe.Prelude
import Lithe.Core.Error
import Lithe.Core.Context
import Lithe.Core.CancelToken
import Lithe.Http.Request
import Lithe.Http.Response
import Lithe.Runtime.WSRegistry
import Lithe.Runtime.StreamQueue
import Lithe.Router.Builder
import Lithe.App

namespace Lithe

inductive WSMessageType
| text | binary | close | ping | pong
  deriving BEq, DecidableEq, Repr

namespace WSMessageType

@[inline] def toByte : WSMessageType → UInt8
  | text => 0
  | binary => 1
  | close => 2
  | ping => 3
  | pong => 4

@[inline] def ofByte? (b : UInt8) : Option WSMessageType :=
  match b.toNat with
  | 0 => some text
  | 1 => some binary
  | 2 => some close
  | 3 => some ping
  | 4 => some pong
  | _ => none

end WSMessageType

structure WSMessage where
  kind : WSMessageType
  data : ByteArray

namespace WSMessage

@[inline] def text (s : String) : WSMessage :=
  { kind := .text, data := stringToBytes s }

@[inline] def binary (b : ByteArray) : WSMessage :=
  { kind := .binary, data := b }

@[inline] def ping (b : ByteArray := ByteArray.empty) : WSMessage :=
  { kind := .ping, data := b }

@[inline] def pong (b : ByteArray := ByteArray.empty) : WSMessage :=
  { kind := .pong, data := b }

@[inline] def close (b : ByteArray := ByteArray.empty) : WSMessage :=
  { kind := .close, data := b }

private def byteArrayOfList (xs : List UInt8) : ByteArray :=
  xs.foldl (fun acc b => acc.push b) ByteArray.empty

@[inline] def encode (msg : WSMessage) : ByteArray :=
  (ByteArray.empty.push msg.kind.toByte) ++ msg.data

@[inline] def decode (bytes : ByteArray) : Except String WSMessage :=
  match bytes.toList with
  | [] => throw "empty ws message"
  | b :: rest =>
      match WSMessageType.ofByte? b with
      | none => throw s!"unknown ws message type {b.toNat}"
      | some kind => pure { kind := kind, data := byteArrayOfList rest }

end WSMessage

structure WSConnection where
  id : UInt64
  pollMs : Nat := 5

namespace WSConnection

private def getSession (conn : WSConnection) : ExceptT HttpError IO WSSession := do
  let sess? ← getWS? conn.id
  match sess? with
  | none => throw { status := 410, code := "ws_closed", message := "websocket closed" }
  | some sess => pure sess

@[inline] def send (conn : WSConnection) (msg : WSMessage) : ExceptT HttpError IO Bool := do
  let sess ← getSession conn
  let canceled ← sess.cancel.isCanceled
  if canceled then
    throw { status := 499, code := "canceled", message := "websocket canceled" }
  let ok ← StreamQueue.push sess.outQ (WSMessage.encode msg)
  pure ok

@[inline] def sendText (conn : WSConnection) (msg : String) : ExceptT HttpError IO Bool :=
  send conn (WSMessage.text msg)

@[inline] def sendBinary (conn : WSConnection) (msg : ByteArray) : ExceptT HttpError IO Bool :=
  send conn (WSMessage.binary msg)

@[inline] def sendJson (conn : WSConnection) (msg : Lean.Json) : ExceptT HttpError IO Bool :=
  send conn (WSMessage.text (Lean.Json.compress msg))

@[inline] def close (conn : WSConnection) : ExceptT HttpError IO Unit := do
  closeWS conn.id

partial def receive (conn : WSConnection) : ExceptT HttpError IO (Option WSMessage) := do
  let sess ← getSession conn
  let rec loop : ExceptT HttpError IO (Option WSMessage) := do
    let canceled ← sess.cancel.isCanceled
    if canceled then
      throw { status := 499, code := "canceled", message := "websocket canceled" }
    let msg? ← StreamQueue.pop? sess.inQ
    match msg? with
    | some bytes =>
        match WSMessage.decode bytes with
        | .ok msg => pure (some msg)
        | .error err =>
            throw { status := 500, code := "ws_decode_error", message := err }
    | none =>
        let closed ← StreamQueue.isClosed sess.inQ
        if closed then
          pure none
        else
          IO.sleep (UInt32.ofNat conn.pollMs)
          loop
  loop

end WSConnection

abbrev WSHandler := WSConnection → RequestCtx → ExceptT HttpError IO Unit

structure WSConfig where
  inCapacity : Nat := 262144
  outCapacity : Nat := 262144
  pollMs : Nat := 5
  headerName : String := "x-lithe-ws-id"

@[inline] def wsHeaderName : String := "x-lithe-ws-id"

private def isWebSocketUpgrade (req : Request) : Bool :=
  let methodOk := req.method == Method.GET
  let upgradeOk :=
    match req.header? "upgrade" with
    | none => false
    | some v => v.trimAscii.toString.toLower == "websocket"
  methodOk && upgradeOk

namespace WSHandler

/--
Convert a WebSocket handler into a normal HTTP handler that requests an upgrade.
The returned response includes `x-lithe-ws-id` for the Rust shim to bind the socket.
-/
def toHandler (h : WSHandler) (cfg : WSConfig := {}) : Handler :=
  fun ctx => do
    if !isWebSocketUpgrade ctx.req then
      throw { status := 426, code := "upgrade_required", message := "websocket upgrade required" }
    let inQ ← StreamQueue.new cfg.inCapacity
    let outQ ← StreamQueue.new cfg.outCapacity
    let cancel ← CancelToken.new
    let taskRef ← IO.mkRef (none : Option (Task (Except IO.Error Unit)))
    let sess : WSSession := { inQ := inQ, outQ := outQ, cancel := cancel, taskRef := taskRef }
    let id ← registerWS sess
    let conn : WSConnection := { id := id, pollMs := cfg.pollMs }
    let task ← IO.asTask (do
      let _ ← (h conn ctx).run
      let sess? ← getWS? id
      match sess? with
      | none => pure ()
      | some sess =>
          let _ ← StreamQueue.push sess.outQ (WSMessage.encode (WSMessage.close))
          pure ()
      finishWS id
    )
    setWSTask id task
    let headerName := if cfg.headerName.isEmpty then wsHeaderName else cfg.headerName
    let resp : Response :=
      { status := Status.ofCode 101
      , headers := #[(headerName, toString id)]
      , body := ByteArray.empty
      , bodyStream := none
      }
    pure resp

end WSHandler

namespace Router

@[inline] def ws (path : String) (h : WSHandler) (r : Router) : Router :=
  Router.get path (WSHandler.toHandler h) r

end Router

namespace App

@[inline] def ws (path : String) (h : WSHandler) (app : App) : App :=
  App.get path (WSHandler.toHandler h) app

end App

end Lithe
