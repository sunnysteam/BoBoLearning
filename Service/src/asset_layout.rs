use std::{
    fs::{self, File, OpenOptions},
    path::{Component, Path, PathBuf},
};

use anyhow::{Context, Result, bail};

pub const UNCATEGORIZED_FOLDER: &str = "未分类";

/// 拒绝跨平台路径歧义、隐藏目录和路径穿越，保留中文及嵌套分类原名。
fn validate_relative_path(value: &str) -> Result<()> {
    if value.is_empty()
        || value.split('/').any(|part| {
            part.is_empty()
                || part.starts_with('.')
                || part.contains(['\\', ':', '\0'])
                || part.chars().any(char::is_control)
        })
        || Path::new(value)
            .components()
            .any(|part| !matches!(part, Component::Normal(_)))
    {
        bail!("资产相对路径无效：{value:?}");
    }
    Ok(())
}

/// 分类必须来自原视频父目录，不能仅相信可编辑的元数据字段。
pub fn validate_category(folder: &str, relative_video: &str) -> Result<()> {
    validate_relative_path(relative_video)?;
    let expected = relative_video
        .rsplit_once('/')
        .map_or("", |(parent, _)| parent);
    if folder != expected {
        bail!("资产分类与原视频父目录不一致");
    }
    Ok(())
}

pub fn grouped_video_dir(root: &Path, folder: &str, id: &str) -> Result<PathBuf> {
    if !folder.is_empty() {
        validate_relative_path(folder)?;
    }
    validate_component(id)?;
    Ok(root
        .join(if folder.is_empty() {
            UNCATEGORIZED_FOLDER
        } else {
            folder
        })
        .join(id))
}

pub fn validate_component(value: &str) -> Result<()> {
    validate_relative_path(value)?;
    if value.contains('/') {
        bail!("资产目录名不能包含路径分隔符");
    }
    Ok(())
}

/// 操作前逐级核验，禁止通过符号链接离开正式资产库；允许尚未创建的后缀。
pub fn ensure_contained(root: &Path, path: &Path) -> Result<()> {
    let relative = path
        .strip_prefix(root)
        .context("目标路径不在正式资产库内")?;
    if relative
        .components()
        .any(|part| !matches!(part, Component::Normal(_)))
    {
        bail!("目标路径包含非法目录层级");
    }
    let mut current = root.to_path_buf();
    for component in relative.components() {
        current.push(component);
        match fs::symlink_metadata(&current) {
            Ok(metadata) => {
                if metadata.file_type().is_symlink() || !current.canonicalize()?.starts_with(root) {
                    bail!("资产路径包含符号链接或越界目录：{}", current.display());
                }
            }
            Err(error) if error.kind() == std::io::ErrorKind::NotFound => break,
            Err(error) => return Err(error).context("无法核验资产目录"),
        }
    }
    Ok(())
}

/// 服务与迁移程序共用进程锁；关闭文件句柄即释放，不以锁文件存在判断占用。
pub fn lock_asset_library(root: &Path) -> Result<File> {
    let root = root.canonicalize().context("无法定位正式资产库")?;
    let path = root.join(".hls-layout.lock");
    ensure_contained(&root, &path)?;
    let file = OpenOptions::new()
        .read(true)
        .write(true)
        .create(true)
        .truncate(false)
        .open(path)
        .context("无法打开正式资产库锁")?;
    file.try_lock()
        .context("正式资产库正在使用，请先停止服务及其他迁移进程")?;
    Ok(file)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn 分类保留中文层级且拒绝路径穿越() {
        let root = Path::new("assets");
        assert_eq!(
            grouped_video_dir(root, "课程/佩奇 英语", "id").unwrap(),
            root.join("课程/佩奇 英语/id")
        );
        assert_eq!(
            grouped_video_dir(root, "", "id").unwrap(),
            root.join("未分类/id")
        );
        for folder in [
            "../课程",
            "课程/../其他",
            "/课程",
            "C:/课程",
            "课程\\其他",
            "课程//其他",
            ".隐藏",
        ] {
            assert!(
                grouped_video_dir(root, folder, "id").is_err(),
                "不应接受：{folder}"
            );
        }
        assert!(validate_category("课程", "其他/视频.mp4").is_err());
        assert!(validate_category("课程", "课程/视频.mp4").is_ok());
    }

    #[test]
    fn 服务锁阻止同时整理资产() {
        let root = tempfile::tempdir().unwrap();
        let first = lock_asset_library(root.path()).unwrap();
        assert!(lock_asset_library(root.path()).is_err());
        drop(first);
        assert!(lock_asset_library(root.path()).is_ok());
    }

    #[test]
    fn 尚未创建的目标也不能包含越界后缀() {
        let temporary = tempfile::tempdir().unwrap();
        let root = temporary.path().canonicalize().unwrap();
        assert!(ensure_contained(&root, &root.join("不存在/../../其他")).is_err());
        assert!(ensure_contained(&root, &root.join("新分类/视频")).is_ok());
    }
}
