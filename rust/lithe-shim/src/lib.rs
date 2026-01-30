pub mod ffi;
pub mod wire;
pub mod websocket;

use axum::{
    body::Body,
    extract::{ConnectInfo, FromRequestParts, State},
    http::{HeaderMap, HeaderName, HeaderValue, Request, Response, StatusCode},
    routing::any,
    Router,
};
use axum::extract::ws::WebSocketUpgrade;
use axum::response::IntoResponse;
use bytes::Bytes;
use hyper::body::HttpBody as _;
use std::cell::Cell;
use std::net::SocketAddr;
use std::sync::{Once, OnceLock};
use std::time::{Duration, Instant};
use tracing::warn;

#[derive(Clone)]
pub struct AppState {
    pub app_id: u64,
}

static START: Once = Once::new();
static RUST_TIMEOUT: OnceLock<Option<Duration>> = OnceLock::new();
const POLL_INTERVAL_MS: u64 = 5;
const PUSH_CLOSED: u64 = 0;
const PUSH_OK: u64 = 1;
const PUSH_FULL: u64 = 2;
thread_local! {
    static LEAN_THREAD_INIT: Cell<bool> = Cell::new(false);
}

fn init_lean_thread() {
    LEAN_THREAD_INIT.with(|cell| {
        if !cell.get() {
            unsafe {
                ffi::lean_initialize_thread();
            }
            cell.set(true);
        }
    });
}

pub fn init_lean() {
    START.call_once(|| unsafe {
        ffi::lean_initialize_runtime_module();
        ffi::lean_initialize();
        ffi::lean_init_task_manager();
        init_lean_thread();
        init_example();
    });
    init_lean_thread();
}

#[cfg(lithe_example = "hello")]
unsafe fn init_example() {
    let init_res = ffi::initialize_hello_Hello(0);
    ffi::unwrap_io_result(init_res, |_| ());
}

#[cfg(lithe_example = "crafter")]
unsafe fn init_example() {
    let init_res = ffi::initialize_crafter_Crafter(0);
    ffi::unwrap_io_result(init_res, |_| ());
}

#[cfg(not(any(lithe_example = "hello", lithe_example = "crafter")))]
unsafe fn init_example() {}

fn headers_to_vec(headers: &HeaderMap) -> Vec<(String, String)> {
    headers
        .iter()
        .filter_map(|(name, value)| {
            let value = value.to_str().ok()?;
            Some((name.as_str().to_string(), value.to_string()))
        })
        .collect()
}

fn rust_timeout() -> Option<Duration> {
    *RUST_TIMEOUT.get_or_init(|| {
        std::env::var("LITHE_RUST_TIMEOUT_MS")
            .ok()
            .and_then(|v| v.parse::<u64>().ok())
            .filter(|ms| *ms > 0)
            .map(Duration::from_millis)
    })
}

fn apply_headers(
    mut builder: axum::http::response::Builder,
    headers: Vec<(String, String)>,
) -> axum::http::response::Builder {
    for (k, v) in headers {
        if let (Ok(name), Ok(value)) = (
            HeaderName::from_bytes(k.as_bytes()),
            HeaderValue::from_str(&v),
        ) {
            builder = builder.header(name, value);
        }
    }
    builder
}

fn head_to_response(status: u16, headers: Vec<(String, String)>, body: Body) -> Response<Body> {
    let builder = Response::builder().status(status);
    let builder = apply_headers(builder, headers);
    builder.body(body).unwrap_or_else(|_| {
        Response::builder()
            .status(StatusCode::INTERNAL_SERVER_ERROR)
            .body(Body::from("invalid response"))
            .unwrap()
    })
}

fn handle_sync(app_id: u64, payload: &[u8]) -> Vec<u8> {
    unsafe {
        init_lean();
        let req_arr = ffi::mk_byte_array(payload);
        let res = ffi::lithe_handle(app_id, req_arr);
        ffi::lithe_lean_dec(req_arr);
        ffi::unwrap_io_result(res, |val| ffi::byte_array_to_vec(val))
    }
}

fn header_value(headers: &[(String, String)], name: &str) -> Option<String> {
    let target = name.trim().to_lowercase();
    headers
        .iter()
        .find(|(k, _)| k.trim().to_lowercase() == target)
        .map(|(_, v)| v.clone())
}

fn ws_header_allowed(name: &str) -> bool {
    let key = name.trim().to_lowercase();
    !matches!(
        key.as_str(),
        "x-lithe-ws-id"
            | "connection"
            | "upgrade"
            | "sec-websocket-accept"
            | "sec-websocket-key"
            | "sec-websocket-version"
            | "content-length"
            | "transfer-encoding"
    )
}

// Cancels the in-flight Lean stream if the handler is dropped (e.g., client disconnect).
struct StreamGuard {
    req_id: u64,
    active: bool,
}

impl StreamGuard {
    fn new(req_id: u64) -> Self {
        Self {
            req_id,
            active: true,
        }
    }

    fn complete(&mut self) {
        self.active = false;
    }
}

impl Drop for StreamGuard {
    fn drop(&mut self) {
        if self.active {
            stream_cancel(self.req_id);
        }
    }
}

fn stream_start(app_id: u64, payload: &[u8]) -> u64 {
    unsafe {
        init_lean();
        let req_arr = ffi::mk_byte_array(payload);
        let res = ffi::lithe_stream_start(app_id, req_arr);
        ffi::lithe_lean_dec(req_arr);
        ffi::unwrap_io_result(res, |val| ffi::lithe_lean_unbox_uint64(val))
    }
}

fn stream_push_body(req_id: u64, chunk: &[u8], is_last: bool) -> u64 {
    unsafe {
        init_lean();
        let chunk_arr = ffi::mk_byte_array(chunk);
        let res = ffi::lithe_stream_push_body(req_id, chunk_arr, if is_last { 1 } else { 0 });
        ffi::lithe_lean_dec(chunk_arr);
        ffi::unwrap_io_result(res, |val| ffi::lithe_lean_unbox_uint64(val))
    }
}

fn stream_poll_response(req_id: u64) -> Option<Vec<u8>> {
    unsafe {
        init_lean();
        let res = ffi::lithe_stream_poll_response(req_id);
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

fn stream_cancel(req_id: u64) {
    unsafe {
        init_lean();
        let res = ffi::lithe_stream_cancel(req_id);
        ffi::unwrap_io_result(res, |_| ());
    }
}

async fn push_request_body(req_id: u64, mut body: Body) {
    while let Some(next) = body.data().await {
        match next {
            Ok(chunk) => {
                let bytes = chunk.to_vec();
                loop {
                    match stream_push_body(req_id, &bytes, false) {
                        PUSH_OK => break,
                        PUSH_FULL => {
                            tokio::time::sleep(Duration::from_millis(POLL_INTERVAL_MS)).await;
                        }
                        _ => return,
                    }
                }
            }
            Err(err) => {
                warn!(error = %err, "failed to read request body chunk");
                stream_cancel(req_id);
                return;
            }
        }
    }

    loop {
        match stream_push_body(req_id, &[], true) {
            PUSH_OK | PUSH_CLOSED => break,
            PUSH_FULL => {
                tokio::time::sleep(Duration::from_millis(POLL_INTERVAL_MS)).await;
            }
            _ => break,
        }
    }
}

async fn handle(
    State(state): State<AppState>,
    ConnectInfo(addr): ConnectInfo<SocketAddr>,
    req: Request<Body>,
) -> Response<Body> {
    init_lean();

    let (mut parts, body) = req.into_parts();

    if let Ok(ws) = WebSocketUpgrade::from_request_parts(&mut parts, &state).await {
        let headers = headers_to_vec(&parts.headers);
        let remote = Some(addr.to_string());
        let payload = match wire::encode_request(
            &parts.method,
            parts.uri.path(),
            parts.uri.query().unwrap_or(""),
            &headers,
            &[],
            remote.as_deref(),
        ) {
            Ok(v) => v,
            Err(err) => {
                warn!(error = %err, "failed to encode wire request");
                return Response::builder()
                    .status(StatusCode::INTERNAL_SERVER_ERROR)
                    .body(Body::from("encode error"))
                    .unwrap();
            }
        };

        let resp_bytes = handle_sync(state.app_id, &payload);
        match wire::decode_response(&resp_bytes) {
            Ok(wire_resp) => {
                if let Some(id_str) = header_value(&wire_resp.headers, "x-lithe-ws-id") {
                    if let Ok(ws_id) = id_str.parse::<u64>() {
                        let mut resp = ws
                            .on_upgrade(move |socket| websocket::handle_socket(socket, ws_id))
                            .into_response();
                        for (k, v) in wire_resp.headers {
                            if !ws_header_allowed(&k) {
                                continue;
                            }
                            if let (Ok(name), Ok(value)) = (
                                HeaderName::from_bytes(k.as_bytes()),
                                HeaderValue::from_str(&v),
                            ) {
                                resp.headers_mut().insert(name, value);
                            }
                        }
                        return resp;
                    }
                }
                return head_to_response(wire_resp.status, wire_resp.headers, Body::from(wire_resp.body));
            }
            Err(err) => {
                warn!(error = %err, "failed to decode wire response");
                return Response::builder()
                    .status(StatusCode::INTERNAL_SERVER_ERROR)
                    .body(Body::from("decode error"))
                    .unwrap();
            }
        }
    }
    let headers = headers_to_vec(&parts.headers);
    let remote = Some(addr.to_string());
    let payload = match wire::encode_request(
        &parts.method,
        parts.uri.path(),
        parts.uri.query().unwrap_or(""),
        &headers,
        &[],
        remote.as_deref(),
    ) {
        Ok(v) => v,
        Err(err) => {
            warn!(error = %err, "failed to encode wire request");
            return Response::builder()
                .status(StatusCode::INTERNAL_SERVER_ERROR)
                .body(Body::from("encode error"))
                .unwrap();
        }
    };

    let req_id = stream_start(state.app_id, &payload);
    let mut guard = StreamGuard::new(req_id);
    tokio::spawn(push_request_body(req_id, body));
    let started = Instant::now();
    let timeout = rust_timeout();
    let (status, headers, is_stream, head_body) = loop {
        if let Some(bytes) = stream_poll_response(req_id) {
            match wire::decode_stream_msg(&bytes) {
                Ok(wire::StreamMsg::Head {
                    status,
                    headers,
                    is_stream,
                    body,
                }) => break (status, headers, is_stream, body),
                Ok(_) => {}
                Err(err) => {
                    warn!(error = %err, "failed to decode stream response");
                    stream_cancel(req_id);
                    guard.complete();
                    return Response::builder()
                        .status(StatusCode::INTERNAL_SERVER_ERROR)
                        .body(Body::from("decode error"))
                        .unwrap();
                }
            }
        }
        if let Some(limit) = timeout {
            if started.elapsed() >= limit {
                stream_cancel(req_id);
                guard.complete();
                return Response::builder()
                    .status(StatusCode::GATEWAY_TIMEOUT)
                    .body(Body::from("request timed out"))
                    .unwrap();
            }
        }
        tokio::time::sleep(Duration::from_millis(POLL_INTERVAL_MS)).await;
    };

    if !is_stream {
        guard.complete();
        return head_to_response(status, headers, Body::from(head_body));
    }

    let (mut sender, stream_body) = Body::channel();
    let mut stream_guard = guard;
    tokio::spawn(async move {
        if !head_body.is_empty() {
            if sender.send_data(Bytes::from(head_body)).await.is_err() {
                stream_cancel(req_id);
                stream_guard.complete();
                return;
            }
        }
        loop {
            if let Some(bytes) = stream_poll_response(req_id) {
                match wire::decode_stream_msg(&bytes) {
                    Ok(wire::StreamMsg::Chunk(chunk)) => {
                        if sender.send_data(Bytes::from(chunk)).await.is_err() {
                            stream_cancel(req_id);
                            stream_guard.complete();
                            return;
                        }
                    }
                    Ok(wire::StreamMsg::End) => {
                        stream_guard.complete();
                        return;
                    }
                    Ok(wire::StreamMsg::Head { .. }) => {}
                    Err(err) => {
                        warn!(error = %err, "failed to decode stream chunk");
                        stream_cancel(req_id);
                        stream_guard.complete();
                        return;
                    }
                }
            } else {
                tokio::time::sleep(Duration::from_millis(POLL_INTERVAL_MS)).await;
            }
        }
    });

    head_to_response(status, headers, stream_body)
}

pub fn new_app_id(name: &str) -> u64 {
    unsafe {
        init_lean();
        let name_arr = ffi::mk_byte_array(name.as_bytes());
        let res = ffi::lithe_new_app_named(name_arr);
        ffi::lithe_lean_dec(name_arr);
        ffi::unwrap_io_result(res, |val| ffi::lithe_lean_unbox_uint64(val))
    }
}

pub fn shutdown_lean(app_id: u64) {
    unsafe {
        let res = ffi::lithe_free_app(app_id);
        ffi::unwrap_io_result(res, |_| ());
        ffi::lean_finalize_task_manager();
    }
}

pub fn make_router(app_id: u64) -> Router {
    let app_state = AppState { app_id };
    Router::new()
        .route("/", any(handle))
        .fallback(handle)
        .with_state(app_state)
}

pub async fn serve_with_shutdown<F>(
    addr: SocketAddr,
    app_id: u64,
    shutdown: F,
) -> Result<(), Box<dyn std::error::Error + Send + Sync>>
where
    F: std::future::Future<Output = ()> + Send + 'static,
{
    let app = make_router(app_id);
    axum::Server::bind(&addr)
        .serve(app.into_make_service_with_connect_info::<SocketAddr>())
        .with_graceful_shutdown(shutdown)
        .await?;
    Ok(())
}

pub async fn serve_with_listener<F>(
    listener: std::net::TcpListener,
    app_id: u64,
    shutdown: F,
) -> Result<(), Box<dyn std::error::Error + Send + Sync>>
where
    F: std::future::Future<Output = ()> + Send + 'static,
{
    listener.set_nonblocking(true)?;
    let app = make_router(app_id);
    axum::Server::from_tcp(listener)?
        .serve(app.into_make_service_with_connect_info::<SocketAddr>())
        .with_graceful_shutdown(shutdown)
        .await?;
    Ok(())
}
