use std::{
    collections::HashSet,
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

const COVER_FILTER: &str = "scale=640:360:force_original_aspect_ratio=increase,crop=640:360";

/// 封面来源，用于生成日志和缓存维护。
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum CoverSource {
    Cache,
    Generated,
    Default,
}

/// 一次封面解析结果。
pub struct ResolvedCover {
    pub path: PathBuf,
    pub source: CoverSource,
    pub warning: Option<String>,
}

/// 视频封面生成器，测试可使用内存替身而不依赖本机 FFmpeg。
pub trait CoverGenerator: Send + Sync {
    fn generate(&self, video_path: &Path, output_path: &Path) -> Result<()>;
}

/// 通过 FFmpeg 从视频中截取单帧封面。
#[derive(Clone, Debug)]
pub struct FfmpegCoverGenerator {
    executable: OsString,
    capture_seconds: u64,
}

impl FfmpegCoverGenerator {
    pub fn new(executable: OsString, capture_seconds: u64) -> Self {
        Self {
            executable,
            capture_seconds,
        }
    }

    fn generate_at(&self, video_path: &Path, output_path: &Path, second: u64) -> Result<()> {
        let seek = second.to_string();
        let output = Command::new(&self.executable)
            .args([
                "-hide_banner",
                "-loglevel",
                "error",
                "-nostdin",
                "-y",
                "-ss",
                &seek,
                "-i",
            ])
            .arg(video_path)
            .args([
                "-map",
                "0:v:0",
                "-frames:v",
                "1",
                "-vf",
                COVER_FILTER,
                "-c:v",
                "libwebp",
                "-lossless",
                "0",
                "-quality",
                "82",
                "-compression_level",
                "4",
                "-pix_fmt",
                "yuv420p",
                "-f",
                "image2",
            ])
            .arg(output_path)
            .output()
            .with_context(|| format!("无法启动 FFmpeg：{}", self.executable.to_string_lossy()))?;

        if !output.status.success() {
            let stderr = concise_stderr(&output.stderr);
            bail!("截取第 {second} 秒失败（{}）：{stderr}", output.status);
        }
        if !is_readable_nonempty_file(output_path) {
            bail!("FFmpeg 未生成有效图片");
        }
        Ok(())
    }
}

impl CoverGenerator for FfmpegCoverGenerator {
    fn generate(&self, video_path: &Path, output_path: &Path) -> Result<()> {
        let temporary_path = temporary_cover_path(output_path)?;
        let mut attempts = vec![self.capture_seconds];
        if self.capture_seconds != 0 {
            attempts.push(0);
        }

        let mut errors = Vec::new();
        for second in attempts {
            remove_if_exists(&temporary_path)?;
            match self.generate_at(video_path, &temporary_path, second) {
                Ok(()) => {
                    remove_if_exists(output_path)?;
                    fs::rename(&temporary_path, output_path).with_context(|| {
                        format!(
                            "无法发布自动封面：{} -> {}",
                            temporary_path.display(),
                            output_path.display()
                        )
                    })?;
                    return Ok(());
                }
                Err(error) => errors.push(error.to_string()),
            }
        }

        let _ = fs::remove_file(&temporary_path);
        bail!("{}", errors.join("；"));
    }
}

/// 管理自动封面缓存、生成失败回退和无效缓存清理。
#[derive(Clone)]
pub struct CoverResolver {
    cache_dir: PathBuf,
    default_cover_path: PathBuf,
    generator: Arc<dyn CoverGenerator>,
}

impl CoverResolver {
    pub fn new(
        cache_dir: PathBuf,
        default_cover_path: PathBuf,
        generator: Arc<dyn CoverGenerator>,
    ) -> Self {
        Self {
            cache_dir,
            default_cover_path,
            generator,
        }
    }

    pub fn resolve(&self, video_path: &Path, video_id: &str) -> Result<ResolvedCover> {
        let cache_path = self.cache_path(video_path, video_id)?;
        if is_readable_nonempty_file(&cache_path) {
            return Ok(ResolvedCover {
                path: cache_path,
                source: CoverSource::Cache,
                warning: None,
            });
        }

        match self.generator.generate(video_path, &cache_path) {
            Ok(()) => Ok(ResolvedCover {
                path: cache_path,
                source: CoverSource::Generated,
                warning: None,
            }),
            Err(error) if is_readable_nonempty_file(&self.default_cover_path) => {
                Ok(ResolvedCover {
                    path: self.default_cover_path.clone(),
                    source: CoverSource::Default,
                    warning: Some(format!("自动截取封面失败，已使用默认封面（{error:#}）")),
                })
            }
            Err(error) => Err(error).with_context(|| {
                format!(
                    "自动截取封面失败，且默认封面不可用：{}",
                    self.default_cover_path.display()
                )
            }),
        }
    }

    pub fn cleanup_unused(&self, active_paths: &HashSet<PathBuf>) -> Vec<String> {
        let mut warnings = Vec::new();
        let entries = match fs::read_dir(&self.cache_dir) {
            Ok(entries) => entries,
            Err(error) => {
                warnings.push(format!(
                    "无法清理自动封面缓存目录 {}：{error}",
                    self.cache_dir.display()
                ));
                return warnings;
            }
        };

        for entry in entries {
            let entry = match entry {
                Ok(entry) => entry,
                Err(error) => {
                    warnings.push(format!("读取自动封面缓存项失败：{error}"));
                    continue;
                }
            };
            let path = entry.path();
            let file_type = match entry.file_type() {
                Ok(file_type) => file_type,
                Err(error) => {
                    warnings.push(format!("读取缓存文件类型失败 {}：{error}", path.display()));
                    continue;
                }
            };
            if !file_type.is_file() {
                continue;
            }

            let file_name = entry.file_name().to_string_lossy().into_owned();
            let is_generated = file_name.starts_with("auto-") && file_name.ends_with(".webp");
            let is_temporary = file_name.starts_with(".auto-") && file_name.ends_with(".tmp.webp");
            if ((is_generated && !active_paths.contains(&path)) || is_temporary)
                && let Err(error) = fs::remove_file(&path)
            {
                warnings.push(format!("删除无效自动封面失败 {}：{error}", path.display()));
            }
        }
        warnings
    }

    fn cache_path(&self, video_path: &Path, video_id: &str) -> Result<PathBuf> {
        let metadata = fs::metadata(video_path)
            .with_context(|| format!("无法读取视频元数据：{}", video_path.display()))?;
        let modified_nanos = metadata
            .modified()
            .ok()
            .and_then(|value| value.duration_since(UNIX_EPOCH).ok())
            .map(|value| value.as_nanos())
            .unwrap_or_default();

        let mut hasher = Sha256::new();
        hasher.update(metadata.len().to_le_bytes());
        hasher.update(modified_nanos.to_le_bytes());
        let digest = hasher.finalize();
        let mut version = String::with_capacity(16);
        for byte in &digest[..8] {
            write!(&mut version, "{byte:02x}").expect("写入字符串不会失败");
        }
        Ok(self
            .cache_dir
            .join(format!("auto-{video_id}-{version}.webp")))
    }
}

fn temporary_cover_path(output_path: &Path) -> Result<PathBuf> {
    let file_stem = output_path
        .file_stem()
        .context("自动封面缓存文件缺少文件名")?
        .to_string_lossy();
    Ok(output_path.with_file_name(format!(".{file_stem}.tmp.webp")))
}

fn is_readable_nonempty_file(path: &Path) -> bool {
    File::open(path)
        .and_then(|file| file.metadata())
        .map(|metadata| metadata.is_file() && metadata.len() > 0)
        .unwrap_or(false)
}

fn remove_if_exists(path: &Path) -> Result<()> {
    match fs::remove_file(path) {
        Ok(()) => Ok(()),
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => Ok(()),
        Err(error) => Err(error).with_context(|| format!("无法清理临时封面：{}", path.display())),
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
