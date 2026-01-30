use lithe_shim::{new_app_id, shutdown_lean, serve_with_shutdown};
use std::net::SocketAddr;
use tracing::{info, warn};

async fn shutdown_signal() {
    let ctrl_c = async {
        if let Err(err) = tokio::signal::ctrl_c().await {
            warn!(error = %err, "failed to install ctrl-c handler");
        }
    };

    #[cfg(unix)]
    let terminate = async {
        let mut sigterm = tokio::signal::unix::signal(tokio::signal::unix::SignalKind::terminate())
            .expect("failed to install SIGTERM handler");
        sigterm.recv().await;
    };

    #[cfg(not(unix))]
    let terminate = std::future::pending::<()>();

    tokio::select! {
        _ = ctrl_c => {},
        _ = terminate => {},
    }
}

#[tokio::main]
async fn main() {
    tracing_subscriber::fmt()
        .with_env_filter(tracing_subscriber::EnvFilter::from_default_env())
        .init();

    let addr: SocketAddr = std::env::var("LITHE_BIND")
        .unwrap_or_else(|_| "127.0.0.1:3000".to_string())
        .parse()
        .expect("invalid bind address");
    let app_name = std::env::var("LITHE_APP").unwrap_or_else(|_| "hello".to_string());

    let app_id = new_app_id(&app_name);

    info!(%addr, app = %app_name, "lithe-shim listening");

    serve_with_shutdown(addr, app_id, shutdown_signal())
        .await
        .expect("server failed");

    shutdown_lean(app_id);
}
