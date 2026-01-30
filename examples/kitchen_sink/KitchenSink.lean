import Lithe
import Lithe.FFI.Exports

open Lithe

private def helloHandler : Handler :=
  fun _ => do
    return Response.text "hello"

private def echoHandler : Handler :=
  fun ctx => do
    let body ← ctx.req.readBodyAll
    return Response.text s!"len={body.size}"

private def spawnEvents (writer : BodyWriter) (count : Nat := 3) (intervalMs : Nat := 100) : IO Unit := do
  let _ ← (writer.push (SSEEvent.keepAlive "connected" |> SSEEvent.toBytes)).run
  let rec loop (i : Nat) : IO Unit := do
    if i >= count then
      let _ ← (writer.close).run
      pure ()
    else
      IO.sleep (UInt32.ofNat intervalMs)
      let ev := SSEEvent.ofData s!"message {i}" (id? := some (toString i)) (event? := some "tick")
      let res ← (writer.push (SSEEvent.toBytes ev)).run
      match res with
      | .ok true => loop (i + 1)
      | _ =>
          let _ ← (writer.close).run
          pure ()
  loop 0

private def sseHandler : Handler :=
  fun _ => do
    let (stream, writer) ← BodyStream.newQueuePair 65536
    let _ ← IO.asTask (spawnEvents writer)
    return Response.sse stream

private def wsEchoHandler : WSHandler :=
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

private def kitchenApp : App :=
  App.empty
  |>.useAll (Lithe.defaultStack)
  |>.get "/hello" helloHandler
  |>.post "/echo" echoHandler
  |>.get "/sse" sseHandler
  |>.ws "/ws" wsEchoHandler

initialize kitchenAppRegistry : Unit ← do
  Lithe.registerApp "kitchen_sink" (pure kitchenApp)
  pure ()

@[export kitchen_sink_new_app]
def kitchen_sink_new_app : IO UInt64 := do
  let router := App.toRouter kitchenApp
  Lithe.newInstance router

@[export kitchen_sink_handle]
def kitchen_sink_handle (app : UInt64) (reqBytes : ByteArray) : IO ByteArray :=
  Lithe.lithe_handle app reqBytes

@[export kitchen_sink_free_app]
def kitchen_sink_free_app (app : UInt64) : IO Unit :=
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
