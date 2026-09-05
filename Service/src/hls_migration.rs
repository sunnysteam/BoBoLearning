use std::{
    collections::BTreeMap,
    ffi::OsString,
    fs::{self, File, OpenOptions},
    io::{Read, Write},
    path::{Path, PathBuf},
    time::{SystemTime, UNIX_EPOCH},
};

use anyhow::{Context, Result, bail};
use serde::Serialize;
use sha2::{Digest, Sha256};
use walkdir::WalkDir;

use crate::{
    asset_layout::{ensure_contained, grouped_video_dir, lock_asset_library},
    discovery::{PUBLISHED_ASSET_FILE, parse_published_asset},
};

pub struct Arguments {
    root: PathBuf,
    apply: bool,
}

pub fn parse_arguments(arguments: impl Iterator<Item = OsString>) -> Result<Option<Arguments>> {
    let arguments: Vec<_> = arguments.collect();
    if !arguments
        .iter()
        .any(|value| value == "--migrate-hls-folders")
    {
        return Ok(None);
    }
    if arguments
        .first()
        .is_none_or(|value| value != "--migrate-hls-folders")
        || arguments.len() < 2
    {
        bail!(
            "用法：bobo-learning-service --migrate-hls-folders <资产库路径> [--apply --service-stopped]"
        );
    }
    let mut apply = false;
    let mut stopped = false;
    for argument in &arguments[2..] {
        match argument.to_str() {
            Some("--apply") if !apply => apply = true,
            Some("--service-stopped") if !stopped => stopped = true,
            _ => bail!("迁移参数无效或重复：{argument:?}"),
        }
    }
    if apply != stopped {
        bail!("执行整理前必须停止服务，并同时提供 --apply --service-stopped；不带这两个参数仅预览");
    }
    Ok(Some(Arguments {
        root: PathBuf::from(&arguments[1]),
        apply,
    }))
}

#[derive(Debug, Serialize)]
struct Move {
    source: PathBuf,
    destination: PathBuf,
    category: String,
    versions: usize,
}

/// 仅整理根目录的旧版视频目录；已分类目录原样保留，所有冲突在移动前拒绝。
fn build_plan(root: &Path) -> Result<Vec<Move>> {
    let mut plan = Vec::new();
    for child in fs::read_dir(root).context("无法读取正式资产库")? {
        let child = child?;
        let name = child.file_name();
        let name = name.to_string_lossy();
        if name.len() != 32 || !name.bytes().all(|value| value.is_ascii_hexdigit()) {
            continue;
        }
        let source = child.path();
        ensure_contained(root, &source)?;
        if !child.file_type()?.is_dir() {
            bail!("旧视频路径不是文件夹：{}", source.display());
        }
        let mut destination = None;
        let mut category = String::new();
        let mut versions = 0;
        for version in fs::read_dir(&source)? {
            let version = version?;
            if !version.file_type()?.is_dir()
                || version.file_name().to_string_lossy().starts_with('.')
            {
                bail!(
                    "旧资产包含临时文件或未知内容，请先人工核对：{}",
                    version.path().display()
                );
            }
            let entry = parse_published_asset(root, &version.path().join(PUBLISHED_ASSET_FILE))
                .with_context(|| format!("旧资产未通过完整性检查：{}", version.path().display()))?;
            let target = grouped_video_dir(root, &entry.folder_path, &entry.id)?;
            ensure_contained(root, &target)?;
            if fs::symlink_metadata(&target).is_ok() {
                bail!("目标已存在，禁止合并或覆盖：{}", target.display());
            }
            if destination
                .as_ref()
                .is_some_and(|existing| existing != &target)
            {
                bail!("同一视频的不同版本分类不一致：{}", source.display());
            }
            category = if entry.folder_path.is_empty() {
                "未分类".to_owned()
            } else {
                entry.folder_path
            };
            destination = Some(target);
            versions += 1;
        }
        let destination = destination
            .with_context(|| format!("旧视频目录为空，需人工核对：{}", source.display()))?;
        plan.push(Move {
            source,
            destination,
            category,
            versions,
        });
    }
    plan.sort_by(|left, right| left.destination.cmp(&right.destination));
    for (index, item) in plan.iter().enumerate() {
        if plan
            .iter()
            .any(|other| item.destination.starts_with(&other.source))
            || plan[..index].iter().any(|other| {
                item.destination.starts_with(&other.destination)
                    || other.destination.starts_with(&item.destination)
            })
        {
            bail!(
                "迁移目标与其他视频目录重叠，需人工核对：{}",
                item.destination.display()
            );
        }
    }
    Ok(plan)
}

#[derive(Debug, Eq, PartialEq, Serialize)]
struct Fingerprint {
    bytes: u64,
    sha256: String,
}

/// 使用固定缓冲区逐文件校验，迁移大视频时不将分片整体载入内存。
fn inventory(root: &Path, directory: &Path) -> Result<BTreeMap<PathBuf, Fingerprint>> {
    let mut result = BTreeMap::new();
    let mut buffer = [0u8; 64 * 1024];
    for child in WalkDir::new(directory).follow_links(false) {
        let child = child.context("无法遍历待整理资产")?;
        ensure_contained(root, child.path())?;
        if child.file_type().is_dir() {
            continue;
        }
        if !child.file_type().is_file() {
            bail!("资产中存在非普通文件，拒绝整理：{}", child.path().display());
        }
        let mut file = File::open(child.path())?;
        let mut hash = Sha256::new();
        let mut bytes = 0;
        loop {
            let size = file.read(&mut buffer)?;
            if size == 0 {
                break;
            }
            hash.update(&buffer[..size]);
            bytes += size as u64;
        }
        result.insert(
            child.path().strip_prefix(directory)?.to_path_buf(),
            Fingerprint {
                bytes,
                sha256: format!("{:x}", hash.finalize()),
            },
        );
    }
    Ok(result)
}

fn record(journal: &mut File, value: impl Serialize) -> Result<()> {
    serde_json::to_writer(&mut *journal, &value).context("无法记录整理日志")?;
    journal.write_all(b"\n")?;
    journal.sync_all().context("无法持久化整理日志")
}

fn move_without_overwrite(root: &Path, source: &Path, target: &Path) -> Result<()> {
    ensure_contained(root, source)?;
    ensure_contained(root, target)?;
    match fs::symlink_metadata(target) {
        Ok(_) => bail!("目标已经存在，禁止覆盖：{}", target.display()),
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => {}
        Err(error) => return Err(error).context("无法核验迁移目标"),
    }
    fs::create_dir_all(target.parent().context("迁移目标缺少父目录")?)?;
    fs::rename(source, target)
        .with_context(|| format!("无法移动资产：{} -> {}", source.display(), target.display()))
}

/// 调用者持有资产库锁。移动前后核验全部文件；遇到错误按相反顺序回移，绝不覆盖。
fn apply_plan(
    root: &Path,
    plan: &[Move],
    before_move: impl Fn(usize) -> Result<()>,
) -> Result<PathBuf> {
    let fingerprints: Vec<_> = plan
        .iter()
        .map(|item| inventory(root, &item.source))
        .collect::<Result<_>>()?;
    let stamp = SystemTime::now().duration_since(UNIX_EPOCH)?.as_nanos();
    let journal_path = root.join(format!(".hls-folder-migration-{stamp}.jsonl"));
    let mut journal = OpenOptions::new()
        .write(true)
        .create_new(true)
        .open(&journal_path)?;
    record(
        &mut journal,
        serde_json::json!({"阶段": "计划", "目录": plan, "校验": fingerprints}),
    )?;
    let mut moved = Vec::<&Move>::new();
    let outcome = (|| -> Result<()> {
        for (index, item) in plan.iter().enumerate() {
            before_move(index)?;
            move_without_overwrite(root, &item.source, &item.destination)?;
            moved.push(item);
            if inventory(root, &item.destination)? != fingerprints[index] {
                bail!("移动后文件校验不一致：{}", item.destination.display());
            }
            record(
                &mut journal,
                serde_json::json!({"阶段": "已移动并校验", "目录": item}),
            )?;
        }
        record(
            &mut journal,
            serde_json::json!({"阶段": "完成", "视频数": moved.len()}),
        )?;
        Ok(())
    })();
    if let Err(error) = outcome {
        let mut rollback_errors = Vec::new();
        for item in moved.into_iter().rev() {
            match move_without_overwrite(root, &item.destination, &item.source) {
                Ok(()) => {
                    let _ = record(
                        &mut journal,
                        serde_json::json!({"阶段": "已回移", "目录": item}),
                    );
                }
                Err(error) => {
                    rollback_errors.push(format!("{}：{error:#}", item.destination.display()))
                }
            }
        }
        if rollback_errors.is_empty() {
            bail!(
                "整理失败，已移动的视频目录已回移（可能留下空分类目录）；日志={}；原因：{error:#}",
                journal_path.display()
            );
        }
        bail!(
            "整理失败，部分目录未能回移，请保留现状并按日志核对；日志={}；回移异常={}；原因：{error:#}",
            journal_path.display(),
            rollback_errors.join("；")
        );
    }
    Ok(journal_path)
}

pub fn run(arguments: Arguments) -> Result<()> {
    let root = arguments
        .root
        .canonicalize()
        .context("无法定位待整理的正式资产库")?;
    if !root.is_dir() {
        bail!("正式资产库路径不是文件夹");
    }
    // 旧版服务不认识此锁，因此执行参数仍要求操作人明确确认已停止服务。
    let _lock = if arguments.apply {
        Some(lock_asset_library(&root)?)
    } else {
        None
    };
    let plan = build_plan(&root)?;
    let mut categories = BTreeMap::<&str, usize>::new();
    for item in &plan {
        *categories.entry(&item.category).or_default() += 1;
    }
    println!(
        "{}：待整理视频 {} 个，分类 {} 个",
        if arguments.apply {
            "执行整理"
        } else {
            "只读预览"
        },
        plan.len(),
        categories.len()
    );
    for (category, count) in categories {
        println!("分类「{category}」：{count} 个视频");
    }
    for item in &plan {
        println!(
            "{} -> {}（{} 个版本）",
            item.source.display(),
            item.destination.display(),
            item.versions
        );
    }
    if plan.is_empty() {
        println!("没有需要整理的旧版视频目录，已分类资产保持不变。");
    } else if arguments.apply {
        println!("正在逐文件校验并整理，请勿启动服务或手工修改资产库。");
        let journal = apply_plan(&root, &plan, |_| Ok(()))?;
        println!(
            "整理完成，全部文件校验通过。日志：{}。请启动支持分类目录的新版服务。",
            journal.display()
        );
    } else {
        println!(
            "未移动、删除或改写任何文件。执行前请备份整个资产库并停止服务，再添加 --apply --service-stopped。"
        );
    }
    Ok(())
}

#[cfg(test)]
pub(crate) mod tests {
    use super::*;
    use crate::discovery::{
        PUBLISHED_ASSET_SCHEMA_VERSION, PublishedAssetManifest, scan_published_assets, stable_id,
    };

    pub(crate) fn create_legacy(root: &Path, relative: &str) -> PathBuf {
        let id = stable_id(relative);
        let version_dir = root.join(&id).join("version-1");
        fs::create_dir_all(&version_dir).unwrap();
        for file in ["index.m3u8", "init.mp4", "seg_00000.m4s", "cover.png"] {
            fs::write(
                version_dir.join(file),
                format!("测试资产 {relative} {file}"),
            )
            .unwrap();
        }
        let manifest = PublishedAssetManifest {
            schema_version: PUBLISHED_ASSET_SCHEMA_VERSION,
            id,
            version: "version-1".to_owned(),
            title: relative.to_owned(),
            folder_path: relative
                .rsplit_once('/')
                .map_or("", |(parent, _)| parent)
                .to_owned(),
            relative_video_path: relative.to_owned(),
            cover_file: "cover.png".to_owned(),
        };
        fs::write(
            version_dir.join(PUBLISHED_ASSET_FILE),
            serde_json::to_vec(&manifest).unwrap(),
        )
        .unwrap();
        version_dir
    }

    #[test]
    fn 预览无修改且整理保留全部内容并可重复执行() {
        let temporary = tempfile::tempdir().unwrap();
        let root = temporary.path().canonicalize().unwrap();
        create_legacy(&root, "课程/佩奇 英语/第一集.mp4");
        create_legacy(&root, "根目录.mp4");
        let old = inventory(&root, &root).unwrap();
        let plan = build_plan(&root).unwrap();
        assert_eq!(plan.len(), 2);
        assert_eq!(inventory(&root, &root).unwrap(), old);
        let expected: Vec<_> = plan
            .iter()
            .map(|item| inventory(&root, &item.source).unwrap())
            .collect();
        apply_plan(&root, &plan, |_| Ok(())).unwrap();
        for (index, item) in plan.iter().enumerate() {
            assert!(!item.source.exists());
            assert_eq!(
                inventory(&root, &item.destination).unwrap(),
                expected[index]
            );
        }
        assert!(build_plan(&root).unwrap().is_empty());
        let (entries, warnings) = scan_published_assets(&root).unwrap();
        assert!(warnings.is_empty(), "{warnings:?}");
        assert_eq!(entries.len(), 2);
        assert!(
            entries
                .iter()
                .any(|entry| entry.folder_path == "课程/佩奇 英语")
        );
        fs::remove_dir_all(root.join("课程")).unwrap();
        assert_eq!(scan_published_assets(&root).unwrap().0.len(), 1);
    }

    #[test]
    fn 整理保留同一视频的所有版本() {
        let temporary = tempfile::tempdir().unwrap();
        let root = temporary.path().canonicalize().unwrap();
        let first = create_legacy(&root, "课程/第一集.mp4");
        let second = first.parent().unwrap().join("version-2");
        fs::create_dir(&second).unwrap();
        for name in ["index.m3u8", "init.mp4", "seg_00000.m4s", "cover.png"] {
            fs::copy(first.join(name), second.join(name)).unwrap();
        }
        let mut manifest: PublishedAssetManifest =
            serde_json::from_slice(&fs::read(first.join(PUBLISHED_ASSET_FILE)).unwrap()).unwrap();
        manifest.version = "version-2".to_owned();
        fs::write(
            second.join(PUBLISHED_ASSET_FILE),
            serde_json::to_vec(&manifest).unwrap(),
        )
        .unwrap();
        let plan = build_plan(&root).unwrap();
        assert_eq!(plan.len(), 1);
        assert_eq!(plan[0].versions, 2);
        apply_plan(&root, &plan, |_| Ok(())).unwrap();
        for version in ["version-1", "version-2"] {
            assert!(
                plan[0]
                    .destination
                    .join(version)
                    .join(PUBLISHED_ASSET_FILE)
                    .is_file()
            );
        }
        assert_eq!(scan_published_assets(&root).unwrap().0.len(), 1);
    }

    #[test]
    fn 错误分类和隐藏备份不会被当成正式资产() {
        let temporary = tempfile::tempdir().unwrap();
        let root = temporary.path().canonicalize().unwrap();
        let old = create_legacy(&root, "课程/第一集.mp4");
        let wrong = root.join("错误分类").join(stable_id("课程/第一集.mp4"));
        fs::create_dir_all(wrong.parent().unwrap()).unwrap();
        fs::rename(old.parent().unwrap(), &wrong).unwrap();
        let (entries, warnings) = scan_published_assets(&root).unwrap();
        assert!(entries.is_empty());
        assert_eq!(warnings.len(), 1);
        fs::rename(wrong.parent().unwrap(), root.join(".备份")).unwrap();
        let (entries, warnings) = scan_published_assets(&root).unwrap();
        assert!(entries.is_empty());
        assert!(warnings.is_empty());
    }

    #[test]
    fn 中途失败回移已有目录不丢文件() {
        let temporary = tempfile::tempdir().unwrap();
        let root = temporary.path().canonicalize().unwrap();
        create_legacy(&root, "课程/第一集.mp4");
        create_legacy(&root, "其他/第二集.mp4");
        let plan = build_plan(&root).unwrap();
        let before: Vec<_> = plan
            .iter()
            .map(|item| inventory(&root, &item.source).unwrap())
            .collect();
        let outcome = apply_plan(&root, &plan, |index| {
            if index == 1 {
                bail!("模拟移动失败")
            } else {
                Ok(())
            }
        });
        assert!(outcome.is_err());
        for (index, item) in plan.iter().enumerate() {
            assert!(!item.destination.exists());
            assert_eq!(inventory(&root, &item.source).unwrap(), before[index]);
        }
    }

    #[test]
    fn 同名冲突和无效元数据在移动前被拒绝() {
        let temporary = tempfile::tempdir().unwrap();
        let root = temporary.path().canonicalize().unwrap();
        let version = create_legacy(&root, "课程/第一集.mp4");
        let target = grouped_video_dir(&root, "课程", &stable_id("课程/第一集.mp4")).unwrap();
        fs::create_dir_all(&target).unwrap();
        assert!(build_plan(&root).is_err());
        assert!(version.exists());
        fs::remove_dir(&target).unwrap();
        fs::write(version.join(PUBLISHED_ASSET_FILE), b"{}").unwrap();
        assert!(build_plan(&root).is_err());
        assert!(version.exists());
    }

    #[test]
    fn 执行必须明确声明停服且不接受未知参数() {
        for arguments in [
            vec!["--migrate-hls-folders", "assets", "--apply"],
            vec!["--migrate-hls-folders", "assets", "--unknown"],
        ] {
            assert!(parse_arguments(arguments.into_iter().map(OsString::from)).is_err());
        }
        let arguments = parse_arguments(
            ["--migrate-hls-folders", "assets"]
                .into_iter()
                .map(OsString::from),
        )
        .unwrap()
        .unwrap();
        assert!(!arguments.apply);
    }
}
