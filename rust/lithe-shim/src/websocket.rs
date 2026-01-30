use axum::extract::ws::{Message, WebSocket};
use futures_util::{SinkExt, StreamExt};
use std::time::Duration;

use crate::{ffi, init_lean, POLL_INTERVAL_MS};

const WS_PUSH_CLOSED: u64 = 0;
const WS_PUSH_OK: u64 = 1;
const WS_PUSH_FULL: u64 = 2;

const WS_KIND_TEXT: u8 = 0;
const WS_KIND_BINARY: u8 = 1;
const WS_KIND_CLOSE: u8 = 2;
const WS_KIND_PING: u8 = 3;
const WS_KIND_PONG: u8 = 4;

fn ws_push(ws_id: u64, msg: &[u8]) -> u64 {
    unsafe {
        init_lean();
        let msg_arr = ffi::mk_byte_array(msg);
        let res = ffi::lithe_ws_push(ws_id, msg_arr);
        ffi::lithe_lean_dec(msg_arr);
        ffi::unwrap_io_result(res, |val| ffi::lithe_lean_unbox_uint64(val))
    }
}

fn ws_poll(ws_id: u64) -> Option<Vec<u8>> {
    unsafe {
        init_lean();
        let res = ffi::lithe_ws_poll(ws_id);
        ffi::unwrap_io_result(res, |val| {
            let bytes = ffi::byte_array_to_vec(val);
            if bytes.is_empty() {
                None
            } else {
                Some(bytes)
            }
        })
    }
}

fn ws_close(ws_id: u64) {
    unsafe {
        init_lean();
        let res = ffi::lithe_ws_close(ws_id);
        ffi::unwrap_io_result(res, |_| ());
    }
}

fn encode_message(msg: Message) -> Option<Vec<u8>> {
    let mut out = Vec::new();
    match msg {
        Message::Text(text) => {
            out.push(WS_KIND_TEXT);
            out.extend_from_slice(text.as_bytes());
        }
        Message::Binary(bin) => {
            out.push(WS_KIND_BINARY);
            out.extend_from_slice(&bin);
        }
        Message::Close(_) => {
            out.push(WS_KIND_CLOSE);
        }
        Message::Ping(payload) => {
            out.push(WS_KIND_PING);
            out.extend_from_slice(&payload);
        }
        Message::Pong(payload) => {
            out.push(WS_KIND_PONG);
            out.extend_from_slice(&payload);
        }
    }
    Some(out)
}

fn decode_message(bytes: &[u8]) -> Option<Message> {
    if bytes.is_empty() {
        return None;
    }
    let kind = bytes[0];
    let payload = &bytes[1..];
    match kind {
        WS_KIND_TEXT => String::from_utf8(payload.to_vec())
            .ok()
            .map(Message::Text)
            .or_else(|| Some(Message::Binary(payload.to_vec()))),
        WS_KIND_BINARY => Some(Message::Binary(payload.to_vec())),
        WS_KIND_CLOSE => Some(Message::Close(None)),
        WS_KIND_PING => Some(Message::Ping(payload.to_vec())),
        WS_KIND_PONG => Some(Message::Pong(payload.to_vec())),
        _ => None,
    }
}

async fn push_with_backpressure(ws_id: u64, msg: &[u8]) -> bool {
    loop {
        match ws_push(ws_id, msg) {
            WS_PUSH_OK => return true,
            WS_PUSH_FULL => {
                tokio::time::sleep(Duration::from_millis(POLL_INTERVAL_MS)).await;
            }
            WS_PUSH_CLOSED => return false,
            _ => return false,
        }
    }
}

pub async fn handle_socket(socket: WebSocket, ws_id: u64) {
    init_lean();
    let (mut sender, mut receiver) = socket.split();

    let send_task = tokio::spawn(async move {
        loop {
            if let Some(bytes) = ws_poll(ws_id) {
                if let Some(msg) = decode_message(&bytes) {
                    let is_close = matches!(msg, Message::Close(_));
                    if sender.send(msg).await.is_err() {
                        break;
                    }
                    if is_close {
                        break;
                    }
                }
            } else {
                tokio::time::sleep(Duration::from_millis(POLL_INTERVAL_MS)).await;
            }
        }
    });

    while let Some(msg) = receiver.next().await {
        match msg {
            Ok(msg) => {
                let is_close = matches!(msg, Message::Close(_));
                if let Some(encoded) = encode_message(msg) {
                    if !push_with_backpressure(ws_id, &encoded).await {
                        break;
                    }
                }
                if is_close {
                    break;
                }
            }
            Err(_) => break,
        }
    }

    ws_close(ws_id);
    send_task.abort();
}

#[cfg(test)]
mod tests {
    use super::*;
    use axum::extract::ws::Message;

    #[test]
    fn ws_encode_decode_roundtrip() {
        let text = Message::Text("hello".into());
        let encoded = encode_message(text).expect("encode text");
        let decoded = decode_message(&encoded).expect("decode text");
        assert!(matches!(decoded, Message::Text(t) if t == "hello"));

        let bin = Message::Binary(vec![1, 2, 3]);
        let encoded = encode_message(bin).expect("encode bin");
        let decoded = decode_message(&encoded).expect("decode bin");
        assert!(matches!(decoded, Message::Binary(b) if b == vec![1, 2, 3]));

        let ping = Message::Ping(vec![9]);
        let encoded = encode_message(ping).expect("encode ping");
        let decoded = decode_message(&encoded).expect("decode ping");
        assert!(matches!(decoded, Message::Ping(b) if b == vec![9]));

        let pong = Message::Pong(vec![8]);
        let encoded = encode_message(pong).expect("encode pong");
        let decoded = decode_message(&encoded).expect("decode pong");
        assert!(matches!(decoded, Message::Pong(b) if b == vec![8]));

        let close = Message::Close(None);
        let encoded = encode_message(close).expect("encode close");
        let decoded = decode_message(&encoded).expect("decode close");
        assert!(matches!(decoded, Message::Close(_)));
    }

    #[test]
    fn ws_decode_fuzzish() {
        let mut seed = 7u32;
        for len in 0..128usize {
            let mut data = vec![0u8; len];
            for b in data.iter_mut() {
                seed = seed.wrapping_mul(1664525).wrapping_add(1013904223);
                *b = (seed >> 24) as u8;
            }
            let _ = decode_message(&data);
        }
    }
}
