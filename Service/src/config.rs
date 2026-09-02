use std::{
    env,
    ffi::OsString,
    fs,
    net::SocketAddr,
    path::{Path, PathBuf},
    time::Duration,
};

use anyhow::{Context, Result, bail};

/// 服务运行配置。
#[derive(Clone, Debug)]
pub struct AppConfig {
    pub bind_addr: SocketAddr,
    pub media_dir: PathBuf,
    pub cover_cache_dir: PathBuf,
    pub default_cover_path: PathBuf,
    pub ffmpeg_bin: OsString,
    pub cover_capture_seconds: u64,
    pub scan_debounce: Duration,
    pub scan_interval: Option<Duration>,
}

impl AppConfig {
    /// 从环境变量读取配置，未设置时使用适合本地开发的默认值。
    pub fn from_env() -> Result<Self> {
        let manifest_dir = PathBuf::from(env!("CARGO_MANIFEST_DIR"));
        let bind_addr = env::var("BOBO_BIND")
            .unwrap_or_else(|_| "0.0.0.0:8080".to_owned())
            .parse::<SocketAddr>()
            .context("BOBO_BIND 不是有效的监听地址")?;

        let media_dir = env_path("BOBO_MEDIA_DIR").unwrap_or_else(|| manifest_dir.join("media"));
        let cover_cache_dir =
            env_path("BOBO_COVER_CACHE_DIR").unwrap_or_else(|| manifest_dir.join("cover-cache"));
        let default_cover_path = env_path("BOBO_DEFAULT_COVER_PATH")
            .unwrap_or_else(|| manifest_dir.join("assets").join("default-cover.png"));
        let ffmpeg_bin = env::var_os("BOBO_FFMPEG_BIN")
            .filter(|value| !value.is_empty())
            .unwrap_or_else(|| OsString::from("ffmpeg"));
        let cover_capture_seconds = parse_u64_env("BOBO_COVER_CAPTURE_SECS", 3)?;

        let debounce_ms = parse_u64_env("BOBO_SCAN_DEBOUNCE_MS", 1_500)?;
        if debounce_ms == 0 {
            bail!("BOBO_SCAN_DEBOUNCE_MS 必须大于 0");
        }

        let interval_secs = parse_u64_env("BOBO_SCAN_INTERVAL_SECS", 10)?;
        let scan_interval = (interval_secs > 0).then(|| Duration::from_secs(interval_secs));

        let config = Self {
            bind_addr,
            media_dir,
            cover_cache_dir,
            default_cover_path,
            ffmpeg_bin,
            cover_capture_seconds,
            scan_debounce: Duration::from_millis(debounce_ms),
            scan_interval,
        };
        config.validate()?;
        Ok(config)
    }

    fn validate(&self) -> Result<()> {
        if !self.media_dir.is_dir() {
            bail!("媒体目录不存在或不是文件夹：{}", self.media_dir.display());
        }

        fs::create_dir_all(&self.cover_cache_dir).with_context(|| {
            format!(
                "无法创建自动封面缓存目录：{}",
                self.cover_cache_dir.display()
            )
        })?;
        if !self.cover_cache_dir.is_dir() {
            bail!(
                "自动封面缓存路径不是文件夹：{}",
                self.cover_cache_dir.display()
            );
        }
        if !self.default_cover_path.is_file() {
            bail!(
                "默认封面不存在或不是文件：{}",
                self.default_cover_path.display()
            );
        }
        Ok(())
    }
}

fn env_path(name: &str) -> Option<PathBuf> {
    env::var_os(name)
        .filter(|value| !value.is_empty())
        .map(PathBuf::from)
}

fn parse_u64_env(name: &str, default: u64) -> Result<u64> {
    match env::var(name) {
        Ok(value) => value
            .parse::<u64>()
            .with_context(|| format!("{name} 必须是非负整数")),
        Err(env::VarError::NotPresent) => Ok(default),
        Err(error) => Err(error).with_context(|| format!("读取 {name} 失败")),
    }
}

/// 将路径转换为便于日志展示的规范文本。
#[allow(dead_code)]
pub fn display_path(path: &Path) -> String {
    path.to_string_lossy().into_owned()
}
