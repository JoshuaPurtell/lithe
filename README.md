# Lithe

Lithe is a lean (lightweight) webservice framework for **Lean 4** with an Axum-like router, extractors, and a compact binary wire format for the Rust shim.

## Quick start (Lean, in-memory)

```lean
import Lithe

open Lithe

def hello : Handler :=
  fun _ => pure (Response.text "hello")

def app : Router :=
  (Router.empty |> Router.get "/hello" hello)

def req : Request :=
  { method := Method.GET
  , path := "/hello"
  , query := ""
  , headers := #[]
  , body := ByteArray.empty
  }

#eval (Lithe.run app req)
```

## Install / use in your project

Lithe is a normal Lake package. Add it to your `lakefile.lean`:

```lean
require lithe from git "https://github.com/joshpurtell/lithe" @ "main"
```

Then build:

```bash
lake build
```

Notes:
- Requires a matching Lean toolchain (see `lean-toolchain` in this repo).
- The Rust shim is not published to crates.io; build it from source in `rust/lithe-shim` if you need HTTP/WS.

## Hello world (Rust shim + Lean app)

The Rust shim calls into a **Lean** app compiled from `examples/hello/Hello.lean`.

```bash
cd examples/hello
lake build

cd ../../rust/lithe-shim
cargo run
```

Then:

```bash
curl http://127.0.0.1:3000/hello
```

Use `LITHE_BIND=0.0.0.0:3000` to change the bind address.

## Runtime ABI (Rust ⇄ Lean)

The Rust shim calls into Lean using a small FFI surface. The current **streaming** ABI is:

- `lithe_stream_start(app_id, req_bytes) -> req_id`
- `lithe_stream_push_body(req_id, chunk, is_last) -> code` (1=accepted, 2=full/retry, 0=closed)
- `lithe_stream_poll_response(req_id) -> stream_msg | empty`
- `lithe_stream_cancel(req_id) -> ()`

`lithe_stream_poll_response` returns an empty `ByteArray` when no message is ready. The shim polls
until it receives a stream message (`head`, `chunk`, `end`) or cancels the request.

Legacy non-streaming async ABI (still available):

- `lithe_handle_async(app_id, req_bytes) -> req_id`
- `lithe_poll_response(req_id) -> resp_bytes | empty`
- `lithe_cancel_request(req_id) -> ()`

Rust-side timeout (optional):

- `LITHE_RUST_TIMEOUT_MS=...` sets a hard timeout in the shim.
- If unset, no Rust timeout is applied (Lean middleware timeouts still apply).

Cancellation behavior:

- If the handler future is dropped (e.g., client disconnect), the shim cancels the in-flight Lean task.
- Lean handlers can opt into cooperative cancellation via `checkCancel`, `sleepWithCancel`, or `awaitWithCancel`.

## Security notes

- TLS termination is **not** handled by Lithe. Run the shim behind a TLS proxy (Caddy/Nginx/Envoy) or add TLS at the Rust layer.
- For cookie-based sessions, set `Secure`, `HttpOnly`, and `SameSite=Lax/Strict`.
- CSRF protection for cookie auth is available via the double-submit middleware:

```lean
import Lithe

open Lithe

def app : Router :=
  (Router.empty
    |> Router.withMiddleware (csrf {})
    |> Router.post "/update" updateHandler)
```

The client should send the CSRF token in both a cookie (default: `csrf_token`) and a header
(default: `x-csrf-token`). By default, the middleware only checks requests authenticated via
`AuthInfo.scheme == "session"`.

## Project layout

- `Lithe/` — Lean framework core (router, extractors, middleware, codec)
- `Lithe/FFI/Exports.lean` — optional ABI helpers (JSON wire) used by examples
- `examples/hello` — standalone Lean app that exports FFI entrypoints
- `rust/lithe-shim` — Axum-based shim that bridges HTTP ⇄ Lean via JSON wire
