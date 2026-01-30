#!/usr/bin/env bash
set -euo pipefail

export LITHE_EXAMPLE=websocket
cd rust/lithe-shim
cargo test websocket_echo -- --nocapture
