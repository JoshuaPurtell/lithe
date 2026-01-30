# Lithe SSE & WebSocket Implementation Roadmap

## Overview

This document outlines the implementation plan for adding Server-Sent Events (SSE) and WebSocket support to Lithe, enabling real-time bidirectional communication.

## Goals

1. **SSE Support**: Unidirectional server → client streaming
2. **WebSocket Support**: Bidirectional communication
3. **Easy-to-use APIs**: Simple handlers and response builders
4. **Backward Compatible**: Existing code continues to work

## Implementation Phases

### Phase 1: SSE Support (Week 1)

**Complexity**: Low-Medium  
**Dependencies**: None (uses existing streaming)

#### Tasks

1. **Create `Lithe/Http/SSE.lean`**
   - `SSEEvent` structure with formatting
   - `Response.sse()` helper
   - `BodyStream.fromSSEEvents()` helper
   - Keepalive support

2. **Update `Lithe/Http/Response.lean`**
   - Add `Response.sse()` convenience method

3. **Create SSE Example**
   - `examples/sse/SSE.lean`
   - Demonstrates basic SSE streaming
   - Shows keepalive pattern

4. **Testing**
   - Unit tests for SSE formatting
   - Integration test with browser EventSource

**Deliverables**:
- ✅ SSE response helpers
- ✅ Working SSE example
- ✅ Tests passing

### Phase 2: WebSocket Support (Week 2)

**Complexity**: Medium-High  
**Dependencies**: Axum `ws` feature, `tokio-tungstenite`

#### Tasks

1. **Create `Lithe/Http/WebSocket.lean`**
   - `WSFrame`, `WSMessage` types
   - `WSConnection` structure
   - `WSHandler` type
   - Conversion to regular `Handler`

2. **Create `Lithe/Runtime/WSRegistry.lean`**
   - Connection tracking
   - Lifecycle management

3. **Update Rust Shim**
   - Add `axum` `ws` feature
   - Add `tokio-tungstenite` dependency
   - Implement WebSocket upgrade handler
   - Bridge WebSocket ↔ Lean streaming

4. **Create FFI Functions**
   - `lithe_ws_accept()` - Accept upgrade
   - `lithe_ws_send()` - Send message
   - `lithe_ws_receive()` - Receive message
   - `lithe_ws_close()` - Close connection

5. **Create WebSocket Example**
   - `examples/websocket/WebSocket.lean`
   - Echo server
   - Bidirectional chat

6. **Testing**
   - Unit tests for WebSocket frame encoding
   - Integration tests with WebSocket client
   - Connection lifecycle tests

**Deliverables**:
- ✅ WebSocket upgrade support
- ✅ Bidirectional communication
- ✅ Working WebSocket example
- ✅ Tests passing

### Phase 3: Integration & Polish (Week 3)

**Complexity**: Low  
**Dependencies**: Phases 1 & 2 complete

#### Tasks

1. **Combined Example**
   - Show SSE + WebSocket together
   - Crafter game example (if ready)

2. **Documentation**
   - API reference
   - Usage guide
   - Migration guide
   - Performance notes

3. **Performance Testing**
   - Concurrent connections
   - Message throughput
   - Memory usage

4. **Bug Fixes & Refinement**
   - Address issues found in testing
   - Optimize hot paths
   - Improve error messages

**Deliverables**:
- ✅ Complete documentation
- ✅ Performance benchmarks
- ✅ Production-ready code

## File Structure

```
Lithe/
├── Http/
│   ├── SSE.lean          # NEW: SSE helpers
│   ├── WebSocket.lean     # NEW: WebSocket types & handlers
│   └── Response.lean     # MODIFY: Add SSE helper
├── Runtime/
│   └── WSRegistry.lean   # NEW: WebSocket connection registry
└── FFI/
    └── WebSocket.lean    # NEW: WebSocket FFI functions

rust/lithe-shim/
├── src/
│   ├── websocket.rs      # NEW: WebSocket upgrade handler
│   └── lib.rs            # MODIFY: Add WebSocket route
└── Cargo.toml            # MODIFY: Add dependencies

examples/
├── sse/
│   └── SSE.lean          # NEW: SSE example
└── websocket/
    └── WebSocket.lean   # NEW: WebSocket example
```

## API Design

### SSE API

```lean
-- Create SSE response
Response.sse : BodyStream → Response

-- Format SSE event
SSEEvent.format : SSEEvent → String

-- Create SSE event
SSEEvent.mk (data : String) (id? : Option String) (event? : Option String) : SSEEvent
```

### WebSocket API

```lean
-- WebSocket handler type
WSHandler := WSConnection → RequestCtx → ExceptT HttpError IO Unit

-- Convert to regular handler
WSHandler.toHandler : WSHandler → Handler

-- Send message
WSConnection.send : WSMessage → ExceptT HttpError IO Unit
WSConnection.sendText : String → ExceptT HttpError IO Unit
WSConnection.sendJson : Json → ExceptT HttpError IO Unit

-- Receive message
WSConnection.receive : ExceptT HttpError IO (Option WSMessage)

-- Close connection
WSConnection.close : ExceptT HttpError IO Unit
```

## Testing Strategy

### Unit Tests
- SSE event formatting
- WebSocket frame encoding/decoding
- Connection registry operations

### Integration Tests
- SSE with browser EventSource
- WebSocket with `tokio-tungstenite` client
- Connection lifecycle (connect, send, receive, disconnect)

### Performance Tests
- Concurrent SSE connections (100+)
- Concurrent WebSocket connections (100+)
- Message throughput
- Memory usage under load

## Success Metrics

- ✅ SSE streams work with browser EventSource
- ✅ WebSocket upgrade works with standard clients
- ✅ Bidirectional communication works
- ✅ Examples run successfully
- ✅ Tests pass
- ✅ Documentation complete
- ✅ Performance acceptable (<100ms latency, >1000 msg/s)

## Risks & Mitigation

| Risk | Impact | Mitigation |
|------|--------|------------|
| WebSocket complexity | High | Start with SSE (simpler), learn from it |
| FFI integration issues | Medium | Prototype early, test frequently |
| Performance problems | Medium | Benchmark early, optimize hot paths |
| Breaking changes | Low | Keep backward compatible, version carefully |

## Timeline

- **Week 1**: SSE support (2-3 days) + testing (1-2 days)
- **Week 2**: WebSocket support (4-5 days)
- **Week 3**: Integration, docs, polish (3-5 days)

**Total**: ~2-3 weeks for complete implementation

## Next Steps

1. ✅ Plan created
2. ⏳ Review plan with team
3. ⏳ Start Phase 1 (SSE)
4. ⏳ Implement WebSocket after SSE
5. ⏳ Test & document
6. ⏳ Release

## References

- [SSE Spec](https://html.spec.whatwg.org/multipage/server-sent-events.html)
- [WebSocket Spec](https://tools.ietf.org/html/rfc6455)
- [Axum WebSocket](https://docs.rs/axum/latest/axum/extract/ws/index.html)
- [tokio-tungstenite](https://docs.rs/tokio-tungstenite/)
