use std::{path::Path, sync::Arc, time::Duration};

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
        let hls_dir = scanner.hls_cache_dir().to_path_buf();
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

        for directory in [&media_dir, &hls_dir] {
            if let Err(error) = watcher.watch(directory, RecursiveMode::Recursive) {
                error!(
                    "监听资源目录失败，将依赖周期扫描：{}（{error}）",
                    directory.display()
                );
            } else {
                info!("已监听资源目录变化：{}", directory.display());
            }
        }

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
            if !handle_message(message, &media_dir, &hls_dir) {
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
                                if handle_message(message, &media_dir, &hls_dir) {
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

fn handle_message(message: WatchMessage, media_dir: &Path, hls_dir: &Path) -> bool {
    match message {
        WatchMessage::Event(event) => should_rescan(&event, media_dir, hls_dir),
        WatchMessage::Error(error) => {
            warn!("媒体目录监听发生错误，将等待后续事件或周期扫描：{error}");
            false
        }
    }
}

fn should_rescan(event: &Event, media_dir: &Path, hls_dir: &Path) -> bool {
    if matches!(event.kind, EventKind::Access(_)) {
        return false;
    }
    event.paths.iter().any(|path| {
        if path.starts_with(media_dir) {
            return true;
        }
        let Ok(relative) = path.strip_prefix(hls_dir) else {
            return false;
        };
        if relative
            .components()
            .any(|part| part.as_os_str().to_string_lossy().starts_with('.'))
        {
            return false;
        }
        // 临时目录及分片写入不刷新目录；正式发布重命名、分类增删和元数据更新才刷新。
        path.file_name()
            .is_some_and(|name| name == crate::discovery::PUBLISHED_ASSET_FILE)
            || matches!(
                event.kind,
                EventKind::Create(_)
                    | EventKind::Remove(_)
                    | EventKind::Modify(notify::event::ModifyKind::Name(_))
                    | EventKind::Any
                    | EventKind::Other
            )
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    use notify::event::{CreateKind, DataChange, ModifyKind, RemoveKind};
    use std::fs;

    #[test]
    fn 分类删除与正式发布触发刷新而临时分片不触发() {
        let media = Path::new("media");
        let hls = Path::new("hls");
        let check = |kind, path| should_rescan(&Event::new(kind).add_path(path), media, hls);
        assert!(check(
            EventKind::Remove(RemoveKind::Folder),
            hls.join("课程")
        ));
        assert!(check(
            EventKind::Create(CreateKind::Folder),
            hls.join("课程/id/version")
        ));
        assert!(!check(
            EventKind::Create(CreateKind::File),
            hls.join("课程/id/.version.tmp/seg_00000.m4s")
        ));
        assert!(!check(
            EventKind::Modify(ModifyKind::Data(DataChange::Any)),
            hls.join("课程/id/version/seg_00000.m4s")
        ));
        assert!(check(
            EventKind::Modify(ModifyKind::Data(DataChange::Any)),
            hls.join("课程/id/version/asset.json")
        ));
        assert!(check(
            EventKind::Create(CreateKind::File),
            media.join("课程/视频.mp4")
        ));
    }

    #[tokio::test]
    async fn 关闭周期扫描后移走分类仍通过文件事件更新目录() {
        let temporary = tempfile::tempdir().unwrap();
        let media = temporary.path().join("media");
        let hls_root = temporary.path().join("hls");
        let covers = temporary.path().join("covers");
        fs::create_dir_all(&media).unwrap();
        fs::create_dir_all(&covers).unwrap();
        let default_cover = temporary.path().join("default.png");
        fs::write(&default_cover, "测试封面").unwrap();
        let old = crate::hls_migration::tests::create_legacy(&hls_root, "课程/第一集.mp4");
        let target = crate::asset_layout::grouped_video_dir(
            &hls_root,
            "课程",
            &crate::discovery::stable_id("课程/第一集.mp4"),
        )
        .unwrap();
        fs::create_dir_all(target.parent().unwrap()).unwrap();
        fs::rename(old.parent().unwrap(), &target).unwrap();
        let scanner = MediaScanner::new(
            media,
            hls_root.clone(),
            crate::cover::CoverResolver::new(
                covers,
                default_cover,
                Arc::new(crate::cover::FfmpegCoverGenerator::new(
                    "不存在的转码器".into(),
                    0,
                )),
            ),
        );
        let store = CatalogStore::new(scanner.scan().unwrap().catalog);
        assert_eq!(store.snapshot().await.len(), 1);
        let (stop_tx, stop_rx) = watch::channel(false);
        let (manager, worker) = HlsManager::start(
            hls_root.clone(),
            "不存在的转码器".into(),
            0,
            stop_rx.clone(),
        )
        .unwrap();
        let handles = start_media_monitors(
            scanner,
            store.clone(),
            manager,
            Duration::from_millis(30),
            None,
            Arc::new(Mutex::new(())),
            stop_rx,
        );
        tokio::time::sleep(Duration::from_millis(200)).await;
        fs::rename(hls_root.join("课程"), temporary.path().join("下架备份")).unwrap();
        let outcome = tokio::time::timeout(Duration::from_secs(5), async {
            while store.snapshot().await.len() != 0 {
                tokio::time::sleep(Duration::from_millis(20)).await;
            }
        })
        .await;
        stop_tx.send(true).unwrap();
        for handle in handles {
            handle.await.unwrap();
        }
        worker.await.unwrap();
        assert!(outcome.is_ok(), "文件事件应在未启用周期扫描时更新目录");
        assert!(temporary.path().join("下架备份").exists());
    }
}
