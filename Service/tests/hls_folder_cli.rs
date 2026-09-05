use std::{collections::BTreeMap, fs, path::Path, process::Command};

use sha2::{Digest, Sha256};
use tempfile::tempdir;
use walkdir::WalkDir;

fn files(root: &Path) -> BTreeMap<std::path::PathBuf, Vec<u8>> {
    WalkDir::new(root)
        .into_iter()
        .map(Result::unwrap)
        .filter(|entry| entry.file_type().is_file())
        .map(|entry| {
            (
                entry.path().strip_prefix(root).unwrap().to_path_buf(),
                fs::read(entry.path()).unwrap(),
            )
        })
        .collect()
}

#[test]
fn 命令行预览零写入且执行整理保留原视频所有文件() {
    let temporary = tempdir().unwrap();
    let root = temporary.path();
    let relative = "早教/佩奇 英语/第一集.mp4";
    let id = format!("{:x}", Sha256::digest(relative.as_bytes()))[..32].to_owned();
    let old = root.join(&id);
    let version = old.join("version-1");
    fs::create_dir_all(&version).unwrap();
    for file in ["index.m3u8", "init.mp4", "seg_00000.m4s", "cover.png"] {
        fs::write(version.join(file), format!("测试文件 {file}")).unwrap();
    }
    fs::write(
        version.join("asset.json"),
        serde_json::to_vec(&serde_json::json!({
            "schemaVersion": 1, "id": id, "version": "version-1", "title": "第一集",
            "folderPath": "早教/佩奇 英语", "relativeVideoPath": relative, "coverFile": "cover.png"
        }))
        .unwrap(),
    )
    .unwrap();
    let run = |flags: &[&str]| {
        Command::new(env!("CARGO_BIN_EXE_bobo_learning_service"))
            .arg("--migrate-hls-folders")
            .arg(root)
            .args(flags)
            .output()
            .unwrap()
    };
    let before = files(root);
    let preview = run(&[]);
    assert!(
        preview.status.success(),
        "预览失败：{}",
        String::from_utf8_lossy(&preview.stdout)
    );
    assert!(String::from_utf8_lossy(&preview.stdout).contains("只读预览"));
    assert_eq!(files(root), before);
    assert!(!root.join(".hls-layout.lock").exists());
    assert!(!run(&["--apply"]).status.success());
    assert_eq!(files(root), before);
    let original_files = files(&old);
    let applied = run(&["--apply", "--service-stopped"]);
    assert!(
        applied.status.success(),
        "整理失败：{}",
        String::from_utf8_lossy(&applied.stdout)
    );
    assert!(String::from_utf8_lossy(&applied.stdout).contains("全部文件校验通过"));
    assert!(!old.exists());
    assert_eq!(
        files(&root.join("早教/佩奇 英语").join(&id)),
        original_files
    );
    let repeated = run(&["--apply", "--service-stopped"]);
    assert!(repeated.status.success());
    assert!(String::from_utf8_lossy(&repeated.stdout).contains("没有需要整理"));
}

#[test]
fn 命令行执行被服务进程占用的资产锁阻止() {
    let temporary = tempdir().unwrap();
    let lock = fs::OpenOptions::new()
        .read(true)
        .write(true)
        .create_new(true)
        .open(temporary.path().join(".hls-layout.lock"))
        .unwrap();
    lock.try_lock().unwrap();
    let output = Command::new(env!("CARGO_BIN_EXE_bobo_learning_service"))
        .arg("--migrate-hls-folders")
        .arg(temporary.path())
        .args(["--apply", "--service-stopped"])
        .output()
        .unwrap();
    assert!(!output.status.success());
    assert!(String::from_utf8_lossy(&output.stdout).contains("正式资产库正在使用"));
}
