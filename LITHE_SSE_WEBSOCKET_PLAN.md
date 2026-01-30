# Lithe SSE & WebSocket Support Plan

## Overview

Add support for Server-Sent Events (SSE) and WebSocket protocols to Lithe, enabling real-time bidirectional communication for applications like the Crafter web interface.

## Architecture

### Current State
- ✅ Streaming support via `BodyStream`
- ✅ Wire protocol for encoding/decoding
- ✅ Rust shim handles HTTP/streaming
- ✅ Response structure supports streaming

### What We're Adding
1. **SSE Support** - Unidirectional server → client streaming
2. **WebSocket Support** - Bidirectional communication
3. **Helper APIs** - Easy-to-use handlers and response builders

## Implementation Plan

### Phase 1: SSE Support (2-3 days)

#### 1.1 Lean Side - SSE Response Helpers

**File: `Lithe/Http/SSE.lean`** (new)

```lean
import Lithe.Http.Response
import Lithe.Http.BodyStream
import Lithe.Core.CancelToken

namespace Lithe

/-- SSE event structure --/
structure SSEEvent where
  id : Option String := none
  event : Option String := none
  data : String
  retry : Option Nat := none

namespace SSEEvent

def format (e : SSEEvent) : String :=
  let id := match e.id with
    | some id => s!"id: {id}\n"
    | none => ""
  let event := match e.event with
    | some evt => s!"event: {evt}\n"
    | none => ""
  let data := e.data.splitOn "\n" |>.map (fun line => s!"data: {line}") |>.join "\n"
  let retry := match e.retry with
    | some ms => s!"retry: {ms}\n"
    | none => ""
  s!"{id}{event}{data}\n\n"

end SSEEvent

namespace Response

/-- Create an SSE response --/
def sse (stream : BodyStream) : Response :=
  { status := Status.ok
  , headers := #[ 
      ("content-type", "text/event-stream")
    , ("cache-control", "no-cache")
    , ("connection", "keep-alive")
    , ("x-accel-buffering", "no")  -- Disable nginx buffering
    ]
  , body := ByteArray.empty
  , bodyStream := some stream
  }

/-- Create an SSE response with initial comment (for connection keepalive) --/
def sseWithComment (comment : String) (stream : BodyStream) : Response :=
  let commentBytes := stringToBytes s!": {comment}\n\n"
  let streamWithComment ← BodyStream.prepend commentBytes stream
  sse streamWithComment

end Response

namespace BodyStream

/-- Create an SSE stream from events --/
def fromSSEEvents (events : BodyStream) : BodyStream :=
  { next := do
      let chunk? ← events.next
      match chunk? with
      | none => pure none
      | some bytes =>
          -- Ensure chunks end with \n\n for SSE format
          let str := bytesToString bytes
          let formatted := if str.endsWith "\n\n" then str else s!"{str}\n\n"
          pure (some (stringToBytes formatted))
  }

/-- Create SSE stream that sends events periodically --/
def sseKeepalive (intervalMs : Nat := 30000) : BodyStream :=
  { next := do
      IO.sleep (UInt32.ofNat intervalMs)
      pure (some (stringToBytes ": keepalive\n\n"))
  }

end BodyStream

end Lithe
```

**File: `Lithe/Http/Response.lean`** (add to existing)

```lean
-- Add SSE helper
@[inline] def sse (stream : BodyStream) : Response :=
  Response.sse stream
```

#### 1.2 Rust Shim - SSE Handling

**File: `rust/lithe-shim/src/lib.rs`** (modify)

- SSE responses already work with existing streaming!
- Just need to ensure headers are preserved
- No changes needed if headers are set correctly in Lean

**Optional enhancement**: Add SSE-specific response detection and formatting

#### 1.3 Testing

**File: `examples/sse/SSE.lean`** (new)

```lean
import Lithe
import Lithe.Http.SSE

open Lithe

private def sseHandler : Handler :=
  fun ctx => do
    let (stream, writer) ← BodyStream.newQueuePair 1024
    -- Send initial comment
    writer.push (stringToBytes ": connected\n\n")
    
    -- Send periodic events
    let task ← IO.asTask do
      for i in [0:10] do
        IO.sleep 1000
        let event := SSEEvent.mk (data := s!"message {i}")
        writer.push (stringToBytes (SSEEvent.format event))
      writer.close
    
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
```

### Phase 2: WebSocket Support (4-5 days)

#### 2.1 Lean Side - WebSocket Types & Helpers

**File: `Lithe/Http/WebSocket.lean`** (new)

```lean
import Lithe.Prelude
import Lithe.Core.Context
import Lithe.Core.Handler
import Lithe.Core.Error
import Lithe.Http.Response
import Lithe.Http.BodyStream
import Lithe.Core.CancelToken

namespace Lithe

/-- WebSocket frame types --/
inductive WSFrameType where
  | text
  | binary
  | close
  | ping
  | pong
  | continuation

/-- WebSocket frame --/
structure WSFrame where
  opcode : WSFrameType
  payload : ByteArray
  fin : Bool := true

/-- WebSocket message (can span multiple frames) --/
structure WSMessage where
  text : Option String := none
  binary : Option ByteArray := none
  isText : Bool := true

namespace WSMessage

def ofText (s : String) : WSMessage :=
  { text := some s, isText := true }

def ofBinary (b : ByteArray) : WSMessage :=
  { binary := some b, isText := false }

def toBytes (msg : WSMessage) : ByteArray :=
  match msg.text with
  | some s => stringToBytes s
  | none => msg.binary.getD ByteArray.empty

end WSMessage

/-- WebSocket connection handler --/
structure WSConnection where
  send : WSMessage → ExceptT HttpError IO Unit
  receive : ExceptT HttpError IO (Option WSMessage)
  close : ExceptT HttpError IO Unit
  cancel : CancelToken

namespace WSConnection

/-- Send text message --/
def sendText (conn : WSConnection) (text : String) : ExceptT HttpError IO Unit :=
  conn.send (WSMessage.ofText text)

/-- Send binary message --/
def sendBinary (conn : WSConnection) (data : ByteArray) : ExceptT HttpError IO Unit :=
  conn.send (WSMessage.ofBinary data)

/-- Send JSON message --/
def sendJson (conn : WSConnection) (j : Lean.Json) : ExceptT HttpError IO Unit :=
  conn.sendText (Lean.Json.compress j)

end WSConnection

/-- WebSocket handler type --/
abbrev WSHandler := WSConnection → RequestCtx → ExceptT HttpError IO Unit

/-- Convert WSHandler to regular Handler --/
def WSHandler.toHandler (h : WSHandler) : Handler :=
  fun ctx => do
    -- Check for WebSocket upgrade request
    let upgrade? := ctx.request.headers.find? (fun (k, _) => k.toLower == "upgrade")
    let wsKey? := ctx.request.headers.find? (fun (k, _) => k.toLower == "sec-websocket-key")
    
    match (upgrade?, wsKey?) with
    | (some (_, "websocket"), some (_, key)) =>
        -- TODO: Implement WebSocket upgrade
        -- For now, return upgrade response
        throw (HttpError.badRequest "WebSocket upgrade not yet implemented")
    | _ =>
        throw (HttpError.badRequest "Not a WebSocket upgrade request")

end Lithe
```

#### 2.2 Rust Shim - WebSocket Upgrade

**File: `rust/lithe-shim/Cargo.toml`** (modify)

```toml
[dependencies]
axum = { version = "0.6", features = ["ws"] }  # Add ws feature
tokio-tungstenite = "0.21"  # WebSocket library
```

**File: `rust/lithe-shim/src/websocket.rs`** (new)

```rust
use axum::extract::ws::{Message, WebSocket, WebSocketUpgrade};
use axum::response::Response;
use std::sync::Arc;
use tokio::sync::mpsc;

pub struct WSConnection {
    pub tx: mpsc::UnboundedSender<Message>,
    pub rx: mpsc::UnboundedReceiver<Message>,
}

impl WSConnection {
    pub fn new() -> (Self, Self) {
        let (tx1, rx1) = mpsc::unbounded_channel();
        let (tx2, rx2) = mpsc::unbounded_channel();
        (
            Self { tx: tx1, rx: rx2 },
            Self { tx: tx2, rx: rx1 },
        )
    }
}

pub async fn handle_websocket_upgrade(
    ws: WebSocketUpgrade,
    app_id: u64,
    // ... other params
) -> Response {
    ws.on_upgrade(|socket| handle_socket(socket, app_id))
}

async fn handle_socket(socket: WebSocket, app_id: u64) {
    // Split socket into sender/receiver
    let (mut sender, mut receiver) = socket.split();
    
    // Create channels for bidirectional communication
    let (client_tx, mut client_rx) = mpsc::unbounded_channel();
    let (server_tx, mut server_rx) = mpsc::unbounded_channel();
    
    // Spawn task to forward messages from Lean to WebSocket
    let send_task = tokio::spawn(async move {
        while let Some(msg) = server_rx.recv().await {
            if sender.send(msg).await.is_err() {
                break;
            }
        }
    });
    
    // Spawn task to forward messages from WebSocket to Lean
    let recv_task = tokio::spawn(async move {
        while let Some(Ok(msg)) = receiver.next().await {
            match msg {
                Message::Text(text) => {
                    // Send to Lean via FFI
                    // TODO: Implement
                }
                Message::Binary(data) => {
                    // Send to Lean via FFI
                    // TODO: Implement
                }
                Message::Close(_) => break,
                Message::Ping(data) => {
                    // Handle ping
                }
                Message::Pong(_) => {}
            }
        }
    });
    
    // Wait for tasks
    tokio::select! {
        _ = send_task => {}
        _ = recv_task => {}
    }
}
```

#### 2.3 FFI Integration

**File: `Lithe/FFI/WebSocket.lean`** (new)

```lean
-- FFI functions for WebSocket handling
-- These will be called from Rust shim

@[export lithe_ws_accept]
def lithe_ws_accept (reqId : UInt64) : IO ByteArray :=
  -- Return WebSocket accept response
  pure ByteArray.empty

@[export lithe_ws_send]
def lithe_ws_send (connId : UInt64) (msg : ByteArray) : IO UInt32 :=
  -- Send message through WebSocket
  pure 0

@[export lithe_ws_receive]
def lithe_ws_receive (connId : UInt64) : IO ByteArray :=
  -- Receive message from WebSocket
  pure ByteArray.empty

@[export lithe_ws_close]
def lithe_ws_close (connId : UInt64) : IO Unit :=
  -- Close WebSocket connection
  pure ()
```

#### 2.4 WebSocket Registry

**File: `Lithe/Runtime/WSRegistry.lean`** (new)

```lean
-- Track active WebSocket connections
-- Similar to StreamRegistry but for WebSocket connections

structure WSConnection where
  connId : UInt64
  -- ... other fields

initialize wsConnections : IO.Ref (Std.HashMap UInt64 WSConnection) ← IO.mkRef {}

def registerWS (conn : WSConnection) : IO UInt64 := do
  -- Register connection
  pure conn.connId

def getWS? (connId : UInt64) : IO (Option WSConnection) := do
  -- Get connection
  pure none

def removeWS (connId : UInt64) : IO Unit := do
  -- Remove connection
  pure ()
```

### Phase 3: Integration & Testing (2-3 days)

#### 3.1 Update Examples

- Add SSE example
- Add WebSocket example
- Add combined example (SSE for updates, WebSocket for actions)

#### 3.2 Documentation

- API documentation for SSE helpers
- API documentation for WebSocket handlers
- Usage examples
- Migration guide from polling to SSE/WebSocket

#### 3.3 Testing

- Unit tests for SSE formatting
- Unit tests for WebSocket frame encoding/decoding
- Integration tests with real HTTP clients
- Performance testing

## API Design

### SSE Usage Example

```lean
import Lithe
import Lithe.Http.SSE

def gameStateStream : Handler :=
  fun ctx => do
    let sessionId ← Path.param "id" String ctx
    let (stream, writer) ← BodyStream.newQueuePair 1024
    
    -- Send initial connection message
    writer.push (stringToBytes ": connected\n\n")
    
    -- Stream game state updates
    let task ← IO.asTask do
      loop do
        let state ← getGameState sessionId
        let event := SSEEvent.mk (data := state.toJson)
        writer.push (stringToBytes (SSEEvent.format event))
        IO.sleep 16  -- ~60fps
    
    return Response.sse stream
```

### WebSocket Usage Example

```lean
import Lithe
import Lithe.Http.WebSocket

def gameWebSocket : WSHandler :=
  fun conn ctx => do
    let sessionId ← Path.param "id" String ctx
    
    -- Send welcome message
    conn.sendText "Connected to game session"
    
    -- Handle incoming messages
    loop do
      let msg? ← conn.receive
      match msg? with
      | none => break  -- Connection closed
      | some msg =>
          match msg.text with
          | some "ping" => conn.sendText "pong"
          | some actionJson =>
              let action ← parseAction actionJson
              let result ← executeAction sessionId action
              conn.sendJson result.toJson
          | none => pure ()  -- Binary message, ignore for now
```

## Implementation Order

1. **Week 1**: SSE support (simpler, unidirectional)
   - Day 1-2: Lean SSE helpers
   - Day 3: Rust shim verification (should work as-is)
   - Day 4: Testing & examples

2. **Week 2**: WebSocket support (more complex, bidirectional)
   - Day 1-2: Lean WebSocket types & handlers
   - Day 3-4: Rust shim WebSocket upgrade
   - Day 5: FFI integration & testing

3. **Week 3**: Integration & polish
   - Day 1-2: Combined examples
   - Day 3: Documentation
   - Day 4-5: Testing & bug fixes

## Open Questions

1. **WebSocket Protocol**: Use `tokio-tungstenite` or implement raw WebSocket?
   - Recommendation: Use `tokio-tungstenite` (battle-tested)

2. **Connection Management**: How to handle WebSocket connection lifecycle?
   - Store in registry similar to streams
   - Cleanup on disconnect

3. **Message Format**: JSON for all messages or support binary?
   - Start with JSON, add binary later if needed

4. **Error Handling**: How to handle WebSocket errors?
   - Close connection on error
   - Log errors

5. **Performance**: How many concurrent WebSocket connections?
   - Start simple, optimize later

## Success Criteria

- ✅ SSE streams work end-to-end
- ✅ WebSocket upgrade works
- ✅ Bidirectional WebSocket communication works
- ✅ Examples demonstrate both patterns
- ✅ Documentation is complete
- ✅ Tests pass

## Future Enhancements

- WebSocket subprotocols
- Compression (permessage-deflate)
- Connection pooling
- Rate limiting for WebSocket messages
- Metrics for WebSocket connections
