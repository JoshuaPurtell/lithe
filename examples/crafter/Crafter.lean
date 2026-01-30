import Lithe
import Lithe.FFI.Exports

open Lithe

@[extern "crafter_lean_new"]
constant crafter_lean_new : IO UInt64

@[extern "crafter_lean_step"]
constant crafter_lean_step : UInt64 → ByteArray → IO Unit

@[extern "crafter_lean_render"]
constant crafter_lean_render : UInt64 → IO ByteArray

@[extern "crafter_lean_free"]
constant crafter_lean_free : UInt64 → IO Unit

structure StepRequest where
  action : String
  deriving Lean.FromJson

structure FrameResponse where
  id : String
  frame : String
  deriving Lean.ToJson

structure Session where
  handle : UInt64

initialize sessionRef : IO.Ref (Std.HashMap String Session) ←
  IO.mkRef (Std.HashMap.emptyWithCapacity)

initialize nextSessionIdRef : IO.Ref Nat ← IO.mkRef 1

private def nextSessionId : IO String := do
  let n ← nextSessionIdRef.get
  nextSessionIdRef.set (n + 1)
  pure (toString n)

private def getSession (id : String) : ExceptT HttpError IO Session := do
  let m ← sessionRef.get
  match m.get? id with
  | some sess => pure sess
  | none => throw { status := 404, code := "session_not_found", message := s!"unknown session '{id}'" }

private def putSession (id : String) (sess : Session) : IO Unit :=
  sessionRef.modify (fun m => m.insert id sess)

private def removeSession (id : String) : IO Unit :=
  sessionRef.modify (fun m => m.erase id)

private def renderFrame (handle : UInt64) : ExceptT HttpError IO String := do
  let bytes ← crafter_lean_render handle
  match bytesToString? bytes with
  | some s => pure s
  | none => throw { status := 500, code := "render_invalid_utf8", message := "render output invalid utf-8" }

private def stepAndRender (handle : UInt64) (action : String) : ExceptT HttpError IO String := do
  crafter_lean_step handle (stringToBytes action)
  renderFrame handle

private def makeFrameResponse (id : String) (frame : String) : Response :=
  Response.json (Lean.toJson { id := id, frame := frame } : FrameResponse)

private def createSession : ExceptT HttpError IO (String × String) := do
  let handle ← crafter_lean_new
  let id ← nextSessionId
  putSession id { handle := handle }
  let frame ← renderFrame handle
  pure (id, frame)

private def resetSession (id : String) : ExceptT HttpError IO String := do
  let sess ← getSession id
  crafter_lean_free sess.handle
  let handle ← crafter_lean_new
  putSession id { handle := handle }
  renderFrame handle

private def closeSession (id : String) : ExceptT HttpError IO Unit := do
  let sess ← getSession id
  crafter_lean_free sess.handle
  removeSession id

private def createHandler : Handler :=
  fun _ => do
    let (id, frame) ← createSession
    pure (makeFrameResponse id frame)

private def renderHandler : Handler :=
  fun ctx => do
    let id ← (Path.param "id" String) ctx
    let sess ← getSession id
    let frame ← renderFrame sess.handle
    pure (makeFrameResponse id frame)

private def stepHandler : Handler :=
  fun ctx => do
    let id ← (Path.param "id" String) ctx
    let req ← (JsonBody StepRequest) ctx
    if req.action.trimAscii.toString.isEmpty then
      throw (HttpError.badRequest "action required")
    let sess ← getSession id
    let frame ← stepAndRender sess.handle req.action
    pure (makeFrameResponse id frame)

private def resetHandler : Handler :=
  fun ctx => do
    let id ← (Path.param "id" String) ctx
    let frame ← resetSession id
    pure (makeFrameResponse id frame)

private def closeHandler : Handler :=
  fun ctx => do
    let id ← (Path.param "id" String) ctx
    closeSession id
    pure (Response.empty 204)

private def wsHandler : WSHandler :=
  fun conn ctx => do
    let id ← (Path.param "id" String) ctx
    let sess ← getSession id
    let frame ← renderFrame sess.handle
    let _ ← WSConnection.sendText conn frame
    let rec loop : ExceptT HttpError IO Unit := do
      let msg? ← WSConnection.receive conn
      match msg? with
      | none => pure ()
      | some msg =>
          match msg.kind with
          | .text =>
              let action := bytesToString msg.data
              if action.trimAscii.toString.isEmpty then
                loop
              else
                let sess ← getSession id
                let frame ← stepAndRender sess.handle action
                let _ ← WSConnection.sendText conn frame
                loop
          | .binary =>
              let sess ← getSession id
              let frame ← stepAndRender sess.handle (bytesToString msg.data)
              let _ ← WSConnection.sendText conn frame
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

private def crafterApp : App :=
  App.empty
  |>.useAll (Lithe.defaultStack)
  |>.post "/session" createHandler
  |>.get "/session/:id/render" renderHandler
  |>.post "/session/:id/step" stepHandler
  |>.post "/session/:id/reset" resetHandler
  |>.post "/session/:id/close" closeHandler
  |>.ws "/ws/:id" wsHandler

initialize crafterAppRegistry : Unit ← do
  Lithe.registerApp "crafter" (pure crafterApp)
  pure ()

@[export crafter_new_app]
def crafter_new_app : IO UInt64 := do
  let router := App.toRouter crafterApp
  Lithe.newInstance router

@[export crafter_handle]
def crafter_handle (app : UInt64) (reqBytes : ByteArray) : IO ByteArray :=
  Lithe.lithe_handle app reqBytes

@[export crafter_free_app]
def crafter_free_app (app : UInt64) : IO Unit :=
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
