import Lithe
import Lithe.FFI.Exports

open Lithe

private def echoHandler : WSHandler :=
  fun conn _ => do
    let rec loop : ExceptT HttpError IO Unit := do
      let msg? ← WSConnection.receive conn
      match msg? with
      | none => pure ()
      | some msg =>
          match msg.kind with
          | .text =>
              let _ ← WSConnection.send conn msg
              loop
          | .binary =>
              let _ ← WSConnection.send conn msg
              loop
          | .ping =>
              let _ ← WSConnection.send conn (WSMessage.pong msg.data)
              loop
          | .pong =>
              loop
          | .close =>
              let _ ← WSConnection.send conn (WSMessage.close)
              WSConnection.close conn
    loop

private def wsApp : App :=
  App.empty
  |>.useAll (Lithe.defaultStack)
  |>.ws "/ws" echoHandler

initialize wsAppRegistry : Unit ← do
  Lithe.registerApp "websocket" (pure wsApp)
  pure ()

@[export websocket_new_app]
def websocket_new_app : IO UInt64 := do
  let router := App.toRouter wsApp
  Lithe.newInstance router

@[export websocket_handle]
def websocket_handle (app : UInt64) (reqBytes : ByteArray) : IO ByteArray :=
  Lithe.lithe_handle app reqBytes

@[export websocket_free_app]
def websocket_free_app (app : UInt64) : IO Unit :=
  Lithe.freeInstance app

@[export lithe_new_app_named]
def lithe_new_app_named (nameBytes : ByteArray) : IO UInt64 := do
  let name ←
    match bytesToString? nameBytes with
    | some s => pure s
    | none => throw (IO.userError "invalid app name")
  let app ← Lithe.getApp name
  let router := App.toRouter app
  Lithe.newInstance router app.state
