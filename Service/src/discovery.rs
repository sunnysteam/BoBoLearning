use std::{
    collections::{HashMap, HashSet},
    ffi::OsString,
    fmt::Write as _,
    fs::{File, read_dir},
    path::{Path, PathBuf},
    sync::Arc,
};

use anyhow::{Context, Result, bail};
use sha2::{Digest, Sha256};
use tokio::sync::{Mutex, RwLock};
use tracing::{error, info, warn};
use walkdir::{DirEntry, WalkDir};

use crate::cover::{CoverResolver, CoverSource};

/// 自动发现的视频资源。
#[derive(Clone, Debug)]
pub struct VideoEntry {
    pub id: String,
    pub title: String,
    pub folder_path: String,
    pub video_path: PathBuf,
    pub cover_path: PathBuf,
    pub relative_video_path: String,
}

/// 一次扫描得到的不可变目录快照。
#[derive(Debug, Default)]
pub struct Catalog {
    entries: Vec<Arc<VideoEntry>>,
    by_id: HashMap<String, Arc<VideoEntry>>,
}

impl Catalog {
    pub fn new(entries: Vec<VideoEntry>) -> Self {
        let entries = entries.into_iter().map(Arc::new).collect::<Vec<_>>();
        let by_id = entries
            .iter()
            .map(|entry| (entry.id.clone(), Arc::clone(entry)))
            .collect();
        Self { entries, by_id }
    }

    pub fn entries(&self) -> &[Arc<VideoEntry>] {
        &self.entries
    }

    pub fn find(&self, id: &str) -> Option<Arc<VideoEntry>> {
        self.by_id.get(id).cloned()
    }

    pub fn len(&self) -> usize {
        self.entries.len()
    }
}

/// 对目录快照提供线程安全的原子替换。
#[derive(Clone)]
pub struct CatalogStore {
    current: Arc<RwLock<Arc<Catalog>>>,
}

/// 封装媒体根目录与自动封面解析器，供启动扫描和运行时刷新复用。
#[derive(Clone)]
pub struct MediaScanner {
    media_dir: PathBuf,
    cover_resolver: CoverResolver,
}

impl MediaScanner {
    pub fn new(media_dir: PathBuf, cover_resolver: CoverResolver) -> Self {
        Self {
            media_dir,
            cover_resolver,
        }
    }

    pub fn media_dir(&self) -> &Path {
        &self.media_dir
    }

    pub fn scan(&self) -> Result<ScanReport> {
        scan_media_with_resolver(&self.media_dir, Some(&self.cover_resolver))
    }

    pub fn cleanup_unused_covers(&self, active_paths: &HashSet<PathBuf>) -> Vec<String> {
        self.cover_resolver.cleanup_unused(active_paths)
    }
}

impl CatalogStore {
    pub fn new(catalog: Catalog) -> Self {
        Self {
            current: Arc::new(RwLock::new(Arc::new(catalog))),
        }
    }

    pub async fn snapshot(&self) -> Arc<Catalog> {
        let current = self.current.read().await;
        Arc::clone(&current)
    }

    pub async fn replace(&self, catalog: Catalog) {
        *self.current.write().await = Arc::new(catalog);
    }
}

/// 扫描报告，警告不会阻止其他合法视频被发现。
pub struct ScanReport {
    pub catalog: Catalog,
    pub warnings: Vec<String>,
    pub active_generated_covers: HashSet<PathBuf>,
}

#[derive(Clone)]
struct CoverCandidate {
    path: PathBuf,
    priority: u8,
}

type CoverKey = (PathBuf, OsString);

/// 测试专用扫描入口，不启用自动封面生成。
#[cfg(test)]
pub fn scan_media(media_dir: &Path) -> Result<ScanReport> {
    scan_media_with_resolver(media_dir, None)
}

/// 递归扫描媒体目录，人工封面优先，缺失时生成并缓存自动封面。
fn scan_media_with_resolver(
    media_dir: &Path,
    cover_resolver: Option<&CoverResolver>,
) -> Result<ScanReport> {
    let root = media_dir
        .canonicalize()
        .with_context(|| format!("无法规范化媒体目录：{}", media_dir.display()))?;
    if !root.is_dir() {
        bail!("媒体路径不是文件夹：{}", root.display());
    }
    read_dir(&root).with_context(|| format!("媒体目录不可读：{}", root.display()))?;

    let mut warnings = Vec::new();
    let mut videos = Vec::new();
    let mut covers: HashMap<CoverKey, Vec<CoverCandidate>> = HashMap::new();
    let mut active_generated_covers = HashSet::new();

    let walker = WalkDir::new(&root)
        .follow_links(false)
        .into_iter()
        .filter_entry(should_visit);

    for result in walker {
        let entry = match result {
            Ok(entry) => entry,
            Err(error) => {
                warnings.push(format!("跳过无法读取的路径：{error}"));
                continue;
            }
        };

        if entry.depth() == 0 || !entry.file_type().is_file() || entry.file_type().is_symlink() {
            continue;
        }
        let path = entry.into_path();
        if is_temporary_file(&path) {
            continue;
        }

        match extension_lowercase(&path).as_deref() {
            Some("mp4") => videos.push(path),
            Some(extension) if cover_priority(extension).is_some() => {
                let Some(parent) = path.parent() else {
                    continue;
                };
                let Some(stem) = path.file_stem() else {
                    continue;
                };
                covers
                    .entry((parent.to_path_buf(), stem.to_os_string()))
                    .or_default()
                    .push(CoverCandidate {
                        path,
                        priority: cover_priority(extension).expect("已校验封面扩展名"),
                    });
            }
            _ => {}
        }
    }

    let mut discovered = Vec::new();
    for video_path in videos {
        let Some(parent) = video_path.parent() else {
            continue;
        };
        let Some(stem) = video_path.file_stem() else {
            warnings.push(format!("视频文件名无效，已跳过：{}", video_path.display()));
            continue;
        };
        let relative_video_path = relative_text(&root, &video_path);
        let id = stable_id(&relative_video_path);

        if let Err(error) = File::open(&video_path) {
            warnings.push(format!(
                "视频不可读，已跳过：{}（{error}）",
                relative_video_path
            ));
            continue;
        }

        let key = (parent.to_path_buf(), stem.to_os_string());
        let cover_path = if let Some(candidates) = covers.get_mut(&key) {
            candidates.sort_by(|left, right| {
                left.priority
                    .cmp(&right.priority)
                    .then_with(|| left.path.cmp(&right.path))
            });
            if candidates.len() > 1 {
                warnings.push(format!(
                    "视频存在多个同名封面，将按格式优先级使用 {}：{}",
                    candidates[0].path.display(),
                    relative_video_path
                ));
            }
            candidates[0].path.clone()
        } else if let Some(resolver) = cover_resolver {
            match resolver.resolve(&video_path, &id) {
                Ok(resolved) => {
                    if matches!(resolved.source, CoverSource::Cache | CoverSource::Generated) {
                        active_generated_covers.insert(resolved.path.clone());
                    }
                    if resolved.source == CoverSource::Generated {
                        info!("已自动截取视频封面：{relative_video_path}");
                    }
                    if let Some(message) = resolved.warning {
                        warnings.push(format!("{relative_video_path}：{message}"));
                    }
                    resolved.path
                }
                Err(error) => {
                    warnings.push(format!(
                        "视频缺少同名封面且自动生成失败，已跳过：{relative_video_path}（{error:#}）"
                    ));
                    continue;
                }
            }
        } else {
            warnings.push(format!("视频缺少同名封面，已跳过：{relative_video_path}"));
            continue;
        };

        if let Err(error) = File::open(&cover_path) {
            warnings.push(format!(
                "封面不可读，已跳过：{}（{error}）",
                relative_text(&root, &cover_path)
            ));
            continue;
        }

        let title = stem.to_string_lossy().into_owned();
        let folder_path = relative_text(&root, parent);
        discovered.push(VideoEntry {
            id,
            title,
            folder_path,
            video_path,
            cover_path,
            relative_video_path,
        });
    }

    discovered.sort_by(|left, right| {
        natord::compare_ignore_case(&left.folder_path, &right.folder_path)
            .then_with(|| left.folder_path.cmp(&right.folder_path))
            .then_with(|| {
                natord::compare_ignore_case(&left.relative_video_path, &right.relative_video_path)
            })
            .then_with(|| left.relative_video_path.cmp(&right.relative_video_path))
    });

    Ok(ScanReport {
        catalog: Catalog::new(discovered),
        warnings,
        active_generated_covers,
    })
}

/// 执行一次后台刷新；已有扫描进行中时直接合并本次请求。
pub async fn refresh_catalog(
    scanner: MediaScanner,
    store: CatalogStore,
    scan_guard: Arc<Mutex<()>>,
    trigger: &'static str,
) {
    let Ok(_guard) = scan_guard.try_lock() else {
        return;
    };

    let scan_worker = scanner.clone();
    let scan_result = tokio::task::spawn_blocking(move || scan_worker.scan()).await;
    match scan_result {
        Ok(Ok(report)) => {
            for message in &report.warnings {
                warn!("{message}");
            }
            let count = report.catalog.len();
            store.replace(report.catalog).await;
            for message in scanner.cleanup_unused_covers(&report.active_generated_covers) {
                warn!("{message}");
            }
            info!("媒体目录刷新完成：触发方式={trigger}，可用视频={count}");
        }
        Ok(Err(error)) => {
            error!("媒体目录刷新失败，继续使用上一份目录：{error:#}");
        }
        Err(error) => {
            error!("媒体目录扫描任务异常结束，继续使用上一份目录：{error}");
        }
    }
}

fn should_visit(entry: &DirEntry) -> bool {
    entry.depth() == 0
        || (!entry.file_name().to_string_lossy().starts_with('.')
            && !entry.file_type().is_symlink())
}

fn is_temporary_file(path: &Path) -> bool {
    let name = path
        .file_name()
        .map(|value| value.to_string_lossy().to_ascii_lowercase())
        .unwrap_or_default();
    name.starts_with('~')
        || name.ends_with('~')
        || name.contains(".tmp.")
        || name.contains(".part.")
}

fn extension_lowercase(path: &Path) -> Option<String> {
    path.extension()
        .map(|value| value.to_string_lossy().to_ascii_lowercase())
}

fn cover_priority(extension: &str) -> Option<u8> {
    match extension {
        "webp" => Some(0),
        "png" => Some(1),
        "jpg" => Some(2),
        "jpeg" => Some(3),
        _ => None,
    }
}

fn relative_text(root: &Path, path: &Path) -> String {
    path.strip_prefix(root)
        .unwrap_or(path)
        .to_string_lossy()
        .replace('\\', "/")
}

fn stable_id(relative_path: &str) -> String {
    let digest = Sha256::digest(relative_path.as_bytes());
    let mut id = String::with_capacity(32);
    for byte in &digest[..16] {
        write!(&mut id, "{byte:02x}").expect("写入字符串不会失败");
    }
    id
}

#[cfg(test)]
mod tests {
    use std::{
        fs,
        sync::{
            Arc,
            atomic::{AtomicUsize, Ordering},
        },
    };

    use tempfile::tempdir;

    use crate::cover::CoverGenerator;

    use super::*;

    struct FakeCoverGenerator {
        calls: Arc<AtomicUsize>,
        should_fail: bool,
    }

    impl CoverGenerator for FakeCoverGenerator {
        fn generate(&self, _video_path: &Path, output_path: &Path) -> Result<()> {
            self.calls.fetch_add(1, Ordering::SeqCst);
            if self.should_fail {
                anyhow::bail!("模拟截帧失败");
            }
            fs::write(output_path, b"generated-cover").expect("模拟封面应写入成功");
            Ok(())
        }
    }

    fn write_file(path: &Path) {
        if let Some(parent) = path.parent() {
            fs::create_dir_all(parent).expect("测试目录应创建成功");
        }
        fs::write(path, b"test-data").expect("测试文件应写入成功");
    }

    #[test]
    fn 发现多目录视频并按数字自然排序() {
        let root = tempdir().expect("临时目录应创建成功");
        write_file(&root.path().join("动物/10-小狗.mp4"));
        write_file(&root.path().join("动物/10-小狗.jpg"));
        write_file(&root.path().join("动物/2-小猫.MP4"));
        write_file(&root.path().join("动物/2-小猫.PNG"));
        write_file(&root.path().join("颜色/红色.mp4"));
        write_file(&root.path().join("颜色/红色.webp"));

        let report = scan_media(root.path()).expect("扫描应成功");
        let titles = report
            .catalog
            .entries()
            .iter()
            .map(|entry| entry.title.as_str())
            .collect::<Vec<_>>();

        assert_eq!(titles, vec!["2-小猫", "10-小狗", "红色"]);
        let folder_paths = report
            .catalog
            .entries()
            .iter()
            .map(|entry| entry.folder_path.as_str())
            .collect::<Vec<_>>();
        assert_eq!(folder_paths, vec!["动物", "动物", "颜色"]);
        assert!(report.warnings.is_empty());
    }

    #[test]
    fn 根目录和嵌套目录生成明确的分类路径() {
        let root = tempdir().expect("临时目录应创建成功");
        write_file(&root.path().join("根目录视频.mp4"));
        write_file(&root.path().join("根目录视频.png"));
        write_file(&root.path().join("启蒙/英语/单词.mp4"));
        write_file(&root.path().join("启蒙/英语/单词.png"));

        let report = scan_media(root.path()).expect("扫描应成功");
        let folder_paths = report
            .catalog
            .entries()
            .iter()
            .map(|entry| entry.folder_path.as_str())
            .collect::<Vec<_>>();

        assert_eq!(folder_paths, vec!["", "启蒙/英语"]);
    }

    #[test]
    fn 未配置自动生成器时缺少封面的视频会被跳过() {
        let root = tempdir().expect("临时目录应创建成功");
        write_file(&root.path().join("课程/没有封面.mp4"));

        let report = scan_media(root.path()).expect("扫描应成功");

        assert_eq!(report.catalog.len(), 0);
        assert!(report.warnings[0].contains("缺少同名封面"));
    }

    #[test]
    fn 缺少人工封面时自动生成并复用缓存() {
        let root = tempdir().expect("临时目录应创建成功");
        let media = root.path().join("media");
        let cache = root.path().join("cache");
        let default_cover = root.path().join("default.png");
        fs::create_dir_all(&cache).expect("缓存目录应创建成功");
        write_file(&media.join("课程/没有封面.mp4"));
        write_file(&default_cover);

        let calls = Arc::new(AtomicUsize::new(0));
        let resolver = CoverResolver::new(
            cache.clone(),
            default_cover,
            Arc::new(FakeCoverGenerator {
                calls: Arc::clone(&calls),
                should_fail: false,
            }),
        );
        let scanner = MediaScanner::new(media, resolver);

        let first = scanner.scan().expect("首次扫描应成功");
        let second = scanner.scan().expect("第二次扫描应成功");

        assert_eq!(first.catalog.len(), 1);
        assert_eq!(second.catalog.len(), 1);
        assert_eq!(calls.load(Ordering::SeqCst), 1);
        assert!(first.catalog.entries()[0].cover_path.starts_with(&cache));
        assert_eq!(first.active_generated_covers.len(), 1);
        assert!(first.warnings.is_empty());
    }

    #[test]
    fn 自动截帧失败时使用默认封面() {
        let root = tempdir().expect("临时目录应创建成功");
        let media = root.path().join("media");
        let cache = root.path().join("cache");
        let default_cover = root.path().join("default.png");
        fs::create_dir_all(&cache).expect("缓存目录应创建成功");
        write_file(&media.join("课程/损坏视频.mp4"));
        write_file(&default_cover);

        let resolver = CoverResolver::new(
            cache,
            default_cover.clone(),
            Arc::new(FakeCoverGenerator {
                calls: Arc::new(AtomicUsize::new(0)),
                should_fail: true,
            }),
        );
        let report = MediaScanner::new(media, resolver)
            .scan()
            .expect("扫描应成功");

        assert_eq!(report.catalog.len(), 1);
        assert_eq!(report.catalog.entries()[0].cover_path, default_cover);
        assert!(report.warnings[0].contains("已使用默认封面"));
        assert!(report.active_generated_covers.is_empty());
    }

    #[test]
    fn 多个同名封面优先选择_webp() {
        let root = tempdir().expect("临时目录应创建成功");
        let video = root.path().join("课程/颜色.mp4");
        let webp = root.path().join("课程/颜色.webp");
        write_file(&video);
        write_file(&root.path().join("课程/颜色.jpg"));
        write_file(&webp);

        let report = scan_media(root.path()).expect("扫描应成功");

        assert_eq!(
            report.catalog.entries()[0].cover_path,
            webp.canonicalize().expect("封面路径应可规范化")
        );
        assert!(report.warnings[0].contains("多个同名封面"));
    }

    #[test]
    fn 相对路径决定稳定且唯一的视频_id() {
        let root = tempdir().expect("临时目录应创建成功");
        for folder in ["甲", "乙"] {
            write_file(&root.path().join(format!("{folder}/课程.mp4")));
            write_file(&root.path().join(format!("{folder}/课程.png")));
        }

        let first = scan_media(root.path()).expect("首次扫描应成功");
        let second = scan_media(root.path()).expect("再次扫描应成功");
        let first_ids = first
            .catalog
            .entries()
            .iter()
            .map(|entry| entry.id.clone())
            .collect::<Vec<_>>();
        let second_ids = second
            .catalog
            .entries()
            .iter()
            .map(|entry| entry.id.clone())
            .collect::<Vec<_>>();

        assert_eq!(first_ids, second_ids);
        assert_ne!(first_ids[0], first_ids[1]);
        assert!(first_ids.iter().all(|id| id.len() == 32));
    }

    #[test]
    fn 隐藏目录和临时文件不会被发现() {
        let root = tempdir().expect("临时目录应创建成功");
        write_file(&root.path().join(".缓存/隐藏.mp4"));
        write_file(&root.path().join(".缓存/隐藏.png"));
        write_file(&root.path().join("课程/~临时.mp4"));
        write_file(&root.path().join("课程/~临时.png"));

        let report = scan_media(root.path()).expect("扫描应成功");

        assert_eq!(report.catalog.len(), 0);
    }
}
