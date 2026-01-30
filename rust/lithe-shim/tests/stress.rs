use hyper::{body::to_bytes, Client, StatusCode};
use lithe_shim::{new_app_id, serve_with_listener, shutdown_lean};
use std::net::TcpListener;
use std::sync::Arc;
use tokio::sync::{oneshot, Semaphore};
use tokio::time::{sleep, timeout, Duration};

#[cfg(lithe_example = "streaming")]
use bytes::Bytes;
#[cfg(lithe_example = "streaming")]
use hyper::Body;

#[cfg(lithe_example = "websocket")]
use futures_util::{SinkExt, StreamExt};
#[cfg(lithe_example = "sse")]
use futures_util::StreamExt;
#[cfg(lithe_example = "websocket")]
use tokio_tungstenite::connect_async;
#[cfg(lithe_example = "websocket")]
use url::Url;

fn lcg(seed: &mut u32) -> u32 {
    *seed = seed.wrapping_mul(1664525).wrapping_add(1013904223);
    *seed
}

async fn start_server(
    app_name: &str,
) -> (
    std::net::SocketAddr,
    oneshot::Sender<()>,
    tokio::task::JoinHandle<()>,
    u64,
) {
    let listener = TcpListener::bind("127.0.0.1:0").expect("bind test listener");
    let addr = listener.local_addr().expect("listener addr");
    let app_id = new_app_id(app_name);
    let (shutdown_tx, shutdown_rx) = oneshot::channel::<()>();

    let handle = tokio::spawn(async move {
        let _ = serve_with_listener(listener, app_id, async {
            let _ = shutdown_rx.await;
        })
        .await;
    });

    (addr, shutdown_tx, handle, app_id)
}

#[cfg(lithe_example = "streaming")]
#[tokio::test(flavor = "multi_thread", worker_threads = 4)]
#[ignore]
async fn stress_streaming_chunked() {
    let iters: usize = std::env::var("LITHE_STRESS_ITERS")
        .ok()
        .and_then(|v| v.parse().ok())
        .unwrap_or(200);
    let concurrency: usize = std::env::var("LITHE_STRESS_CONCURRENCY")
        .ok()
        .and_then(|v| v.parse().ok())
        .unwrap_or(32);
    let max_chunks: usize = std::env::var("LITHE_STRESS_MAX_CHUNKS")
        .ok()
        .and_then(|v| v.parse().ok())
        .unwrap_or(6);
    let max_chunk_kb: usize = std::env::var("LITHE_STRESS_CHUNK_KB")
        .ok()
        .and_then(|v| v.parse().ok())
        .unwrap_or(64);

    let (addr, shutdown, handle, app_id) = start_server("streaming").await;
    sleep(Duration::from_millis(50)).await;

    let client = Client::new();
    let sem = Arc::new(Semaphore::new(concurrency));
    let mut tasks = tokio::task::JoinSet::new();

    for i in 0..iters {
        let client = client.clone();
        let uri = format!("http://{addr}/echo").parse().unwrap();
        let sem = sem.clone();
        tasks.spawn(async move {
            let _permit = sem.acquire().await.expect("permit");
            let (mut sender, body) = Body::channel();
            let req = hyper::Request::post(uri).body(body).unwrap();

            let mut seed = (i as u32).wrapping_mul(1664525).wrapping_add(1013904223);
            let abort_early = lcg(&mut seed) % 20 == 0;
            let chunks = (lcg(&mut seed) as usize % max_chunks) + 1;
            let mut total = 0usize;

            let send_task = tokio::spawn(async move {
                for idx in 0..chunks {
                    let len = ((lcg(&mut seed) as usize) % (max_chunk_kb * 1024)) + 1;
                    total += len;
                    if sender.send_data(Bytes::from(vec![b'x'; len])).await.is_err() {
                        return (total, true);
                    }
                    if abort_early && idx == 0 {
                        drop(sender);
                        return (total, true);
                    }
                }
                drop(sender);
                (total, false)
            });

            let req_fut = timeout(Duration::from_secs(20), client.request(req));
            let (res, send_res) = tokio::join!(req_fut, send_task);
            let (total, aborted) = send_res.expect("send task");
            if aborted {
                // Connection may be closed or may still succeed; both are acceptable.
                return;
            }
            let res = res.expect("request timeout").expect("request failed");
            assert_eq!(res.status(), StatusCode::OK);
            let body = to_bytes(res.into_body()).await.expect("read body");
            assert_eq!(body, format!("len={}", total).as_bytes());
        });
    }

    while let Some(res) = tasks.join_next().await {
        res.expect("task join");
    }

    let _ = shutdown.send(());
    let _ = handle.await;
    sleep(Duration::from_millis(200)).await;
    shutdown_lean(app_id);
}

#[cfg(lithe_example = "websocket")]
#[tokio::test(flavor = "multi_thread", worker_threads = 4)]
#[ignore]
async fn stress_websocket_burst() {
    let conns: usize = std::env::var("LITHE_STRESS_WS_CONNS")
        .ok()
        .and_then(|v| v.parse().ok())
        .unwrap_or(20);
    let messages: usize = std::env::var("LITHE_STRESS_WS_MSGS")
        .ok()
        .and_then(|v| v.parse().ok())
        .unwrap_or(50);

    let (addr, shutdown, handle, app_id) = start_server("websocket").await;
    sleep(Duration::from_millis(50)).await;

    let mut tasks = tokio::task::JoinSet::new();
    for i in 0..conns {
        let url = Url::parse(&format!("ws://{addr}/ws")).expect("ws url");
        tasks.spawn(async move {
            let (mut socket, _resp) = connect_async(url).await.expect("ws connect");
            for n in 0..messages {
                let payload = format!("msg-{i}-{n}");
                socket
                    .send(tokio_tungstenite::tungstenite::Message::Text(payload))
                    .await
                    .expect("ws send");
                let _ = socket.next().await;
            }
        });
    }
    while let Some(res) = tasks.join_next().await {
        let _ = res;
    }

    let _ = shutdown.send(());
    let _ = handle.await;
    sleep(Duration::from_millis(200)).await;
    shutdown_lean(app_id);
}

#[cfg(lithe_example = "sse")]
#[tokio::test(flavor = "multi_thread", worker_threads = 4)]
#[ignore]
async fn stress_sse_fanout() {
    let clients: usize = std::env::var("LITHE_STRESS_SSE_CONNS")
        .ok()
        .and_then(|v| v.parse().ok())
        .unwrap_or(20);

    let (addr, shutdown, handle, app_id) = start_server("sse").await;
    sleep(Duration::from_millis(50)).await;

    let client = Client::new();
    let mut tasks = tokio::task::JoinSet::new();
    for _ in 0..clients {
        let client = client.clone();
        let uri = format!("http://{addr}/sse").parse().unwrap();
        tasks.spawn(async move {
            let res = client.get(uri).await.expect("sse request");
            assert_eq!(res.status(), StatusCode::OK);
            let mut body = res.into_body();
            let _ = timeout(Duration::from_secs(5), body.next()).await;
        });
    }
    while let Some(res) = tasks.join_next().await {
        let _ = res;
    }

    let _ = shutdown.send(());
    let _ = handle.await;
    sleep(Duration::from_millis(200)).await;
    shutdown_lean(app_id);
}
