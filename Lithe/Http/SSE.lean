import Lithe.Prelude
import Lithe.Http.BodyStream

namespace Lithe

/--
Server-Sent Events (SSE) event.
- `data` is optional to allow comment-only keepalive frames.
- `comment` is sent as ":" lines and does not dispatch to clients.
- `retryMs` sets the reconnection time in milliseconds.
-/
structure SSEEvent where
  data : Option String := none
  id? : Option String := none
  event? : Option String := none
  retryMs? : Option Nat := none
  comment? : Option String := none

namespace SSEEvent

@[inline] def ofData (data : String) (id? : Option String := none) (event? : Option String := none) : SSEEvent :=
  { data := some data, id? := id?, event? := event? }

@[inline] def comment (msg : String) : SSEEvent :=
  { data := none, comment? := some msg }

@[inline] def keepAlive (msg : String := "keepalive") : SSEEvent :=
  comment msg

private def pushLines (lines : Array String) (pref : String) (value : String) : Array String :=
  let parts := value.splitOn "\n"
  parts.foldl (init := lines) (fun acc line => acc.push s!"{pref}{line}")

@[inline] def format (e : SSEEvent) : String :=
  Id.run do
    let mut lines : Array String := #[]
    match e.comment? with
    | some msg =>
        let parts := msg.splitOn "\n"
        for line in parts do
          lines := lines.push s!": {line}"
    | none => ()
    match e.id? with
    | some id => lines := lines.push s!"id: {id}"
    | none => ()
    match e.event? with
    | some ev => lines := lines.push s!"event: {ev}"
    | none => ()
    match e.retryMs? with
    | some ms => lines := lines.push s!"retry: {ms}"
    | none => ()
    match e.data with
    | some data =>
        lines := pushLines lines "data: " data
    | none => ()
    let payload := String.intercalate "\n" lines.toList
    return payload ++ "\n\n"

@[inline] def toBytes (e : SSEEvent) : ByteArray :=
  stringToBytes (format e)

end SSEEvent

namespace BodyStream

/--
Create a BodyStream that emits a fixed list of SSE events.
Each event is formatted and emitted as a single chunk.
-/
@[inline] def fromSSEEvents (events : Array SSEEvent) : IO BodyStream := do
  let idxRef ← IO.mkRef 0
  let eventsList := events.toList
  let rec listGet? (xs : List SSEEvent) (idx : Nat) : Option SSEEvent :=
    match xs, idx with
    | [], _ => none
    | x :: _, 0 => some x
    | _ :: rest, Nat.succ n => listGet? rest n
  let arrayGet? (idx : Nat) : Option SSEEvent :=
    listGet? eventsList idx
  pure {
    next := do
      let idx ← idxRef.get
      match arrayGet? idx with
      | none => pure none
      | some ev =>
          idxRef.set (idx + 1)
          pure (some (SSEEvent.toBytes ev))
  }

end BodyStream

end Lithe
