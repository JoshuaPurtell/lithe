import Lithe
import Lithe.FFI.Exports

open Lithe

private def spawnEvents (writer : BodyWriter) (count : Nat := 10) (intervalMs : Nat := 1000) : IO Unit := do
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

private def sseApp : App :=
  App.empty
  |>.useAll (Lithe.defaultStack)
  |>.get "/sse" sseHandler

initialize sseAppRegistry : Unit ← do
  Lithe.registerApp "sse" (pure sseApp)
  pure ()

@[export sse_new_app]
def sse_new_app : IO UInt64 := do
  let router := App.toRouter sseApp
  Lithe.newInstance router

@[export sse_handle]
def sse_handle (app : UInt64) (reqBytes : ByteArray) : IO ByteArray :=
  Lithe.lithe_handle app reqBytes

@[export sse_free_app]
def sse_free_app (app : UInt64) : IO Unit :=
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
