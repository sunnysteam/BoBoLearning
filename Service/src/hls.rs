use std::{
    collections::HashMap,
    ffi::OsString,
    fmt::Write as _,
    fs::{self, File},
    path::{Path, PathBuf},
    process::Command,
    sync::Arc,
    time::UNIX_EPOCH,
};

use anyhow::{Context, Result, bail};
use sha2::{Digest, Sha256};
use tokio::{
    sync::{RwLock, mpsc, watch},
    task::JoinHandle,
};
use tracing::{error, info, warn};

use crate::discovery::{
    PUBLISHED_ASSET_FILE, PUBLISHED_ASSET_SCHEMA_VERSION, PublishedAssetManifest, VideoEntry,
};

const PROFILE_VERSION: &str = "hls-cmaf-720p-v1";
const PLAYLIST_FILE: &str = "index.m3u8";
const INIT_FILE: &str = "init.mp4";

/// 单个视频的 HLS 生成状态。
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum HlsStatus {
    Pending,
    Processing,
    Ready,
    Failed,
}

impl HlsStatus {
    pub const fn as_str(self) -> &'static str {
        match self {
            Self::Pending => "pending",
            Self::Processing => "processing",
            Self::Ready => "ready",
            Self::Failed => "failed",
        }
    }
}

/// API 查询所需的只读 HLS 状态快照。
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct HlsSnapshot {
    pub status: HlsStatus,
    pub version: Option<String>,
}

#[derive(Clone, Debug)]
struct HlsState {
    version: String,
    status: HlsStatus,
}

#[derive(Clone, Debug)]
struct HlsJob {
    entry: Arc<VideoEntry>,
    version: String,
}

/// HLS/CMAF 转码器，测试中可替换为轻量实现。
pub trait HlsGenerator: Send + Sync {
    fn generate(&self, video_path: &Path, output_dir: &Path) -> Result<()>;
}

/// 使用 FFmpeg 生成单路 720p HLS VOD 与 CMAF/fMP4 分片。
#[derive(Clone, Debug)]
pub struct FfmpegHlsGenerator {
    executable: OsString,
}

impl FfmpegHlsGenerator {
    pub fn new(executable: OsString) -> Self {
        Self { executable }
    }
}

impl HlsGenerator for FfmpegHlsGenerator {
    fn generate(&self, video_path: &Path, output_dir: &Path) -> Result<()> {
        fs::create_dir_all(output_dir)
            .with_context(|| format!("无法创建 HLS 临时目录：{}", output_dir.display()))?;

        let output = Command::new(&self.executable)
            .current_dir(output_dir)
            .args([
                "-hide_banner",
                "-loglevel",
                "error",
                "-nostdin",
                "-y",
                "-i",
            ])
            .arg(video_path)
            .args([
                "-map",
                "0:v:0",
                "-map",
                "0:a:0?",
                "-sn",
                "-dn",
                "-vf",
                "scale='min(1280,iw)':'min(720,ih)':force_original_aspect_ratio=decrease:force_divisible_by=2",
                "-c:v",
                "libx264",
                "-preset",
                "veryfast",
                "-pix_fmt",
                "yuv420p",
                "-b:v",
                "1200k",
                "-maxrate",
                "1400k",
                "-bufsize",
                "2800k",
                "-force_key_frames",
                "expr:gte(t,n_forced*6)",
                "-threads",
                "2",
                "-c:a",
                "aac",
                "-b:a",
                "96k",
                "-f",
                "hls",
                "-hls_time",
                "6",
                "-hls_list_size",
                "0",
                "-hls_playlist_type",
                "vod",
                "-hls_segment_type",
                "fmp4",
                "-hls_fmp4_init_filename",
                INIT_FILE,
                "-hls_flags",
                "independent_segments+temp_file",
                "-hls_segment_filename",
                "seg_%05d.m4s",
                PLAYLIST_FILE,
            ])
            .output()
            .with_context(|| format!("无法启动 FFmpeg：{}", self.executable.to_string_lossy()))?;

        if !output.status.success() {
            bail!(
                "FFmpeg 生成 HLS 失败（{}）：{}",
                output.status,
                concise_stderr(&output.stderr)
            );
        }
        validate_output(output_dir)
    }
}

/// 管理 HLS 预热队列、版本化缓存和对外可见状态。
#[derive(Clone)]
pub struct HlsManager {
    cache_dir: PathBuf,
    prewarm_limit: usize,
    states: Arc<RwLock<HashMap<String, HlsState>>>,
    sender: mpsc::Sender<HlsJob>,
}

impl HlsManager {
    pub fn start(
        cache_dir: PathBuf,
        ffmpeg_bin: OsString,
        prewarm_limit: usize,
        stop_rx: watch::Receiver<bool>,
    ) -> Result<(Self, JoinHandle<()>)> {
        Self::start_with_generator(
            cache_dir,
            prewarm_limit,
            Arc::new(FfmpegHlsGenerator::new(ffmpeg_bin)),
            stop_rx,
        )
    }

    fn start_with_generator(
        cache_dir: PathBuf,
        prewarm_limit: usize,
        generator: Arc<dyn HlsGenerator>,
        stop_rx: watch::Receiver<bool>,
    ) -> Result<(Self, JoinHandle<()>)> {
        fs::create_dir_all(&cache_dir)
            .with_context(|| format!("无法创建 HLS 缓存目录：{}", cache_dir.display()))?;
        let (sender, receiver) = mpsc::channel(64);
        let states = Arc::new(RwLock::new(HashMap::new()));
        let manager = Self {
            cache_dir: cache_dir.clone(),
            prewarm_limit,
            states: Arc::clone(&states),
            sender,
        };
        let handle = tokio::spawn(run_worker(cache_dir, states, generator, receiver, stop_rx));
        Ok((manager, handle))
    }

    /// 启动服务时先恢复已发布资产，避免正式资产短暂回退到待处理状态。
    pub async fn restore_published_entries(&self, entries: &[Arc<VideoEntry>]) {
        let mut states = self.states.write().await;
        for entry in entries {
            let Some(version) = entry.published_hls_version.as_ref() else {
                continue;
            };
            let asset_dir = self.asset_dir(&entry.id, version);
            if validate_published_asset(&asset_dir).is_ok() {
                states.insert(
                    entry.id.clone(),
                    HlsState {
                        version: version.clone(),
                        status: HlsStatus::Ready,
                    },
                );
            }
        }
    }

    /// 只为收件箱中的源视频排队；已发布资产仅恢复状态，不会重复转码。
    pub async fn enqueue_entries(&self, entries: &[Arc<VideoEntry>]) {
        let mut incoming_count = 0usize;
        for entry in entries {
            if let Some(version) = entry.published_hls_version.as_ref() {
                let asset_dir = self.asset_dir(&entry.id, version);
                let status = if validate_published_asset(&asset_dir).is_ok() {
                    HlsStatus::Ready
                } else {
                    HlsStatus::Failed
                };
                self.states.write().await.insert(
                    entry.id.clone(),
                    HlsState {
                        version: version.clone(),
                        status,
                    },
                );
                continue;
            }

            if self.prewarm_limit > 0 && incoming_count >= self.prewarm_limit {
                continue;
            }
            incoming_count += 1;
            let Some(video_path) = entry.video_path.as_ref() else {
                continue;
            };
            let version = match media_version(video_path) {
                Ok(version) => version,
                Err(error) => {
                    warn!(
                        "无法计算 HLS 缓存版本，已跳过 {}：{error:#}",
                        entry.relative_video_path
                    );
                    continue;
                }
            };
            let final_dir = self.asset_dir(&entry.id, &version);
            if validate_output(&final_dir).is_ok() {
                match finalize_existing_asset(&final_dir, entry, &version) {
                    Ok(()) => {
                        self.states.write().await.insert(
                            entry.id.clone(),
                            HlsState {
                                version: version.clone(),
                                status: HlsStatus::Ready,
                            },
                        );
                        cleanup_incoming_source(entry);
                    }
                    Err(error) => {
                        error!(
                            "无法接管已有 HLS 资产 {}：{error:#}",
                            entry.relative_video_path
                        );
                        self.states.write().await.insert(
                            entry.id.clone(),
                            HlsState {
                                version,
                                status: HlsStatus::Failed,
                            },
                        );
                    }
                }
                continue;
            }

            let should_queue = {
                let mut states = self.states.write().await;
                match states.get(&entry.id) {
                    Some(state) if state.version == version => false,
                    _ => {
                        states.insert(
                            entry.id.clone(),
                            HlsState {
                                version: version.clone(),
                                status: HlsStatus::Processing,
                            },
                        );
                        true
                    }
                }
            };
            if !should_queue {
                continue;
            }

            let job = HlsJob {
                entry: Arc::clone(entry),
                version,
            };
            if let Err(send_error) = self.sender.send(job).await {
                error!(
                    "HLS 转码队列已停止，无法继续预热：{}",
                    entry.relative_video_path
                );
                let failed_job = send_error.0;
                if let Some(state) = self.states.write().await.get_mut(&failed_job.entry.id)
                    && state.version == failed_job.version
                {
                    state.status = HlsStatus::Failed;
                }
                break;
            }
        }
    }

    pub async fn snapshot(&self, id: &str) -> HlsSnapshot {
        match self.states.read().await.get(id) {
            Some(state) => HlsSnapshot {
                status: state.status,
                version: (state.status == HlsStatus::Ready).then(|| state.version.clone()),
            },
            None => HlsSnapshot {
                status: HlsStatus::Pending,
                version: None,
            },
        }
    }

    /// 仅允许读取当前已发布版本中的固定 HLS 文件名。
    pub async fn resolve_asset_path(&self, id: &str, version: &str, file: &str) -> Option<PathBuf> {
        if !is_allowed_asset_name(file) {
            return None;
        }
        let states = self.states.read().await;
        let state = states.get(id)?;
        if state.status != HlsStatus::Ready || state.version != version {
            return None;
        }
        let path = self.asset_dir(id, version).join(file);
        is_readable_nonempty_file(&path).then_some(path)
    }

    /// 源文件清理和目录快照切换期间，封面始终从正式资产兜底读取。
    pub async fn resolve_cover_path(&self, id: &str) -> Option<PathBuf> {
        let states = self.states.read().await;
        let state = states.get(id)?;
        if state.status != HlsStatus::Ready {
            return None;
        }
        published_cover_path(&self.asset_dir(id, &state.version)).ok()
    }

    fn asset_dir(&self, id: &str, version: &str) -> PathBuf {
        self.cache_dir.join(id).join(version)
    }

    #[cfg(test)]
    pub async fn publish_test_asset(&self, id: &str, version: &str) -> Result<()> {
        let output_dir = self.asset_dir(id, version);
        fs::create_dir_all(&output_dir)?;
        fs::write(output_dir.join(PLAYLIST_FILE), "#EXTM3U\n#EXT-X-ENDLIST\n")?;
        fs::write(output_dir.join(INIT_FILE), b"init")?;
        fs::write(output_dir.join("seg_00000.m4s"), b"segment")?;
        self.states.write().await.insert(
            id.to_owned(),
            HlsState {
                version: version.to_owned(),
                status: HlsStatus::Ready,
            },
        );
        Ok(())
    }
}

async fn run_worker(
    cache_dir: PathBuf,
    states: Arc<RwLock<HashMap<String, HlsState>>>,
    generator: Arc<dyn HlsGenerator>,
    mut receiver: mpsc::Receiver<HlsJob>,
    mut stop_rx: watch::Receiver<bool>,
) {
    loop {
        let job = tokio::select! {
            changed = stop_rx.changed() => {
                if changed.is_err() || *stop_rx.borrow() {
                    break;
                }
                continue;
            }
            job = receiver.recv() => job,
        };
        let Some(job) = job else {
            break;
        };

        info!("开始生成 HLS/CMAF：{}", job.entry.title);
        let job_for_worker = job.clone();
        let cache_for_worker = cache_dir.clone();
        let generator_for_worker = Arc::clone(&generator);
        let result = tokio::task::spawn_blocking(move || {
            generate_atomically(
                &cache_for_worker,
                &job_for_worker,
                generator_for_worker.as_ref(),
            )
        })
        .await;

        let succeeded = matches!(result, Ok(Ok(())));
        match result {
            Ok(Ok(())) => info!("HLS/CMAF 生成完成：{}", job.entry.title),
            Ok(Err(error)) => error!("HLS/CMAF 生成失败 {}：{error:#}", job.entry.title),
            Err(error) => error!("HLS/CMAF 转码任务异常结束 {}：{error}", job.entry.title),
        }

        let mut states = states.write().await;
        if let Some(state) = states.get_mut(&job.entry.id)
            && state.version == job.version
        {
            state.status = if succeeded {
                HlsStatus::Ready
            } else {
                HlsStatus::Failed
            };
        }
    }
    info!("HLS/CMAF 后台生成任务已停止");
}

fn generate_atomically(cache_dir: &Path, job: &HlsJob, generator: &dyn HlsGenerator) -> Result<()> {
    let parent_dir = cache_dir.join(&job.entry.id);
    fs::create_dir_all(&parent_dir)
        .with_context(|| format!("无法创建视频 HLS 缓存目录：{}", parent_dir.display()))?;
    let final_dir = parent_dir.join(&job.version);
    if validate_output(&final_dir).is_ok() {
        finalize_existing_asset(&final_dir, &job.entry, &job.version)?;
        cleanup_incoming_source(&job.entry);
        return Ok(());
    }

    let temporary_dir = parent_dir.join(format!(".{}.tmp", job.version));
    remove_dir_if_exists(&temporary_dir)?;
    fs::create_dir_all(&temporary_dir)
        .with_context(|| format!("无法创建 HLS 临时目录：{}", temporary_dir.display()))?;

    let video_path = job
        .entry
        .video_path
        .as_deref()
        .context("HLS 转码任务缺少源视频")?;
    if let Err(error) = generator.generate(video_path, &temporary_dir) {
        let _ = fs::remove_dir_all(&temporary_dir);
        return Err(error);
    }
    write_published_asset(&temporary_dir, &job.entry, &job.version)?;
    validate_output(&temporary_dir)?;
    validate_published_asset(&temporary_dir)?;
    remove_dir_if_exists(&final_dir)?;
    fs::rename(&temporary_dir, &final_dir).with_context(|| {
        format!(
            "无法原子发布 HLS 缓存：{} -> {}",
            temporary_dir.display(),
            final_dir.display()
        )
    })?;
    remove_stale_versions(&parent_dir, &job.version);
    cleanup_incoming_source(&job.entry);
    Ok(())
}

fn finalize_existing_asset(output_dir: &Path, entry: &VideoEntry, version: &str) -> Result<()> {
    if validate_published_asset(output_dir).is_ok() {
        return Ok(());
    }
    write_published_asset(output_dir, entry, version)?;
    validate_published_asset(output_dir)
}

fn write_published_asset(output_dir: &Path, entry: &VideoEntry, version: &str) -> Result<()> {
    let cover_extension = entry
        .cover_path
        .extension()
        .map(|value| value.to_string_lossy().to_ascii_lowercase())
        .filter(|value| matches!(value.as_str(), "webp" | "png" | "jpg" | "jpeg"))
        .unwrap_or_else(|| "png".to_owned());
    let cover_file = format!("cover.{cover_extension}");
    let cover_path = output_dir.join(&cover_file);
    let temporary_cover = output_dir.join(format!(".{cover_file}.tmp"));
    fs::copy(&entry.cover_path, &temporary_cover).with_context(|| {
        format!(
            "无法复制正式资产封面：{} -> {}",
            entry.cover_path.display(),
            temporary_cover.display()
        )
    })?;
    if cover_path.exists() {
        fs::remove_file(&cover_path)
            .with_context(|| format!("无法替换正式资产封面：{}", cover_path.display()))?;
    }
    fs::rename(&temporary_cover, &cover_path).with_context(|| {
        format!(
            "无法发布正式资产封面：{} -> {}",
            temporary_cover.display(),
            cover_path.display()
        )
    })?;

    let manifest = PublishedAssetManifest {
        schema_version: PUBLISHED_ASSET_SCHEMA_VERSION,
        id: entry.id.clone(),
        version: version.to_owned(),
        title: entry.title.clone(),
        folder_path: entry.folder_path.clone(),
        relative_video_path: entry.relative_video_path.clone(),
        cover_file,
    };
    let bytes = serde_json::to_vec_pretty(&manifest).context("无法序列化正式资产元数据")?;
    let manifest_path = output_dir.join(PUBLISHED_ASSET_FILE);
    let temporary_manifest = output_dir.join(format!(".{PUBLISHED_ASSET_FILE}.tmp"));
    fs::write(&temporary_manifest, bytes).with_context(|| {
        format!(
            "无法写入正式资产临时元数据：{}",
            temporary_manifest.display()
        )
    })?;
    if manifest_path.exists() {
        fs::remove_file(&manifest_path)
            .with_context(|| format!("无法替换正式资产元数据：{}", manifest_path.display()))?;
    }
    fs::rename(&temporary_manifest, &manifest_path).with_context(|| {
        format!(
            "无法发布正式资产元数据：{} -> {}",
            temporary_manifest.display(),
            manifest_path.display()
        )
    })?;
    Ok(())
}

fn validate_published_asset(output_dir: &Path) -> Result<()> {
    validate_output(output_dir)?;
    published_cover_path(output_dir)?;
    Ok(())
}

fn published_cover_path(output_dir: &Path) -> Result<PathBuf> {
    let manifest_path = output_dir.join(PUBLISHED_ASSET_FILE);
    let bytes = fs::read(&manifest_path)
        .with_context(|| format!("无法读取正式资产元数据：{}", manifest_path.display()))?;
    let manifest: PublishedAssetManifest = serde_json::from_slice(&bytes)
        .with_context(|| format!("正式资产元数据格式无效：{}", manifest_path.display()))?;
    if manifest.schema_version != PUBLISHED_ASSET_SCHEMA_VERSION {
        bail!("不支持的正式资产元数据版本：{}", manifest.schema_version);
    }
    let cover_name = Path::new(&manifest.cover_file);
    let cover_path = output_dir.join(cover_name);
    if cover_name.components().count() != 1
        || cover_name.file_name().and_then(|value| value.to_str())
            != Some(manifest.cover_file.as_str())
        || !is_readable_nonempty_file(&cover_path)
    {
        bail!("正式资产封面不存在或文件名无效");
    }
    Ok(cover_path)
}

fn cleanup_incoming_source(entry: &VideoEntry) {
    let Some(video_path) = entry.video_path.as_ref() else {
        return;
    };
    let mut paths = Vec::from([video_path.clone()]);
    if let (Some(parent), Some(stem)) = (video_path.parent(), video_path.file_stem())
        && let Ok(children) = fs::read_dir(parent)
    {
        for child in children.filter_map(Result::ok) {
            let path = child.path();
            if path == *video_path
                || child
                    .file_type()
                    .map(|kind| !kind.is_file())
                    .unwrap_or(true)
                || path.file_stem() != Some(stem)
            {
                continue;
            }
            let extension = path
                .extension()
                .map(|value| value.to_string_lossy().to_ascii_lowercase());
            if matches!(extension.as_deref(), Some("webp" | "png" | "jpg" | "jpeg")) {
                paths.push(path);
            }
        }
    }

    for path in paths {
        match fs::remove_file(&path) {
            Ok(()) => info!("正式资产已发布，已清理源文件：{}", path.display()),
            Err(error) if error.kind() == std::io::ErrorKind::NotFound => {}
            Err(error) => warn!(
                "正式资产已发布，但源文件清理失败 {}：{error}",
                path.display()
            ),
        }
    }
}

fn remove_stale_versions(parent_dir: &Path, active_version: &str) {
    let Ok(entries) = fs::read_dir(parent_dir) else {
        return;
    };
    for entry in entries.filter_map(Result::ok) {
        if entry.file_name() == active_version || !entry.path().is_dir() {
            continue;
        }
        if let Err(error) = fs::remove_dir_all(entry.path()) {
            warn!("清理旧版 HLS 资产失败 {}：{error}", entry.path().display());
        }
    }
}

fn validate_output(output_dir: &Path) -> Result<()> {
    if !is_readable_nonempty_file(&output_dir.join(PLAYLIST_FILE)) {
        bail!("HLS 清单不存在或为空");
    }
    if !is_readable_nonempty_file(&output_dir.join(INIT_FILE)) {
        bail!("HLS 初始化分片不存在或为空");
    }
    let has_segment = fs::read_dir(output_dir)
        .with_context(|| format!("无法读取 HLS 输出目录：{}", output_dir.display()))?
        .filter_map(Result::ok)
        .any(|entry| {
            let name = entry.file_name();
            let name = name.to_string_lossy();
            is_media_segment_name(&name) && is_readable_nonempty_file(&entry.path())
        });
    if !has_segment {
        bail!("HLS 媒体分片不存在或为空");
    }
    Ok(())
}

fn media_version(video_path: &Path) -> Result<String> {
    let metadata = fs::metadata(video_path)
        .with_context(|| format!("无法读取视频元数据：{}", video_path.display()))?;
    let modified_nanos = metadata
        .modified()
        .ok()
        .and_then(|value| value.duration_since(UNIX_EPOCH).ok())
        .map(|value| value.as_nanos())
        .unwrap_or_default();
    let mut hasher = Sha256::new();
    hasher.update(PROFILE_VERSION.as_bytes());
    hasher.update(metadata.len().to_le_bytes());
    hasher.update(modified_nanos.to_le_bytes());
    let digest = hasher.finalize();
    let mut version = String::with_capacity(16);
    for byte in &digest[..8] {
        write!(&mut version, "{byte:02x}").expect("写入字符串不会失败");
    }
    Ok(version)
}

fn is_allowed_asset_name(file: &str) -> bool {
    file == PLAYLIST_FILE || file == INIT_FILE || is_media_segment_name(file)
}

fn is_media_segment_name(file: &str) -> bool {
    file.len() == 13
        && file.starts_with("seg_")
        && file.ends_with(".m4s")
        && file[4..9].bytes().all(|value| value.is_ascii_digit())
}

fn is_readable_nonempty_file(path: &Path) -> bool {
    File::open(path)
        .and_then(|file| file.metadata())
        .map(|metadata| metadata.is_file() && metadata.len() > 0)
        .unwrap_or(false)
}

fn remove_dir_if_exists(path: &Path) -> Result<()> {
    match fs::remove_dir_all(path) {
        Ok(()) => Ok(()),
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => Ok(()),
        Err(error) => {
            Err(error).with_context(|| format!("无法清理 HLS 缓存目录：{}", path.display()))
        }
    }
}

fn concise_stderr(bytes: &[u8]) -> String {
    let text = String::from_utf8_lossy(bytes)
        .trim()
        .replace(['\r', '\n'], " ");
    if text.is_empty() {
        return "FFmpeg 未返回错误详情".to_owned();
    }
    text.chars().take(500).collect()
}

#[cfg(test)]
mod tests {
    use std::sync::atomic::{AtomicUsize, Ordering};

    use tempfile::tempdir;
    use tokio::time::{Duration, sleep};

    use super::*;

    #[derive(Default)]
    struct FakeGenerator {
        calls: AtomicUsize,
        should_fail: bool,
    }

    impl HlsGenerator for FakeGenerator {
        fn generate(&self, _video_path: &Path, output_dir: &Path) -> Result<()> {
            self.calls.fetch_add(1, Ordering::SeqCst);
            if self.should_fail {
                bail!("模拟转码失败");
            }
            fs::write(output_dir.join(PLAYLIST_FILE), "#EXTM3U\n#EXT-X-ENDLIST\n")?;
            fs::write(output_dir.join(INIT_FILE), b"init")?;
            fs::write(output_dir.join("seg_00000.m4s"), b"segment")?;
            Ok(())
        }
    }

    fn video_entry(root: &Path, id: &str) -> Arc<VideoEntry> {
        let video_path = root.join(format!("{id}.mp4"));
        let cover_path = root.join(format!("{id}.png"));
        fs::write(&video_path, b"video").expect("测试视频应创建成功");
        fs::write(&cover_path, b"cover").expect("测试封面应创建成功");
        Arc::new(VideoEntry {
            id: id.to_owned(),
            title: format!("视频{id}"),
            folder_path: String::new(),
            video_path: Some(video_path),
            cover_path,
            relative_video_path: format!("{id}.mp4"),
            published_hls_version: None,
        })
    }

    async fn wait_for_status(manager: &HlsManager, id: &str, expected: HlsStatus) {
        for _ in 0..100 {
            if manager.snapshot(id).await.status == expected {
                return;
            }
            sleep(Duration::from_millis(10)).await;
        }
        panic!("HLS 状态未在预期时间内变为 {expected:?}");
    }

    #[test]
    fn 仅允许固定清单和分片文件名() {
        assert!(is_allowed_asset_name("index.m3u8"));
        assert!(is_allowed_asset_name("init.mp4"));
        assert!(is_allowed_asset_name("seg_00042.m4s"));
        assert!(!is_allowed_asset_name("seg_42.m4s"));
        assert!(!is_allowed_asset_name("../index.m3u8"));
        assert!(!is_allowed_asset_name("other.mp4"));
    }

    #[tokio::test]
    async fn 完整生成后才发布可读取的版本化资源() {
        let root = tempdir().expect("临时目录应创建成功");
        let cache = root.path().join("hls-cache");
        let generator = Arc::new(FakeGenerator::default());
        let (_stop_tx, stop_rx) = watch::channel(false);
        let (manager, _worker) =
            HlsManager::start_with_generator(cache, 4, generator.clone(), stop_rx)
                .expect("HLS 管理器应启动成功");
        let entry = video_entry(root.path(), "video-1");

        manager.enqueue_entries(&[Arc::clone(&entry)]).await;
        wait_for_status(&manager, "video-1", HlsStatus::Ready).await;

        let snapshot = manager.snapshot("video-1").await;
        let version = snapshot.version.expect("就绪资源应包含版本");
        let playlist = manager
            .resolve_asset_path("video-1", &version, PLAYLIST_FILE)
            .await;
        assert!(playlist.is_some());
        let asset_dir = manager.asset_dir("video-1", &version);
        assert!(asset_dir.join(PUBLISHED_ASSET_FILE).is_file());
        assert!(asset_dir.join("cover.png").is_file());
        assert!(!entry.video_path.as_ref().expect("应有源视频").exists());
        assert!(!entry.cover_path.exists());
        assert_eq!(generator.calls.load(Ordering::SeqCst), 1);
    }

    #[tokio::test]
    async fn 接管已有分片时补齐资产元数据且不重复转码() {
        let root = tempdir().expect("临时目录应创建成功");
        let cache = root.path().join("hls-cache");
        let entry = video_entry(root.path(), "video-1");
        let version = media_version(entry.video_path.as_ref().expect("应有源视频"))
            .expect("缓存版本应计算成功");
        let output_dir = cache.join("video-1").join(&version);
        fs::create_dir_all(&output_dir).expect("已有 HLS 目录应创建成功");
        fs::write(output_dir.join(PLAYLIST_FILE), "#EXTM3U\n#EXT-X-ENDLIST\n")
            .expect("清单应写入成功");
        fs::write(output_dir.join(INIT_FILE), b"init").expect("初始化片应写入成功");
        fs::write(output_dir.join("seg_00000.m4s"), b"segment").expect("分片应写入成功");
        let generator = Arc::new(FakeGenerator::default());
        let (_stop_tx, stop_rx) = watch::channel(false);
        let (manager, _worker) =
            HlsManager::start_with_generator(cache, 4, generator.clone(), stop_rx)
                .expect("HLS 管理器应启动成功");

        manager.enqueue_entries(&[Arc::clone(&entry)]).await;

        assert_eq!(manager.snapshot("video-1").await.status, HlsStatus::Ready);
        assert_eq!(generator.calls.load(Ordering::SeqCst), 0);
        assert!(output_dir.join(PUBLISHED_ASSET_FILE).is_file());
        assert!(output_dir.join("cover.png").is_file());
        assert!(!entry.video_path.as_ref().expect("应有源视频").exists());
        assert!(!entry.cover_path.exists());
    }

    #[tokio::test]
    async fn 转码失败不会暴露半成品资源() {
        let root = tempdir().expect("临时目录应创建成功");
        let generator = Arc::new(FakeGenerator {
            calls: AtomicUsize::new(0),
            should_fail: true,
        });
        let (_stop_tx, stop_rx) = watch::channel(false);
        let (manager, _worker) =
            HlsManager::start_with_generator(root.path().join("hls-cache"), 4, generator, stop_rx)
                .expect("HLS 管理器应启动成功");
        let entry = video_entry(root.path(), "video-1");

        manager.enqueue_entries(&[entry]).await;
        wait_for_status(&manager, "video-1", HlsStatus::Failed).await;

        let snapshot = manager.snapshot("video-1").await;
        assert!(snapshot.version.is_none());
        assert!(
            manager
                .resolve_asset_path("video-1", "invalid", PLAYLIST_FILE)
                .await
                .is_none()
        );
    }

    #[tokio::test]
    async fn 预热数量限制不会启动范围外的视频转码() {
        let root = tempdir().expect("临时目录应创建成功");
        let generator = Arc::new(FakeGenerator::default());
        let (_stop_tx, stop_rx) = watch::channel(false);
        let (manager, _worker) = HlsManager::start_with_generator(
            root.path().join("hls-cache"),
            1,
            generator.clone(),
            stop_rx,
        )
        .expect("HLS 管理器应启动成功");
        let first = video_entry(root.path(), "video-1");
        let second = video_entry(root.path(), "video-2");

        manager.enqueue_entries(&[first, second]).await;
        wait_for_status(&manager, "video-1", HlsStatus::Ready).await;

        assert_eq!(manager.snapshot("video-2").await.status, HlsStatus::Pending);
        assert_eq!(generator.calls.load(Ordering::SeqCst), 1);
    }

    #[test]
    fn 视频内容变化会生成新的缓存版本() {
        let root = tempdir().expect("临时目录应创建成功");
        let video = root.path().join("video.mp4");
        fs::write(&video, b"first").expect("测试视频应创建成功");
        let first = media_version(&video).expect("首次版本应计算成功");

        fs::write(&video, b"second-version").expect("测试视频应更新成功");
        let second = media_version(&video).expect("更新版本应计算成功");

        assert_ne!(first, second);
    }
}
