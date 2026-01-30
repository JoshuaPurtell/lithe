# Lithe

[![Version](https://img.shields.io/badge/version-0.1.0-green.svg)](https://github.com/JoshuaPurtell/lithe/releases)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Lean 4](https://img.shields.io/badge/Lean-4.27.0-orange)](https://lean-lang.org/)

A lightweight web framework for **[Lean 4](https://lean-lang.org/)** with an Axum-inspired router, type-safe extractors, and middleware.

> **What is Lean 4?** [Lean](https://lean-lang.org/) is a functional programming language and theorem prover developed by Microsoft Research. It combines a powerful type system with the ability to write mathematical proofs, making it ideal for building verified, high-assurance software.

## Features

- **Router** — Path parameters, query parsing, method routing
- **Extractors** — JSON, Form, Path, Query, Headers, Auth, State
- **Middleware** — CORS, CSRF, rate limiting, timeouts, logging, metrics
- **Streaming** — SSE, WebSocket, chunked responses
- **Storage** — SQLite integration via [lean-sqlite](https://github.com/leanprover/leansqlite)

## Installation

Add to your `lakefile.lean`:

```lean
-- Latest stable release (recommended)
require lithe from git "https://github.com/JoshuaPurtell/lithe" @ "v0.1.0"

-- Or track main branch (latest features, may be unstable)
require lithe from git "https://github.com/JoshuaPurtell/lithe" @ "main"
```

Then build:

```bash
lake build
```

> **Note:** Requires Lean 4.27.0+ (see `lean-toolchain`).

### Versioning

Lithe follows [Semantic Versioning](https://semver.org/). Pin to a specific version tag (e.g., `v0.1.0`) for stability in production.

## Quick Start

```lean
import Lithe

open Lithe

def hello : Handler :=
  fun _ => pure (Response.text "Hello, World!")

def app : Router :=
  Router.empty
    |> Router.get "/hello" hello

-- Test in-memory
#eval Lithe.run app { method := .GET, path := "/hello", query := "", headers := #[], body := .empty }
```

## Running with HTTP (Rust Shim)

For production HTTP serving, use the Rust shim:

```bash
cd examples/hello
lake build

cd ../../rust/lithe-shim
cargo run
```

```bash
curl http://127.0.0.1:3000/hello
# Hello, World!
```

### Environment Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `LITHE_BIND` | Bind address | `127.0.0.1:3000` |
| `LITHE_RUST_TIMEOUT_MS` | Request timeout (ms) | none |

## Middleware Example

```lean
import Lithe

open Lithe

def app : Router :=
  Router.empty
    |> Router.withMiddleware (cors { origins := #["https://example.com"] })
    |> Router.withMiddleware (rateLimit { maxRequests := 100, windowMs := 60000 })
    |> Router.get "/api/data" dataHandler
```

## Project Structure

```
Lithe/
├── Core/           # Handler, Context, Error types
├── Http/           # Request, Response, Status, WebSocket, SSE
├── Router/         # Path matching, routing
├── Extractor/      # JSON, Form, Path, Query extractors
├── Middleware/     # CORS, CSRF, Auth, Logging, etc.
├── Storage/        # SQLite integration
└── FFI/            # Rust shim exports
```

## Examples

| Example | Description |
|---------|-------------|
| `examples/hello` | Basic "Hello World" |
| `examples/streaming` | Chunked response streaming |
| `examples/sse` | Server-Sent Events |
| `examples/websocket` | WebSocket echo server |
| `examples/kitchen_sink` | All features combined |

## Security Notes

- **TLS**: Not handled by Lithe. Use a reverse proxy (Caddy/Nginx) or add TLS at the Rust layer.
- **CSRF**: Use the `csrf` middleware for cookie-based auth.
- **Sessions**: Set `Secure`, `HttpOnly`, `SameSite=Strict` on cookies.

## Demo: Lean Crafter

As a demonstration, I've built [Crafter](https://github.com/JoshuaPurtell/lean-crafter)—a 2D survival game—entirely in Lean 4 and hosted it on the web using Lithe.

🎮 **[Play it live](https://lean-crafter-production.up.railway.app/)** | 📦 **[Source code](https://github.com/JoshuaPurtell/lean-crafter)**

## License

MIT — see [LICENSE](LICENSE)
