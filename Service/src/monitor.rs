use std::{sync::Arc, time::Duration};

use notify::{
    Config as NotifyConfig, Event, EventKind, RecommendedWatcher, RecursiveMode, Watcher,
};
use tokio::{
    sync::{Mutex, mpsc, watch},
    task::JoinHandle,
    time::{Instant, MissedTickBehavior, sleep_until},
};
use tracing::{error, info, warn};

use crate::discovery::{CatalogStore, MediaScanner, refresh_catalog};
use crate::hls::HlsManager;

enum WatchMessage {
    Event(Event),
    Error(notify::Error),
}

/// 启动文件事件监听和周期扫描兜底任务。
pub fn start_media_monitors(
    scanner: MediaScanner,
    store: CatalogStore,
    hls: HlsManager,
    debounce: Duration,
    interval: Option<Duration>,
    scan_guard: Arc<Mutex<()>>,
    stop_rx: watch::Receiver<bool>,
) -> Vec<JoinHandle<()>> {
    let mut handles = vec![spawn_event_monitor(
        scanner.clone(),
        store.clone(),
        hls.clone(),
        debounce,
        Arc::clone(&scan_guard),
        stop_rx.clone(),
    )];

    if let Some(period) = interval {
        handles.push(spawn_periodic_scan(
            scanner, store, hls, period, scan_guard, stop_rx,
        ));
    }
    handles
}

fn spawn_event_monitor(
    scanner: MediaScanner,
    store: CatalogStore,
    hls: HlsManager,
    debounce: Duration,
    scan_guard: Arc<Mutex<()>>,
    mut stop_rx: watch::Receiver<bool>,
) -> JoinHandle<()> {
    tokio::spawn(async move {
        let media_dir = scanner.media_dir().to_path_buf();
        let (event_tx, mut event_rx) = mpsc::unbounded_channel::<WatchMessage>();
        let callback_tx = event_tx.clone();
        let watcher_result = RecommendedWatcher::new(
            move |result| {
                let message = match result {
                    Ok(event) => WatchMessage::Event(event),
                    Err(error) => WatchMessage::Error(error),
                };
                let _ = callback_tx.send(message);
            },
            NotifyConfig::default(),
        );
        let mut watcher = match watcher_result {
            Ok(watcher) => watcher,
            Err(error) => {
                error!("创建媒体目录监听器失败，将依赖周期扫描：{error}");
                return;
            }
        };

        if let Err(error) = watcher.watch(&media_dir, RecursiveMode::Recursive) {
            error!(
                "监听媒体目录失败，将依赖周期扫描：{}（{error}）",
                media_dir.display()
            );
            return;
        }
        info!("已监听媒体目录变化：{}", media_dir.display());

        loop {
            let first_message = tokio::select! {
                changed = stop_rx.changed() => {
                    if changed.is_err() || *stop_rx.borrow() {
                        break;
                    }
                    continue;
                }
                message = event_rx.recv() => message,
            };

            let Some(message) = first_message else {
                break;
            };
            if !handle_message(message) {
                continue;
            }

            let mut deadline = Instant::now() + debounce;
            loop {
                let timer = sleep_until(deadline);
                tokio::pin!(timer);
                tokio::select! {
                    changed = stop_rx.changed() => {
                        if changed.is_err() || *stop_rx.borrow() {
                            info!("媒体目录监听任务已停止");
                            return;
                        }
                    }
                    message = event_rx.recv() => {
                        match message {
                            Some(message) => {
                                if handle_message(message) {
                                deadline = Instant::now() + debounce;
                                }
                            }
                            None => return,
                        }
                    }
                    () = &mut timer => break,
                }
            }

            refresh_catalog(
                scanner.clone(),
                store.clone(),
                Arc::clone(&scan_guard),
                "文件事件",
            )
            .await;
            hls.enqueue_entries(store.snapshot().await.entries()).await;
        }
        info!("媒体目录监听任务已停止");
    })
}

fn spawn_periodic_scan(
    scanner: MediaScanner,
    store: CatalogStore,
    hls: HlsManager,
    period: Duration,
    scan_guard: Arc<Mutex<()>>,
    mut stop_rx: watch::Receiver<bool>,
) -> JoinHandle<()> {
    tokio::spawn(async move {
        let mut interval = tokio::time::interval_at(Instant::now() + period, period);
        interval.set_missed_tick_behavior(MissedTickBehavior::Skip);
        loop {
            tokio::select! {
                changed = stop_rx.changed() => {
                    if changed.is_err() || *stop_rx.borrow() {
                        break;
                    }
                }
                _ = interval.tick() => {
                    refresh_catalog(
                        scanner.clone(),
                        store.clone(),
                        Arc::clone(&scan_guard),
                        "周期任务",
                    ).await;
                    hls.enqueue_entries(store.snapshot().await.entries()).await;
                }
            }
        }
        info!("媒体目录周期扫描任务已停止");
    })
}

fn handle_message(message: WatchMessage) -> bool {
    match message {
        WatchMessage::Event(event) => !matches!(event.kind, EventKind::Access(_)),
        WatchMessage::Error(error) => {
            warn!("媒体目录监听发生错误，将等待后续事件或周期扫描：{error}");
            false
        }
    }
}
