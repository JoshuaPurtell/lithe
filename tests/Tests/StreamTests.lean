import Lithe.Http.BodyStream
import Lithe.Core.CancelToken
import Lithe.Http.Response
import Tests.Util

def testBodyStreamQueue : IO Unit := do
  let (stream, writer) ← Lithe.BodyStream.newQueuePair 32
  let _ ← (writer.push (Lithe.stringToBytes "a")).run
  let _ ← (writer.push (Lithe.stringToBytes "b")).run
  let _ ← (writer.close).run

  let first ← stream.next.run
  match first with
  | .ok (some chunk) =>
      assertEqBytes chunk (Lithe.stringToBytes "a") "stream chunk 1"
  | _ => throw (IO.userError "missing first stream chunk")

  let second ← stream.next.run
  match second with
  | .ok (some chunk) =>
      assertEqBytes chunk (Lithe.stringToBytes "b") "stream chunk 2"
  | _ => throw (IO.userError "missing second stream chunk")

  let third ← stream.next.run
  match third with
  | .ok none => pure ()
  | _ => throw (IO.userError "expected end of stream")

def testBodyStreamCancel : IO Unit := do
  let token ← Lithe.CancelToken.new
  let stream := Lithe.BodyStream.withCancel Lithe.BodyStream.empty token
  Lithe.CancelToken.cancel token
  let res ← stream.next.run
  match res with
  | .ok _ => throw (IO.userError "expected canceled stream error")
  | .error err =>
      assertEqNat err.status.toNat 499 "cancel status"

def testBodyWriterCancel : IO Unit := do
  let token ← Lithe.CancelToken.new
  let writer := Lithe.BodyWriter.withCancel Lithe.BodyWriter.discard token
  Lithe.CancelToken.cancel token
  let res ← (writer.push (Lithe.stringToBytes "x")).run
  match res with
  | .ok _ => throw (IO.userError "expected canceled writer error")
  | .error err =>
      assertEqNat err.status.toNat 499 "cancel status"
