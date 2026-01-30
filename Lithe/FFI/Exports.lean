import Lithe.Runtime.Registry
import Lithe.Runtime.AsyncRegistry
import Lithe.Runtime.StreamRegistry
import Lithe.Runtime.WSRegistry
import Lithe.Runtime.Dispatch
import Lithe.Codec.Wire
import Lithe.Core.Context
import Lithe.Core.Error
import Lithe.Http.Response
import Lithe.Http.BodyStream
import Lithe.Router.Router
import Lithe.Core.CancelToken

namespace Lithe

@[export lithe_init]
def lithe_init : IO UInt32 :=
  pure 1

@[export lithe_new_app]
def lithe_new_app (routerBytes : ByteArray) : IO UInt64 := do
  let _ := routerBytes
  newInstance Router.empty

@[export lithe_handle]
def lithe_handle (app : UInt64) (reqBytes : ByteArray) : IO ByteArray := do
  let inst ← getInstance app
  match decodeWireRequest reqBytes with
  | .ok wireReq =>
      let req := wireReq.toRequest
      let ctx := RequestCtx.ofRequest req inst.state
      let resp ← dispatch inst.router ctx
      let wireResp := WireResponse.ofResponse resp
      pure (encodeWireResponse wireResp)
  | .error err =>
      let err := HttpError.badRequest err
      let resp := (Response.json (HttpError.toJson err)).withStatus err.status
      pure (encodeWireResponse (WireResponse.ofResponse resp))

@[export lithe_free_app]
def lithe_free_app (app : UInt64) : IO Unit :=
  freeInstance app

private def encodeError (msg : String) : ByteArray :=
  let err := HttpError.internal msg
  let resp := (Response.json (HttpError.toJson err)).withStatus err.status
  encodeWireResponse (WireResponse.ofResponse resp)

private def errorResponse (err : HttpError) : Response :=
  (Response.json (HttpError.toJson err)).withStatus err.status

private def handleRequest (inst : AppInstance) (cancel : CancelToken) (reqBytes : ByteArray) : IO ByteArray := do
  match decodeWireRequest reqBytes with
  | .ok wireReq =>
      let req := wireReq.toRequest
      let ctx := RequestCtx.ofRequest req inst.state
      let ctx := RequestCtx.withCancelToken ctx cancel
      let resp ← dispatch inst.router ctx
      let wireResp := WireResponse.ofResponse resp
      pure (encodeWireResponse wireResp)
  | .error err =>
      let err := HttpError.badRequest err
      let resp := (Response.json (HttpError.toJson err)).withStatus err.status
      pure (encodeWireResponse (WireResponse.ofResponse resp))

/--
Start handling a request asynchronously. Returns a request ID that can be polled.
-/
@[export lithe_handle_async]
def lithe_handle_async (app : UInt64) (reqBytes : ByteArray) : IO UInt64 := do
  let inst ← getInstance app
  let cancel ← CancelToken.new
  let task ← IO.asTask (handleRequest inst cancel reqBytes)
  registerPending { task := task, cancel := cancel }

/--
Poll for a completed response. Returns an empty ByteArray if not ready.
-/
@[export lithe_poll_response]
def lithe_poll_response (reqId : UInt64) : IO ByteArray := do
  let pending? ← getPending? reqId
  match pending? with
  | none => pure ByteArray.empty
  | some p =>
      let finished ← IO.hasFinished p.task
      if finished then
        let res ← IO.wait p.task
        removePending reqId
        match res with
        | .ok bytes => pure bytes
        | .error e => pure (encodeError s!"io error: {e}")
      else
        pure ByteArray.empty

/--
Request cooperative cancellation for a pending request.
-/
@[export lithe_cancel_request]
def lithe_cancel_request (reqId : UInt64) : IO Unit :=
  cancelPending reqId

private def streamQueueCapacity : Nat := 262144
private def streamPumpSleepMs : Nat := 5

private partial def pushWithBackpressure (q : StreamQueue) (chunk : ByteArray) (cancel : CancelToken) : IO Bool := do
  let rec loop : IO Bool := do
    let canceled ← cancel.isCanceled
    if canceled then
      StreamQueue.close q
      pure false
    else
      let ok ← StreamQueue.push q chunk
      if ok then
        pure true
      else
        let closed ← q.isClosed
        if closed then
          pure false
        else
          IO.sleep (UInt32.ofNat streamPumpSleepMs)
          loop
  loop

private partial def pumpResponseStream (stream : BodyStream) (q : StreamQueue) (cancel : CancelToken) : IO Unit := do
  let rec loop : IO Unit := do
    let canceled ← cancel.isCanceled
    if canceled then
      StreamQueue.close q
    else
      let res ← stream.next.run
      match res with
      | .ok (some chunk) =>
          let ok ← pushWithBackpressure q chunk cancel
          if ok then
            loop
          else
            StreamQueue.close q
      | .ok none =>
          StreamQueue.close q
      | .error _ =>
          StreamQueue.close q
  loop

private def resolveStreamResponse (sess : StreamSession) : IO Unit := do
  let ready? ← sess.respRef.get
  if ready?.isSome then
    pure ()
  else
    let finished ← IO.hasFinished sess.task
    if finished then
      let res ← IO.wait sess.task
      StreamQueue.close sess.reqQueue
      let resp :=
        match res with
        | .ok r => r
        | .error e => errorResponse (HttpError.internal s!"io error: {e}")
      match resp.bodyStream with
      | none =>
          sess.respRef.set (some resp)
      | some stream => do
          let stream ← BodyStream.prepend resp.body stream
          let q ← StreamQueue.new streamQueueCapacity
          let _ ← IO.asTask (pumpResponseStream stream q sess.cancel)
          let headResp := { resp with body := ByteArray.empty, bodyStream := none }
          sess.respRef.set (some headResp)
          sess.respQueue.set (some q)
    else
      pure ()

@[export lithe_stream_start]
def lithe_stream_start (app : UInt64) (reqBytes : ByteArray) : IO UInt64 := do
  let inst ← getInstance app
  let cancel ← CancelToken.new
  let reqQueue ← StreamQueue.new streamQueueCapacity
  let baseStream := BodyStream.fromQueue reqQueue
  let stream := BodyStream.withCancel baseStream cancel
  let task ← IO.asTask (do
    match decodeWireRequest reqBytes with
    | .ok wireReq =>
        let stream ← BodyStream.prepend wireReq.body stream
        let req := { wireReq.toRequest with body := ByteArray.empty, bodyStream := some stream }
        let ctx := RequestCtx.ofRequest req inst.state
        let ctx := RequestCtx.withCancelToken ctx cancel
        dispatch inst.router ctx
    | .error err =>
        pure (errorResponse (HttpError.badRequest err))
  )
  let respRef ← IO.mkRef (none : Option Response)
  let respQueue ← IO.mkRef (none : Option StreamQueue)
  let headSent ← IO.mkRef false
  let sess : StreamSession :=
    { task := task
    , cancel := cancel
    , reqQueue := reqQueue
    , respRef := respRef
    , respQueue := respQueue
    , headSent := headSent
    }
  registerStream sess

/--
Push a request body chunk. Returns:
- 1 if accepted
- 2 if full (retry)
- 0 if closed or missing
-/
@[export lithe_stream_push_body]
def lithe_stream_push_body (reqId : UInt64) (chunk : ByteArray) (isLast : UInt64) : IO UInt64 := do
  let sess? ← getStream? reqId
  match sess? with
  | none => pure 0
  | some sess =>
      let ok ← StreamQueue.push sess.reqQueue chunk
      if ok then
        if isLast != 0 then
          StreamQueue.close sess.reqQueue
        pure 1
      else
        let closed ← sess.reqQueue.isClosed
        if closed then
          pure 0
        else
          pure 2

/--
Poll for a stream response message. Returns empty when no message is ready.
-/
@[export lithe_stream_poll_response]
def lithe_stream_poll_response (reqId : UInt64) : IO ByteArray := do
  let sess? ← getStream? reqId
  match sess? with
  | none => pure ByteArray.empty
  | some sess => do
      resolveStreamResponse sess
      let resp? ← sess.respRef.get
      match resp? with
      | none => pure ByteArray.empty
      | some resp =>
          let sent ← sess.headSent.get
          if !sent then
            let respQ? ← sess.respQueue.get
            let isStream := respQ?.isSome
            let body := if isStream then ByteArray.empty else resp.body
            sess.headSent.set true
            if !isStream then
              removeStream reqId
            pure (encodeStreamHead resp.status.code resp.headers isStream body)
          else
            let respQ? ← sess.respQueue.get
            match respQ? with
            | none =>
                removeStream reqId
                pure ByteArray.empty
            | some q =>
                match (← q.pop?) with
                | some chunk =>
                    pure (encodeStreamChunk chunk)
                | none =>
                    let closed ← q.isClosed
                    if closed then
                      removeStream reqId
                      pure encodeStreamEnd
                    else
                      pure ByteArray.empty

/--
Cancel an in-flight stream request.
-/
@[export lithe_stream_cancel]
def lithe_stream_cancel (reqId : UInt64) : IO Unit :=
  cancelStream reqId

@[export lithe_ws_push]
def lithe_ws_push (wsId : UInt64) (msg : ByteArray) : IO UInt64 :=
  wsPushIn wsId msg

@[export lithe_ws_poll]
def lithe_ws_poll (wsId : UInt64) : IO ByteArray :=
  wsPopOut wsId

@[export lithe_ws_close]
def lithe_ws_close (wsId : UInt64) : IO Unit :=
  closeWS wsId

end Lithe
