mod api;
mod config;
mod cover;
mod discovery;
mod hls;
mod monitor;
mod update;

use std::{process::ExitCode, sync::Arc};

use anyhow::{Context, Result};
use api::{AppState, build_router};
use config::AppConfig;
use cover::{CoverResolver, FfmpegCoverGenerator};
use discovery::{CatalogStore, MediaScanner};
use hls::HlsManager;
use tokio::sync::{Mutex, watch};
use tracing::{error, info, warn};
use tracing_subscriber::EnvFilter;

#[tokio::main]
async fn main() -> ExitCode {
    init_tracing();
    match run().await {
        Ok(()) => ExitCode::SUCCESS,
        Err(error) => {
            error!("服务运行失败：{error:#}");
            ExitCode::FAILURE
        }
    }
}

async fn run() -> Result<()> {
    let config = AppConfig::from_env()?;
    let cover_generator = Arc::new(FfmpegCoverGenerator::new(
        config.ffmpeg_bin.clone(),
        config.cover_capture_seconds,
    ));
    let cover_resolver = CoverResolver::new(
        config.cover_cache_dir.clone(),
        config.default_cover_path.clone(),
        cover_generator,
    );
    let scanner = MediaScanner::new(
        config.media_dir.clone(),
        config.hls_cache_dir.clone(),
        cover_resolver,
    );
    let initial_report = scanner.scan()?;
    for message in &initial_report.warnings {
        warn!("{message}");
    }
    for message in scanner.cleanup_unused_covers(&initial_report.active_generated_covers) {
        warn!("{message}");
    }
    info!(
        "初始媒体扫描完成：可用视频={}",
        initial_report.catalog.len()
    );

    let store = CatalogStore::new(initial_report.catalog);
    let scan_guard = Arc::new(Mutex::new(()));
    let (stop_tx, stop_rx) = watch::channel(false);
    let (hls_manager, hls_worker) = HlsManager::start(
        config.hls_cache_dir.clone(),
        config.ffmpeg_bin.clone(),
        config.hls_prewarm_limit,
        stop_rx.clone(),
    )?;
    let initial_hls_manager = hls_manager.clone();
    let initial_catalog = store.snapshot().await;
    hls_manager
        .restore_published_entries(initial_catalog.entries())
        .await;
    let initial_hls_enqueue = tokio::spawn(async move {
        initial_hls_manager
            .enqueue_entries(initial_catalog.entries())
            .await;
    });
    let mut monitor_handles = monitor::start_media_monitors(
        scanner,
        store.clone(),
        hls_manager.clone(),
        config.scan_debounce,
        config.scan_interval,
        scan_guard,
        stop_rx,
    );
    monitor_handles.push(initial_hls_enqueue);

    let app = build_router(AppState {
        catalog: store,
        hls: hls_manager,
        update_dir: config.update_dir.clone(),
    });
    let listener = tokio::net::TcpListener::bind(config.bind_addr)
        .await
        .with_context(|| format!("无法监听地址 {}", config.bind_addr))?;
    info!(
        "菠萝乐园服务已启动：http://{}，媒体目录={}，自动封面缓存={}，HLS 缓存={}，HLS 预热数量={}，升级包目录={}",
        config.bind_addr,
        config.media_dir.display(),
        config.cover_cache_dir.display(),
        config.hls_cache_dir.display(),
        config.hls_prewarm_limit,
        config.update_dir.display()
    );

    let shutdown_tx = stop_tx.clone();
    let server_result = axum::serve(listener, app)
        .with_graceful_shutdown(async move {
            shutdown_signal().await;
            info!("收到停止信号，正在安全关闭服务");
            let _ = shutdown_tx.send(true);
        })
        .await;

    let _ = stop_tx.send(true);
    for handle in monitor_handles {
        if let Err(error) = handle.await {
            warn!("后台任务退出异常：{error}");
        }
    }
    if let Err(error) = hls_worker.await {
        warn!("HLS 后台任务退出异常：{error}");
    }
    server_result.context("HTTP 服务异常退出")?;
    info!("菠萝乐园服务已停止");
    Ok(())
}

fn init_tracing() {
    let filter = EnvFilter::try_from_default_env()
        .unwrap_or_else(|_| EnvFilter::new("bobo_learning_service=info"));
    tracing_subscriber::fmt()
        .with_env_filter(filter)
        .with_target(false)
        .compact()
        .init();
}

async fn shutdown_signal() {
    let ctrl_c = async {
        if let Err(error) = tokio::signal::ctrl_c().await {
            error!("监听 Ctrl+C 失败：{error}");
        }
    };

    #[cfg(unix)]
    let terminate = async {
        use tokio::signal::unix::{SignalKind, signal};
        match signal(SignalKind::terminate()) {
            Ok(mut stream) => {
                stream.recv().await;
            }
            Err(error) => {
                error!("监听 SIGTERM 失败：{error}");
                std::future::pending::<()>().await;
            }
        }
    };

    #[cfg(not(unix))]
    let terminate = std::future::pending::<()>();

    tokio::select! {
        () = ctrl_c => {}
        () = terminate => {}
    }
}
