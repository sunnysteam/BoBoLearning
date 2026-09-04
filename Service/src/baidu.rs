use std::{
    collections::BTreeMap,
    env, fmt, fs,
    path::{Path, PathBuf},
    sync::Arc,
    time::{Duration, Instant, SystemTime, UNIX_EPOCH},
};

use anyhow::{Context, Result, bail};
use reqwest::{Client, Method, Response, Url, header::RANGE};
use serde::{Deserialize, Serialize};
use tokio::sync::Mutex;

const FILE_API_URL: &str = "https://pan.baidu.com/rest/2.0/xpan/file";
const META_API_URL: &str = "https://pan.baidu.com/rest/2.0/xpan/multimedia";
const DEVICE_CODE_URL: &str = "https://openapi.baidu.com/oauth/2.0/device/code";
const TOKEN_URL: &str = "https://openapi.baidu.com/oauth/2.0/token";
const PAGE_SIZE: usize = 1_000;
const TOKEN_REFRESH_MARGIN_SECS: u64 = 300;

/// 百度网盘内容类型。
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum CloudMediaKind {
    Video,
    Photo,
}

impl CloudMediaKind {
    pub fn as_str(self) -> &'static str {
        match self {
            Self::Video => "video",
            Self::Photo => "photo",
        }
    }
}

/// 已通过百度开放 API 校验的只读媒体条目。
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct CloudMediaEntry {
    pub fs_id: i64,
    pub file_name: String,
    pub size_bytes: i64,
    pub modified_at: i64,
    pub kind: CloudMediaKind,
    pub thumbnail_source: Option<String>,
}

/// 不包含上游 URL 或凭证的安全错误。
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum BaiduCloudError {
    NotFound,
    Unauthorized,
    RootNotFound,
    RateLimited,
    Unavailable,
}

impl fmt::Display for BaiduCloudError {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter.write_str(match self {
            Self::NotFound => "没有找到这个百度网盘文件",
            Self::Unauthorized => "百度网盘授权已失效，请重新授权",
            Self::RootNotFound => "百度网盘目录 /菠萝乐园 不存在",
            Self::RateLimited => "百度网盘访问过于频繁，请稍后再试",
            Self::Unavailable => "百度网盘暂时不可用，请稍后再试",
        })
    }
}

impl std::error::Error for BaiduCloudError {}

/// 百度网盘只读直连客户端，统一管理令牌刷新与短期目录缓存。
#[derive(Clone)]
pub struct BaiduCloud {
    inner: Arc<BaiduCloudInner>,
}

struct BaiduCloudInner {
    client: Client,
    app_key: String,
    secret_key: String,
    root_path: String,
    token_path: PathBuf,
    token: Mutex<TokenDocument>,
    catalog: Mutex<CatalogCache>,
    cache_ttl: Duration,
}

#[derive(Default)]
struct CatalogCache {
    loaded_at: Option<Instant>,
    entries: Vec<CloudMediaEntry>,
}

#[derive(Clone, Serialize, Deserialize)]
struct TokenDocument {
    access_token: String,
    refresh_token: String,
    expires_at: u64,
}

#[derive(Deserialize)]
struct FileListResponse {
    #[serde(default)]
    errno: i32,
    #[serde(default)]
    list: Vec<FileListEntry>,
}

#[derive(Deserialize)]
struct FileListEntry {
    fs_id: i64,
    server_filename: String,
    #[serde(default)]
    size: i64,
    #[serde(default)]
    server_mtime: i64,
    #[serde(default)]
    isdir: i32,
    #[serde(default)]
    category: i32,
    #[serde(default)]
    thumbs: BTreeMap<String, String>,
}

#[derive(Deserialize)]
struct FileMetaResponse {
    #[serde(default)]
    errno: i32,
    #[serde(default)]
    list: Vec<FileMetaEntry>,
}

#[derive(Deserialize)]
struct FileMetaEntry {
    fs_id: i64,
    #[serde(default)]
    dlink: String,
}

#[derive(Deserialize)]
struct DeviceCodeResponse {
    device_code: String,
    user_code: String,
    verification_url: String,
    #[serde(default)]
    qrcode_url: String,
    expires_in: u64,
    interval: u64,
}

#[derive(Deserialize)]
struct OAuthTokenResponse {
    #[serde(default)]
    access_token: String,
    #[serde(default)]
    refresh_token: String,
    #[serde(default)]
    expires_in: u64,
    #[serde(default)]
    error: String,
}

impl BaiduCloud {
    /// 根据环境变量初始化；未启用时返回 `None`。
    pub async fn from_env() -> Result<Option<Self>> {
        if !parse_bool_env("BOBO_BAIDU_ENABLED", false)? {
            return Ok(None);
        }

        let app_key = required_env("BAIDU_NETDISK_APP_KEY")?;
        let secret_key = required_env("BAIDU_NETDISK_SECRET_KEY")?;
        let root_path = normalize_root_path(
            env::var("BOBO_BAIDU_ROOT_PATH").unwrap_or_else(|_| "/菠萝乐园".to_owned()),
        )?;
        let token_path = token_path_from_env();
        let token_text = tokio::fs::read_to_string(&token_path)
            .await
            .with_context(|| {
                format!(
                    "百度网盘令牌不存在，请先运行 --authorize-baidu：{}",
                    token_path.display()
                )
            })?;
        let token: TokenDocument =
            serde_json::from_str(&token_text).context("百度网盘令牌文件格式不正确，请重新授权")?;
        validate_token(&token)?;
        let cache_secs = parse_u64_env("BOBO_BAIDU_CACHE_SECS", 60)?;
        let client = Client::builder()
            .connect_timeout(Duration::from_secs(10))
            .timeout(Duration::from_secs(30))
            .redirect(reqwest::redirect::Policy::limited(10))
            .build()
            .context("无法初始化百度网盘 HTTP 客户端")?;

        Ok(Some(Self {
            inner: Arc::new(BaiduCloudInner {
                client,
                app_key,
                secret_key,
                root_path,
                token_path,
                token: Mutex::new(token),
                catalog: Mutex::new(CatalogCache::default()),
                cache_ttl: Duration::from_secs(cache_secs),
            }),
        }))
    }

    pub fn root_path(&self) -> &str {
        &self.inner.root_path
    }

    /// 返回指定类型的直接子文件，并再次确保文件名倒序稳定排列。
    pub async fn list_media(
        &self,
        kind: CloudMediaKind,
    ) -> std::result::Result<Vec<CloudMediaEntry>, BaiduCloudError> {
        let mut items = self
            .load_catalog(false)
            .await?
            .into_iter()
            .filter(|item| item.kind == kind)
            .collect::<Vec<_>>();
        sort_by_file_name_desc(&mut items);
        Ok(items)
    }

    /// 将已缓存的缩略图地址代理到客户端。
    pub async fn proxy_thumbnail(
        &self,
        id: i64,
        method: Method,
    ) -> std::result::Result<Response, BaiduCloudError> {
        let entry = self.find_entry(id).await?;
        let source = entry.thumbnail_source.ok_or(BaiduCloudError::NotFound)?;
        let url = Url::parse(&source).map_err(|_| BaiduCloudError::Unavailable)?;
        if !matches!(url.scheme(), "http" | "https") {
            return Err(BaiduCloudError::Unavailable);
        }
        // 百度部分缩略图节点拒绝 HEAD；改用 GET 获取响应头，Axum 会为 HEAD 自动移除响应体。
        let upstream_method = if method == Method::HEAD {
            Method::GET
        } else {
            method
        };
        self.inner
            .client
            .request(upstream_method, url)
            .header("User-Agent", "pan.baidu.com")
            .send()
            .await
            .map_err(|_| BaiduCloudError::Unavailable)
    }

    /// 获取临时下载链接并代理原始内容，Range 会原样传给百度下载节点。
    pub async fn proxy_content(
        &self,
        id: i64,
        method: Method,
        range: Option<&str>,
    ) -> std::result::Result<Response, BaiduCloudError> {
        self.find_entry(id).await?;
        let mut access_token = self.access_token(false).await?;
        let mut dlink = match self.fetch_dlink(id, &access_token).await {
            Err(BaiduCloudError::Unauthorized) => {
                access_token = self.access_token(true).await?;
                self.fetch_dlink(id, &access_token).await?
            }
            result => result?,
        };
        dlink
            .query_pairs_mut()
            .append_pair("access_token", &access_token);

        let mut request = self
            .inner
            .client
            .request(method, dlink)
            .header("User-Agent", "pan.baidu.com");
        if let Some(value) = range {
            request = request.header(RANGE, value);
        }
        request
            .send()
            .await
            .map_err(|_| BaiduCloudError::Unavailable)
    }

    async fn find_entry(&self, id: i64) -> std::result::Result<CloudMediaEntry, BaiduCloudError> {
        if let Some(entry) = self
            .load_catalog(false)
            .await?
            .into_iter()
            .find(|entry| entry.fs_id == id)
        {
            return Ok(entry);
        }
        self.load_catalog(true)
            .await?
            .into_iter()
            .find(|entry| entry.fs_id == id)
            .ok_or(BaiduCloudError::NotFound)
    }

    async fn load_catalog(
        &self,
        force_refresh: bool,
    ) -> std::result::Result<Vec<CloudMediaEntry>, BaiduCloudError> {
        if !force_refresh {
            let cache = self.inner.catalog.lock().await;
            if cache
                .loaded_at
                .is_some_and(|loaded| loaded.elapsed() < self.inner.cache_ttl)
            {
                return Ok(cache.entries.clone());
            }
        }

        let entries = self.fetch_catalog().await?;
        let mut cache = self.inner.catalog.lock().await;
        cache.loaded_at = Some(Instant::now());
        cache.entries = entries.clone();
        Ok(entries)
    }

    async fn fetch_catalog(&self) -> std::result::Result<Vec<CloudMediaEntry>, BaiduCloudError> {
        let mut all = Vec::new();
        let mut start = 0usize;
        loop {
            let access_token = self.access_token(false).await?;
            let response = self.request_file_list(start, &access_token).await?;
            if response.errno != 0 {
                if response.errno == -6 {
                    let refreshed = self.access_token(true).await?;
                    let retried = self.request_file_list(start, &refreshed).await?;
                    if retried.errno != 0 {
                        return Err(map_errno(retried.errno));
                    }
                    let count = retried.list.len();
                    all.extend(retried.list);
                    if count < PAGE_SIZE {
                        break;
                    }
                } else {
                    return Err(map_errno(response.errno));
                }
            } else {
                let count = response.list.len();
                all.extend(response.list);
                if count < PAGE_SIZE {
                    break;
                }
            }
            start += PAGE_SIZE;
        }

        let mut entries = map_list_entries(all);
        sort_by_file_name_desc(&mut entries);
        Ok(entries)
    }

    async fn request_file_list(
        &self,
        start: usize,
        access_token: &str,
    ) -> std::result::Result<FileListResponse, BaiduCloudError> {
        self.inner
            .client
            .get(FILE_API_URL)
            .query(&[
                ("method", "list".to_owned()),
                ("dir", self.inner.root_path.clone()),
                ("order", "name".to_owned()),
                ("desc", "1".to_owned()),
                ("start", start.to_string()),
                ("limit", PAGE_SIZE.to_string()),
                ("web", "1".to_owned()),
                ("access_token", access_token.to_owned()),
            ])
            .send()
            .await
            .map_err(|_| BaiduCloudError::Unavailable)?
            .json::<FileListResponse>()
            .await
            .map_err(|_| BaiduCloudError::Unavailable)
    }

    async fn fetch_dlink(
        &self,
        id: i64,
        access_token: &str,
    ) -> std::result::Result<Url, BaiduCloudError> {
        let fsids = format!("[{id}]");
        let response = self
            .inner
            .client
            .get(META_API_URL)
            .query(&[
                ("method", "filemetas"),
                ("dlink", "1"),
                ("fsids", fsids.as_str()),
                ("access_token", access_token),
            ])
            .send()
            .await
            .map_err(|_| BaiduCloudError::Unavailable)?
            .json::<FileMetaResponse>()
            .await
            .map_err(|_| BaiduCloudError::Unavailable)?;
        if response.errno != 0 {
            return Err(map_errno(response.errno));
        }
        let meta = response
            .list
            .into_iter()
            .find(|item| item.fs_id == id)
            .ok_or(BaiduCloudError::NotFound)?;
        if meta.dlink.is_empty() {
            return Err(BaiduCloudError::Unavailable);
        }
        Url::parse(&meta.dlink).map_err(|_| BaiduCloudError::Unavailable)
    }

    async fn access_token(
        &self,
        force_refresh: bool,
    ) -> std::result::Result<String, BaiduCloudError> {
        let mut token = self.inner.token.lock().await;
        let now = unix_timestamp();
        if !force_refresh && token.expires_at > now.saturating_add(TOKEN_REFRESH_MARGIN_SECS) {
            return Ok(token.access_token.clone());
        }

        let refreshed = self
            .inner
            .client
            .get(TOKEN_URL)
            .query(&[
                ("grant_type", "refresh_token"),
                ("refresh_token", token.refresh_token.as_str()),
                ("client_id", self.inner.app_key.as_str()),
                ("client_secret", self.inner.secret_key.as_str()),
            ])
            .send()
            .await
            .map_err(|_| BaiduCloudError::Unavailable)?
            .json::<OAuthTokenResponse>()
            .await
            .map_err(|_| BaiduCloudError::Unavailable)?;
        if refreshed.access_token.is_empty() || refreshed.refresh_token.is_empty() {
            return Err(BaiduCloudError::Unauthorized);
        }
        *token = token_from_response(refreshed);
        write_token(&self.inner.token_path, &token).map_err(|_| BaiduCloudError::Unavailable)?;
        Ok(token.access_token.clone())
    }
}

/// 启动一次设备码授权，并将令牌安全写入独立运行目录。
pub async fn authorize_from_env() -> Result<()> {
    let app_key = required_env("BAIDU_NETDISK_APP_KEY")?;
    let secret_key = required_env("BAIDU_NETDISK_SECRET_KEY")?;
    let token_path = token_path_from_env();
    let client = Client::builder()
        .connect_timeout(Duration::from_secs(10))
        .timeout(Duration::from_secs(30))
        .build()
        .context("无法初始化百度授权客户端")?;

    let device = client
        .get(DEVICE_CODE_URL)
        .query(&[
            ("response_type", "device_code"),
            ("client_id", app_key.as_str()),
            ("scope", "basic,netdisk"),
        ])
        .send()
        .await
        .map_err(|_| anyhow::anyhow!("获取百度设备码失败，请检查网络后重试"))?
        .json::<DeviceCodeResponse>()
        .await
        .map_err(|_| anyhow::anyhow!("百度设备码响应格式不正确"))?;

    println!("请在浏览器打开以下地址并完成百度网盘授权：");
    println!("{}?code={}", device.verification_url, device.user_code);
    println!("授权码：{}", device.user_code);
    if !device.qrcode_url.is_empty() {
        println!("也可以扫描二维码：{}", device.qrcode_url);
    }
    println!("正在等待授权，请不要关闭终端……");

    let interval = Duration::from_secs(device.interval.max(3));
    let deadline = Instant::now() + Duration::from_secs(device.expires_in);
    loop {
        if Instant::now() >= deadline {
            bail!("设备授权码已过期，请重新运行授权命令");
        }
        tokio::time::sleep(interval).await;
        let response = client
            .get(TOKEN_URL)
            .query(&[
                ("grant_type", "device_token"),
                ("code", device.device_code.as_str()),
                ("client_id", app_key.as_str()),
                ("client_secret", secret_key.as_str()),
            ])
            .send()
            .await
            .map_err(|_| anyhow::anyhow!("轮询百度授权状态失败，请检查网络后重试"))?
            .json::<OAuthTokenResponse>()
            .await
            .map_err(|_| anyhow::anyhow!("百度授权响应格式不正确"))?;
        if !response.access_token.is_empty() && !response.refresh_token.is_empty() {
            let token = token_from_response(response);
            write_token(&token_path, &token)?;
            println!("百度网盘授权成功，令牌已安全保存。此终端不会显示令牌内容。");
            return Ok(());
        }
        if !matches!(
            response.error.as_str(),
            "authorization_pending" | "slow_down"
        ) {
            bail!("百度网盘授权失败，请重新发起授权");
        }
    }
}

fn map_list_entries(entries: Vec<FileListEntry>) -> Vec<CloudMediaEntry> {
    entries
        .into_iter()
        .filter(|entry| entry.isdir == 0 && matches!(entry.category, 1 | 3))
        .map(|entry| CloudMediaEntry {
            fs_id: entry.fs_id,
            file_name: entry.server_filename,
            size_bytes: entry.size,
            modified_at: entry.server_mtime,
            kind: if entry.category == 1 {
                CloudMediaKind::Video
            } else {
                CloudMediaKind::Photo
            },
            thumbnail_source: preferred_thumbnail(&entry.thumbs),
        })
        .collect()
}

fn preferred_thumbnail(thumbs: &BTreeMap<String, String>) -> Option<String> {
    ["url3", "url2", "url1"]
        .into_iter()
        .find_map(|key| thumbs.get(key).filter(|value| !value.is_empty()).cloned())
        .or_else(|| thumbs.values().find(|value| !value.is_empty()).cloned())
}

fn sort_by_file_name_desc(items: &mut [CloudMediaEntry]) {
    items.sort_by(|left, right| {
        right
            .file_name
            .to_lowercase()
            .cmp(&left.file_name.to_lowercase())
            .then_with(|| right.file_name.cmp(&left.file_name))
            .then_with(|| right.fs_id.cmp(&left.fs_id))
    });
}

fn token_from_response(response: OAuthTokenResponse) -> TokenDocument {
    TokenDocument {
        access_token: response.access_token,
        refresh_token: response.refresh_token,
        expires_at: unix_timestamp().saturating_add(response.expires_in),
    }
}

fn write_token(path: &Path, token: &TokenDocument) -> Result<()> {
    validate_token(token)?;
    let parent = path.parent().context("百度令牌路径缺少父目录")?;
    fs::create_dir_all(parent)
        .with_context(|| format!("无法创建百度网盘授权目录：{}", parent.display()))?;
    let temporary = path.with_extension("json.tmp");
    let content = serde_json::to_vec_pretty(token).context("无法序列化百度网盘令牌")?;
    fs::write(&temporary, content)
        .with_context(|| format!("无法写入百度网盘临时令牌：{}", temporary.display()))?;
    #[cfg(windows)]
    if path.exists() {
        fs::remove_file(path)
            .with_context(|| format!("无法替换旧的百度网盘令牌：{}", path.display()))?;
    }
    fs::rename(&temporary, path)
        .with_context(|| format!("无法发布百度网盘令牌：{}", path.display()))?;
    set_private_permissions(path)?;
    Ok(())
}

#[cfg(unix)]
fn set_private_permissions(path: &Path) -> Result<()> {
    use std::os::unix::fs::PermissionsExt;
    fs::set_permissions(path, fs::Permissions::from_mode(0o600))
        .with_context(|| format!("无法收紧百度网盘令牌权限：{}", path.display()))
}

#[cfg(not(unix))]
fn set_private_permissions(_path: &Path) -> Result<()> {
    Ok(())
}

fn validate_token(token: &TokenDocument) -> Result<()> {
    if token.access_token.is_empty() || token.refresh_token.is_empty() {
        bail!("百度网盘令牌内容不完整，请重新授权");
    }
    Ok(())
}

fn normalize_root_path(value: String) -> Result<String> {
    let trimmed = value.trim();
    if !trimmed.starts_with('/') {
        bail!("BOBO_BAIDU_ROOT_PATH 必须是以 / 开头的百度网盘绝对路径");
    }
    if trimmed.contains("我的网盘") {
        bail!("BOBO_BAIDU_ROOT_PATH 不应包含客户端展示名称“我的网盘”");
    }
    let normalized = if trimmed.len() > 1 {
        trimmed.trim_end_matches('/')
    } else {
        trimmed
    };
    Ok(normalized.to_owned())
}

fn required_env(name: &str) -> Result<String> {
    let value = env::var(name).with_context(|| format!("缺少环境变量 {name}"))?;
    if value.trim().is_empty() {
        bail!("环境变量 {name} 不能为空");
    }
    Ok(value)
}

fn token_path_from_env() -> PathBuf {
    env::var_os("BOBO_BAIDU_TOKEN_PATH")
        .filter(|value| !value.is_empty())
        .map(PathBuf::from)
        .unwrap_or_else(|| {
            PathBuf::from(env!("CARGO_MANIFEST_DIR"))
                .join("baidu-auth")
                .join("token.json")
        })
}

fn parse_bool_env(name: &str, default: bool) -> Result<bool> {
    match env::var(name) {
        Ok(value) => match value.trim().to_ascii_lowercase().as_str() {
            "1" | "true" | "yes" | "on" => Ok(true),
            "0" | "false" | "no" | "off" => Ok(false),
            _ => bail!("{name} 必须是 true 或 false"),
        },
        Err(env::VarError::NotPresent) => Ok(default),
        Err(error) => Err(error).with_context(|| format!("读取 {name} 失败")),
    }
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

fn map_errno(errno: i32) -> BaiduCloudError {
    match errno {
        -6 => BaiduCloudError::Unauthorized,
        -9 => BaiduCloudError::RootNotFound,
        31034 => BaiduCloudError::RateLimited,
        _ => BaiduCloudError::Unavailable,
    }
}

fn unix_timestamp() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_secs()
}

#[cfg(test)]
mod tests {
    use super::*;

    fn entry(id: i64, name: &str, category: i32, isdir: i32) -> FileListEntry {
        FileListEntry {
            fs_id: id,
            server_filename: name.to_owned(),
            size: 12,
            server_mtime: 34,
            isdir,
            category,
            thumbs: BTreeMap::from([("url1".to_owned(), "https://example.test/a".to_owned())]),
        }
    }

    #[test]
    fn 只保留视频图片并按文件名倒序排列() {
        let mut items = map_list_entries(vec![
            entry(1, "A.mp4", 1, 0),
            entry(2, "c.jpg", 3, 0),
            entry(3, "b.txt", 6, 0),
            entry(4, "目录", 1, 1),
            entry(5, "B.mp4", 1, 0),
        ]);
        sort_by_file_name_desc(&mut items);

        let names = items
            .iter()
            .map(|item| item.file_name.as_str())
            .collect::<Vec<_>>();
        assert_eq!(names, vec!["c.jpg", "B.mp4", "A.mp4"]);
        assert_eq!(items[0].kind, CloudMediaKind::Photo);
    }

    #[test]
    fn 百度根路径会去除尾斜杠并拒绝我的网盘前缀() {
        assert_eq!(
            normalize_root_path("/菠萝乐园/".to_owned()).expect("路径应有效"),
            "/菠萝乐园"
        );
        assert!(normalize_root_path("我的网盘/菠萝乐园".to_owned()).is_err());
    }
}
