#[cfg(any(lithe_example = "websocket", lithe_example = "sse", lithe_example = "kitchen_sink"))]
use futures_util::StreamExt;
#[cfg(any(lithe_example = "websocket", lithe_example = "kitchen_sink"))]
use futures_util::SinkExt;
use hyper::{body::to_bytes, Client, StatusCode};
use lithe_shim::{new_app_id, serve_with_listener, shutdown_lean};
use std::net::TcpListener;
use tokio::sync::oneshot;
use tokio::time::{sleep, timeout, Duration};
#[cfg(lithe_example = "hello")]
use hyper::{Body, Request};
#[cfg(lithe_example = "hello")]
use hyper::client::conn;
#[cfg(lithe_example = "hello")]
use tokio::net::TcpStream;
#[cfg(any(lithe_example = "streaming", lithe_example = "kitchen_sink"))]
use hyper::Body;
#[cfg(any(lithe_example = "streaming", lithe_example = "kitchen_sink"))]
use bytes::Bytes;
#[cfg(any(lithe_example = "websocket", lithe_example = "kitchen_sink"))]
use tokio_tungstenite::connect_async;
#[cfg(any(lithe_example = "websocket", lithe_example = "kitchen_sink"))]
use url::Url;

async fn start_server(app_name: &str) -> (std::net::SocketAddr, oneshot::Sender<()>, tokio::task::JoinHandle<()>, u64) {
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

#[cfg(lithe_example = "hello")]
#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn end_to_end() {
    let (addr, shutdown, handle, app_id) = start_server("hello-test").await;
    sleep(Duration::from_millis(50)).await;

    let client = Client::new();
    let uri = format!("http://{addr}/hello").parse().unwrap();
    let res = client.get(uri).await.expect("hello request");
    let status = res.status();
    let body = to_bytes(res.into_body()).await.expect("read body");
    assert_eq!(status, StatusCode::OK);
    assert_eq!(body.as_ref(), b"hello");

    let uri = format!("http://{addr}/sleep/300").parse().unwrap();
    let res = timeout(Duration::from_secs(20), client.get(uri))
        .await
        .expect("timeout wrapper")
        .expect("sleep request");
    assert_eq!(res.status(), StatusCode::GATEWAY_TIMEOUT);

    eprintln!("shutting down server");
    let _ = shutdown.send(());
    let _ = handle.await;
    sleep(Duration::from_millis(600)).await;
    eprintln!("finalizing lean");
    shutdown_lean(app_id);
    eprintln!("done");
}

#[cfg(lithe_example = "hello")]
#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn keep_alive_multiple_requests() {
    let (addr, shutdown, handle, app_id) = start_server("hello-test").await;
    sleep(Duration::from_millis(50)).await;

    let stream = TcpStream::connect(addr).await.expect("tcp connect");
    let (mut sender, conn) = conn::Builder::new()
        .handshake(stream)
        .await
        .expect("handshake");
    let conn_task = tokio::spawn(async move {
        let _ = conn.await;
    });

    let uri1 = format!("http://{addr}/hello");
    let req1 = Request::builder()
        .method("GET")
        .uri(uri1)
        .body(Body::empty())
        .unwrap();
    let res1 = sender.send_request(req1).await.expect("req1");
    assert_eq!(res1.status(), StatusCode::OK);
    let body1 = to_bytes(res1.into_body()).await.expect("body1");
    assert_eq!(body1.as_ref(), b"hello");

    let uri2 = format!("http://{addr}/sleep/10");
    let req2 = Request::builder()
        .method("GET")
        .uri(uri2)
        .body(Body::empty())
        .unwrap();
    let res2 = sender.send_request(req2).await.expect("req2");
    assert_eq!(res2.status(), StatusCode::OK);

    let uri3 = format!("http://{addr}/hello");
    let req3 = Request::builder()
        .method("GET")
        .uri(uri3)
        .body(Body::empty())
        .unwrap();
    let res3 = sender.send_request(req3).await.expect("req3");
    assert_eq!(res3.status(), StatusCode::OK);
    let body3 = to_bytes(res3.into_body()).await.expect("body3");
    assert_eq!(body3.as_ref(), b"hello");

    let _ = shutdown.send(());
    let _ = handle.await;
    let _ = conn_task.await;
    sleep(Duration::from_millis(200)).await;
    shutdown_lean(app_id);
}

#[cfg(lithe_example = "websocket")]
#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn websocket_echo() {
    let (addr, shutdown, handle, app_id) = start_server("websocket").await;
    sleep(Duration::from_millis(50)).await;

    let url = Url::parse(&format!("ws://{addr}/ws")).expect("ws url");
    let (mut socket, resp) = connect_async(url).await.expect("ws connect");
    assert_eq!(resp.status(), StatusCode::SWITCHING_PROTOCOLS);

    use tokio_tungstenite::tungstenite::Message;
    socket.send(Message::Text("hello".into())).await.expect("ws send text");
    socket
        .send(Message::Binary(vec![1, 2, 3]))
        .await
        .expect("ws send binary");
    socket.send(Message::Ping(vec![9])).await.expect("ws send ping");

    let mut got_text = false;
    let mut got_bin = false;
    let mut got_pong = false;
    for _ in 0..10 {
        let msg = timeout(Duration::from_secs(5), socket.next())
            .await
            .expect("ws recv timeout")
            .expect("ws recv")
            .expect("ws recv msg");
        match msg {
            Message::Text(text) => {
                if text == "hello" {
                    got_text = true;
                }
            }
            Message::Binary(bin) => {
                if bin == vec![1, 2, 3] {
                    got_bin = true;
                }
            }
            Message::Pong(payload) => {
                if payload == vec![9] {
                    got_pong = true;
                }
            }
            Message::Close(_) => break,
            _ => {}
        }
        if got_text && got_bin && got_pong {
            break;
        }
    }
    assert!(got_text, "missing text echo");
    assert!(got_bin, "missing binary echo");
    assert!(got_pong, "missing pong reply");

    let _ = shutdown.send(());
    let _ = handle.await;
    sleep(Duration::from_millis(200)).await;
    shutdown_lean(app_id);
}

#[cfg(lithe_example = "sse")]
#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn sse_stream_smoke() {
    let (addr, shutdown, handle, app_id) = start_server("sse").await;
    sleep(Duration::from_millis(50)).await;

    let client = Client::new();
    let uri = format!("http://{addr}/sse").parse().unwrap();
    let res = client.get(uri).await.expect("sse request");
    assert_eq!(res.status(), StatusCode::OK);
    let content_type = res
        .headers()
        .get("content-type")
        .and_then(|v| v.to_str().ok())
        .unwrap_or("");
    assert!(content_type.starts_with("text/event-stream"));

    let mut body = res.into_body();
    let mut collected = String::new();
    for _ in 0..4 {
        let next = timeout(Duration::from_secs(5), body.next())
            .await
            .expect("sse recv timeout")
            .expect("sse recv");
        match next {
            Some(bytes) => {
                if let Ok(chunk) = bytes {
                    collected.push_str(&String::from_utf8_lossy(&chunk));
                    if collected.contains("data: message 0") {
                        break;
                    }
                }
            }
            None => break,
        }
    }
    assert!(collected.contains(": connected"), "missing keepalive");
    assert!(collected.contains("data: message 0"), "missing first message");

    let _ = shutdown.send(());
    let _ = handle.await;
    sleep(Duration::from_millis(200)).await;
    shutdown_lean(app_id);
}

#[cfg(lithe_example = "streaming")]
#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn request_body_streaming() {
    let (addr, shutdown, handle, app_id) = start_server("streaming").await;
    sleep(Duration::from_millis(50)).await;

    let client = Client::new();
    let (mut sender, body) = Body::channel();
    let uri = format!("http://{addr}/echo").parse().unwrap();
    let req = hyper::Request::post(uri).body(body).unwrap();

    let send_task = tokio::spawn(async move {
        sender
            .send_data(Bytes::from_static(b"abc"))
            .await
            .expect("send chunk 1");
        sender
            .send_data(Bytes::from_static(b"defg"))
            .await
            .expect("send chunk 2");
    });

    let res = client.request(req).await.expect("streaming request");
    assert_eq!(res.status(), StatusCode::OK);
    let body = to_bytes(res.into_body()).await.expect("read body");
    assert_eq!(body.as_ref(), b"len=7");

    let _ = send_task.await;
    let _ = shutdown.send(());
    let _ = handle.await;
    sleep(Duration::from_millis(200)).await;
    shutdown_lean(app_id);
}

#[cfg(lithe_example = "streaming")]
#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn request_body_concurrent() {
    let (addr, shutdown, handle, app_id) = start_server("streaming").await;
    sleep(Duration::from_millis(50)).await;

    let client = Client::new();
    let mut tasks = Vec::new();
    for i in 0..10u8 {
        let client = client.clone();
        let uri = format!("http://{addr}/echo").parse().unwrap();
        let payload = vec![b'a'; (i as usize) + 1];
        tasks.push(tokio::spawn(async move {
            let res = client
                .request(hyper::Request::post(uri).body(Body::from(payload.clone())).unwrap())
                .await
                .expect("request");
            let body = to_bytes(res.into_body()).await.expect("read body");
            assert_eq!(body, format!("len={}", payload.len()).as_bytes());
        }));
    }
    for task in tasks {
        let _ = task.await;
    }

    let _ = shutdown.send(());
    let _ = handle.await;
    sleep(Duration::from_millis(200)).await;
    shutdown_lean(app_id);
}

#[cfg(lithe_example = "streaming")]
#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn request_body_abort_then_recover() {
    let (addr, shutdown, handle, app_id) = start_server("streaming").await;
    sleep(Duration::from_millis(50)).await;

    let client = Client::new();
    let uri = format!("http://{addr}/echo").parse().unwrap();
    let (mut sender, body) = Body::channel();
    let req = hyper::Request::post(uri).body(body).unwrap();

    let send_task = tokio::spawn(async move {
        let _ = sender.send_data(Bytes::from_static(b"abc")).await;
        drop(sender);
    });

    let _ = client.request(req).await;
    let _ = send_task.await;

    let uri = format!("http://{addr}/echo").parse().unwrap();
    let res = client
        .request(hyper::Request::post(uri).body(Body::from("abcd")).unwrap())
        .await
        .expect("recover request");
    let body = to_bytes(res.into_body()).await.expect("read body");
    assert_eq!(body.as_ref(), b"len=4");

    let _ = shutdown.send(());
    let _ = handle.await;
    sleep(Duration::from_millis(200)).await;
    shutdown_lean(app_id);
}

#[cfg(lithe_example = "streaming")]
#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn request_body_large() {
    let (addr, shutdown, handle, app_id) = start_server("streaming").await;
    sleep(Duration::from_millis(50)).await;

    let client = Client::new();
    let uri = format!("http://{addr}/echo").parse().unwrap();
    let payload = vec![b'x'; 512 * 1024];
    let res = client
        .request(hyper::Request::post(uri).body(Body::from(payload)).unwrap())
        .await
        .expect("large request");
    assert_eq!(res.status(), StatusCode::OK);
    let body = to_bytes(res.into_body()).await.expect("read body");
    assert_eq!(body.as_ref(), b"len=524288");

    let _ = shutdown.send(());
    let _ = handle.await;
    sleep(Duration::from_millis(200)).await;
    shutdown_lean(app_id);
}

#[cfg(lithe_example = "kitchen_sink")]
#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn kitchen_sink_end_to_end() {
    let (addr, shutdown, handle, app_id) = start_server("kitchen_sink").await;
    sleep(Duration::from_millis(50)).await;

    let client = Client::new();
    let uri = format!("http://{addr}/hello").parse().unwrap();
    let res = client.get(uri).await.expect("hello request");
    let body = to_bytes(res.into_body()).await.expect("read body");
    assert_eq!(body.as_ref(), b"hello");

    let uri = format!("http://{addr}/echo").parse().unwrap();
    let (mut sender, body) = Body::channel();
    let req = hyper::Request::post(uri).body(body).unwrap();
    let send_task = tokio::spawn(async move {
        sender
            .send_data(Bytes::from_static(b"abc"))
            .await
            .expect("send chunk 1");
        sender
            .send_data(Bytes::from_static(b"defg"))
            .await
            .expect("send chunk 2");
    });
    let res = client.request(req).await.expect("echo request");
    let body = to_bytes(res.into_body()).await.expect("read echo body");
    assert_eq!(body.as_ref(), b"len=7");
    let _ = send_task.await;

    let url = Url::parse(&format!("ws://{addr}/ws")).expect("ws url");
    let (mut socket, resp) = connect_async(url).await.expect("ws connect");
    assert_eq!(resp.status(), StatusCode::SWITCHING_PROTOCOLS);
    socket
        .send(tokio_tungstenite::tungstenite::Message::Text("hi".into()))
        .await
        .expect("ws send");
    let msg = timeout(Duration::from_secs(5), socket.next())
        .await
        .expect("ws recv timeout")
        .expect("ws recv")
        .expect("ws recv msg");
    match msg {
        tokio_tungstenite::tungstenite::Message::Text(text) => {
            assert_eq!(text, "hi");
        }
        other => panic!("unexpected ws message: {other:?}"),
    }

    let uri = format!("http://{addr}/sse").parse().unwrap();
    let res = client.get(uri).await.expect("sse request");
    assert_eq!(res.status(), StatusCode::OK);
    let mut body = res.into_body();
    let mut collected = String::new();
    for _ in 0..4 {
        let next = timeout(Duration::from_secs(5), body.next())
            .await
            .expect("sse recv timeout")
            .expect("sse recv");
        match next {
            Some(bytes) => {
                if let Ok(chunk) = bytes {
                    collected.push_str(&String::from_utf8_lossy(&chunk));
                    if collected.contains("data: message 0") {
                        break;
                    }
                }
            }
            None => break,
        }
    }
    assert!(collected.contains(": connected"), "missing keepalive");
    assert!(collected.contains("data: message 0"), "missing first message");

    let _ = shutdown.send(());
    let _ = handle.await;
    sleep(Duration::from_millis(200)).await;
    shutdown_lean(app_id);
}

#[cfg(lithe_example = "streaming")]
#[tokio::test(flavor = "multi_thread", worker_threads = 2)]
async fn request_body_chunked_concurrent() {
    let (addr, shutdown, handle, app_id) = start_server("streaming").await;
    sleep(Duration::from_millis(50)).await;

    let client = Client::new();
    let mut tasks = Vec::new();
    for i in 0..8u8 {
        let client = client.clone();
        let uri = format!("http://{addr}/echo").parse().unwrap();
        tasks.push(tokio::spawn(async move {
            let (mut sender, body) = Body::channel();
            let req = hyper::Request::post(uri).body(body).unwrap();
            let send_task = tokio::spawn(async move {
                sender
                    .send_data(Bytes::from(vec![b'a'; (i as usize) + 1]))
                    .await
                    .expect("send chunk 1");
                sender
                    .send_data(Bytes::from(vec![b'b'; (i as usize) + 2]))
                    .await
                    .expect("send chunk 2");
            });

            let res = client.request(req).await.expect("streaming request");
            let body = to_bytes(res.into_body()).await.expect("read body");
            assert_eq!(body, format!("len={}", (i as usize) + 3).as_bytes());
            let _ = send_task.await;
        }));
    }
    for task in tasks {
        let _ = task.await;
    }

    let _ = shutdown.send(());
    let _ = handle.await;
    sleep(Duration::from_millis(200)).await;
    shutdown_lean(app_id);
}
