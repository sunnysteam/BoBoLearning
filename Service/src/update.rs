use std::path::{Component, Path, PathBuf};

use anyhow::{Context, Result, bail};
use serde::{Deserialize, Serialize};
use tokio::fs;

const MANIFEST_FILE_NAME: &str = "latest.json";

/// 服务端磁盘中的 Android 升级清单。
#[derive(Clone, Debug, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct UpdateManifest {
    pub version_name: String,
    pub version_code: u64,
    pub apk_file: String,
    pub sha256: String,
    pub size_bytes: u64,
    #[serde(default)]
    pub release_notes: Vec<String>,
    pub published_at: String,
}

/// 面向客户端的升级清单，不暴露服务端文件路径。
#[derive(Clone, Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct UpdateResponse {
    pub version_name: String,
    pub version_code: u64,
    pub download_url: String,
    pub sha256: String,
    pub size_bytes: u64,
    pub release_notes: Vec<String>,
    pub published_at: String,
}

impl UpdateManifest {
    /// 读取并校验当前发布清单；清单不存在表示尚未发布升级包。
    pub async fn load(update_dir: &Path) -> Result<Option<Self>> {
        let manifest_path = update_dir.join(MANIFEST_FILE_NAME);
        let bytes = match fs::read(&manifest_path).await {
            Ok(bytes) => bytes,
            Err(error) if error.kind() == std::io::ErrorKind::NotFound => return Ok(None),
            Err(error) => {
                return Err(error)
                    .with_context(|| format!("无法读取升级清单：{}", manifest_path.display()));
            }
        };
        if bytes.len() > 64 * 1024 {
            bail!("升级清单超过 64 KiB 安全上限");
        }

        let manifest: Self = serde_json::from_slice(&bytes).context("升级清单不是合法 JSON")?;
        manifest.validate(update_dir).await?;
        Ok(Some(manifest))
    }

    pub fn package_path(&self, update_dir: &Path) -> PathBuf {
        update_dir.join(&self.apk_file)
    }

    pub fn to_response(&self) -> UpdateResponse {
        UpdateResponse {
            version_name: self.version_name.clone(),
            version_code: self.version_code,
            download_url: format!("/api/v1/app-updates/packages/{}", self.apk_file),
            sha256: self.sha256.clone(),
            size_bytes: self.size_bytes,
            release_notes: self.release_notes.clone(),
            published_at: self.published_at.clone(),
        }
    }

    async fn validate(&self, update_dir: &Path) -> Result<()> {
        if self.version_name.trim().is_empty() || self.version_name.len() > 64 {
            bail!("升级清单 versionName 为空或过长");
        }
        if self.version_code == 0 {
            bail!("升级清单 versionCode 必须大于 0");
        }
        if !is_safe_apk_file_name(&self.apk_file) {
            bail!("升级清单 apkFile 不是安全的 APK 文件名");
        }
        if self.sha256.len() != 64
            || !self
                .sha256
                .bytes()
                .all(|value| value.is_ascii_hexdigit() && !value.is_ascii_uppercase())
        {
            bail!("升级清单 sha256 必须是 64 位小写十六进制文本");
        }
        if self.size_bytes == 0 {
            bail!("升级清单 sizeBytes 必须大于 0");
        }
        if self.published_at.trim().is_empty() || self.published_at.len() > 64 {
            bail!("升级清单 publishedAt 为空或过长");
        }
        if self.release_notes.len() > 20
            || self
                .release_notes
                .iter()
                .any(|note| note.trim().is_empty() || note.len() > 200)
        {
            bail!("升级说明最多 20 条，且每条必须为 1 至 200 个字符");
        }

        let package_path = self.package_path(update_dir);
        let metadata = fs::metadata(&package_path)
            .await
            .with_context(|| format!("升级包不存在：{}", package_path.display()))?;
        if !metadata.is_file() {
            bail!("升级包不是普通文件：{}", package_path.display());
        }
        if metadata.len() != self.size_bytes {
            bail!(
                "升级包长度与清单不一致：清单={}，实际={}",
                self.size_bytes,
                metadata.len()
            );
        }
        Ok(())
    }
}

fn is_safe_apk_file_name(value: &str) -> bool {
    let path = Path::new(value);
    value.ends_with(".apk")
        && value.len() <= 128
        && path.components().count() == 1
        && matches!(path.components().next(), Some(Component::Normal(_)))
        && value
            .bytes()
            .all(|byte| byte.is_ascii_alphanumeric() || matches!(byte, b'.' | b'-' | b'_'))
}

#[cfg(test)]
mod tests {
    use std::fs;

    use tempfile::tempdir;

    use super::*;

    #[tokio::test]
    async fn 合法升级清单可生成同源下载地址() {
        let root = tempdir().expect("临时目录应创建成功");
        fs::write(root.path().join("bobo-learning-2.apk"), b"apk").expect("测试升级包应写入成功");
        fs::write(
            root.path().join(MANIFEST_FILE_NAME),
            r#"{
                "versionName":"0.2.0",
                "versionCode":2,
                "apkFile":"bobo-learning-2.apk",
                "sha256":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
                "sizeBytes":3,
                "releaseNotes":["升级测试"],
                "publishedAt":"2026-09-03T00:00:00Z"
            }"#,
        )
        .expect("测试清单应写入成功");

        let manifest = UpdateManifest::load(root.path())
            .await
            .expect("清单应读取成功")
            .expect("清单应存在");
        assert_eq!(manifest.version_code, 2);
        assert_eq!(
            manifest.to_response().download_url,
            "/api/v1/app-updates/packages/bobo-learning-2.apk"
        );
    }

    #[tokio::test]
    async fn 路径穿越或长度不符的清单会被拒绝() {
        let root = tempdir().expect("临时目录应创建成功");
        fs::write(
            root.path().join(MANIFEST_FILE_NAME),
            r#"{
            "versionName":"0.2.0",
            "versionCode":2,
            "apkFile":"../bad.apk",
            "sha256":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
            "sizeBytes":3,
            "publishedAt":"2026-09-03T00:00:00Z"
        }"#,
        )
        .expect("测试清单应写入成功");

        let error = UpdateManifest::load(root.path())
            .await
            .expect_err("非法清单应读取失败");
        assert!(error.to_string().contains("安全"));
    }
}
