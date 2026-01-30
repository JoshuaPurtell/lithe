import Lithe
import Lithe.FFI.Exports

open Lithe

private def helloHandler : Handler :=
  fun _ => do
    return Response.text "hello"

private def sleepHandler : Handler :=
  fun ctx => do
    let ms ← (Path.param "ms" Nat) ctx
    let sleepMs : UInt32 := UInt32.ofNat ms
    IO.sleep sleepMs
    return Response.text s!"slept {ms}ms"

private def helloApp : App :=
  App.empty
  |>.useAll (Lithe.defaultStack)
  |>.get "/hello" helloHandler
  |>.get "/sleep/:ms" sleepHandler

private def testApp : App :=
  App.empty
  |>.useAll (Lithe.defaultStack 200)
  |>.get "/hello" helloHandler
  |>.get "/sleep/:ms" sleepHandler

initialize helloAppRegistry : Unit ← do
  Lithe.registerApp "hello" (pure helloApp)
  Lithe.registerApp "hello-test" (pure testApp)
  pure ()

@[export hello_new_app]
def hello_new_app : IO UInt64 := do
  let router := App.toRouter helloApp
  Lithe.newInstance router

@[export hello_handle]
def hello_handle (app : UInt64) (reqBytes : ByteArray) : IO ByteArray :=
  Lithe.lithe_handle app reqBytes

@[export hello_free_app]
def hello_free_app (app : UInt64) : IO Unit :=
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
