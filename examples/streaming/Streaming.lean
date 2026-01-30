import Lithe
import Lithe.FFI.Exports

open Lithe

private def echoHandler : Handler :=
  fun ctx => do
    let body ← ctx.req.readBodyAll
    let len := body.size
    return Response.text s!"len={len}"

private def streamingApp : App :=
  App.empty
  |>.useAll (Lithe.defaultStack)
  |>.post "/echo" echoHandler

initialize streamingAppRegistry : Unit ← do
  Lithe.registerApp "streaming" (pure streamingApp)
  pure ()

@[export streaming_new_app]
def streaming_new_app : IO UInt64 := do
  let router := App.toRouter streamingApp
  Lithe.newInstance router

@[export streaming_handle]
def streaming_handle (app : UInt64) (reqBytes : ByteArray) : IO ByteArray :=
  Lithe.lithe_handle app reqBytes

@[export streaming_free_app]
def streaming_free_app (app : UInt64) : IO Unit :=
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
