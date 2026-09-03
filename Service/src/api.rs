use std::{path::PathBuf, sync::Arc};

use axum::{
    Json, Router,
    body::Body,
    extract::{Path, Request, State},
    http::{
        HeaderValue, Method, StatusCode,
        header::{
            ACCEPT_RANGES, CACHE_CONTROL, CONTENT_DISPOSITION, CONTENT_LENGTH, CONTENT_RANGE,
            CONTENT_TYPE, RANGE,
        },
    },
    response::{IntoResponse, Response},
    routing::{any, get},
};
use serde::Serialize;
use tower::ServiceExt;
use tower_http::{
    cors::{Any, CorsLayer},
    services::ServeFile,
};

use crate::discovery::{CatalogStore, VideoEntry};
use crate::update::UpdateManifest;
use tracing::warn;

/// Axum 共享状态。
#[derive(Clone)]
pub struct AppState {
    pub catalog: CatalogStore,
    pub update_dir: PathBuf,
}

#[derive(Serialize)]
struct HealthResponse {
    status: &'static str,
}

#[derive(Serialize)]
struct VideoListResponse {
    items: Vec<VideoResponse>,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct VideoResponse {
    id: String,
    title: String,
    folder_path: String,
    cover_url: String,
    stream_url: String,
}

#[derive(Serialize)]
struct ErrorEnvelope {
    error: ErrorResponse,
}

#[derive(Serialize)]
struct ErrorResponse {
    code: &'static str,
    message: &'static str,
}

/// 构建独立的媒体 API 路由。
pub fn build_router(state: AppState) -> Router {
    let api = Router::new()
        .route("/videos", get(list_videos))
        .route("/videos/{id}/cover", get(serve_cover))
        .route("/videos/{id}/stream", get(serve_stream))
        .route("/app-updates/latest", get(latest_update))
        .route(
            "/app-updates/packages/{file_name}",
            get(serve_update_package),
        )
        .fallback(api_not_found);

    let cors = CorsLayer::new()
        .allow_origin(Any)
        .allow_methods([Method::GET, Method::HEAD])
        .allow_headers([RANGE])
        .expose_headers([ACCEPT_RANGES, CONTENT_LENGTH, CONTENT_RANGE, CONTENT_TYPE]);

    Router::new()
        .route("/healthz", get(health))
        .nest("/api/v1", api)
        .route("/api/{*path}", any(api_not_found))
        .fallback(api_not_found)
        .layer(cors)
        .with_state(state)
}

async fn health() -> Json<HealthResponse> {
    Json(HealthResponse { status: "ok" })
}

async fn list_videos(State(state): State<AppState>) -> Json<VideoListResponse> {
    let snapshot = state.catalog.snapshot().await;
    let items = snapshot
        .entries()
        .iter()
        .map(|entry| VideoResponse {
            id: entry.id.clone(),
            title: entry.title.clone(),
            folder_path: entry.folder_path.clone(),
            cover_url: format!("/api/v1/videos/{}/cover", entry.id),
            stream_url: format!("/api/v1/videos/{}/stream", entry.id),
        })
        .collect();
    Json(VideoListResponse { items })
}

async fn serve_cover(
    State(state): State<AppState>,
    Path(id): Path<String>,
    request: Request,
) -> Response {
    let Some(entry) = find_entry(&state, &id).await else {
        return video_not_found();
    };
    serve_file(entry.cover_path.clone(), request, "public, max-age=3600").await
}

async fn serve_stream(
    State(state): State<AppState>,
    Path(id): Path<String>,
    request: Request,
) -> Response {
    let Some(entry) = find_entry(&state, &id).await else {
        return video_not_found();
    };
    serve_file(entry.video_path.clone(), request, "public, max-age=600").await
}

async fn latest_update(State(state): State<AppState>) -> Response {
    match UpdateManifest::load(&state.update_dir).await {
        Ok(Some(manifest)) => {
            let mut response = Json(manifest.to_response()).into_response();
            response
                .headers_mut()
                .insert(CACHE_CONTROL, HeaderValue::from_static("no-store"));
            response
        }
        Ok(None) => StatusCode::NO_CONTENT.into_response(),
        Err(error) => {
            warn!("升级清单不可用：{error:#}");
            error_response(
                StatusCode::SERVICE_UNAVAILABLE,
                "update_manifest_unavailable",
                "升级信息暂时不可用，请稍后再试",
            )
        }
    }
}

async fn serve_update_package(
    State(state): State<AppState>,
    Path(file_name): Path<String>,
    request: Request,
) -> Response {
    let manifest = match UpdateManifest::load(&state.update_dir).await {
        Ok(Some(manifest)) => manifest,
        Ok(None) => return update_not_found(),
        Err(error) => {
            warn!("读取升级包前校验清单失败：{error:#}");
            return error_response(
                StatusCode::SERVICE_UNAVAILABLE,
                "update_manifest_unavailable",
                "升级信息暂时不可用，请稍后再试",
            );
        }
    };
    if file_name != manifest.apk_file {
        return update_not_found();
    }

    let mut response = serve_file(
        manifest.package_path(&state.update_dir),
        request,
        "public, max-age=31536000, immutable",
    )
    .await;
    response.headers_mut().insert(
        CONTENT_TYPE,
        HeaderValue::from_static("application/vnd.android.package-archive"),
    );
    if let Ok(value) = HeaderValue::from_str(&format!("attachment; filename=\"{file_name}\"")) {
        response.headers_mut().insert(CONTENT_DISPOSITION, value);
    }
    response
}

async fn find_entry(state: &AppState, id: &str) -> Option<Arc<VideoEntry>> {
    state.catalog.snapshot().await.find(id)
}

async fn serve_file(path: PathBuf, request: Request, cache_control: &'static str) -> Response {
    let response = match ServeFile::new(path).oneshot(request).await {
        Ok(response) => response.map(Body::new),
        Err(error) => match error {},
    };
    let mut response = response;
    response
        .headers_mut()
        .insert(CACHE_CONTROL, HeaderValue::from_static(cache_control));
    response
}

async fn api_not_found() -> Response {
    error_response(StatusCode::NOT_FOUND, "api_not_found", "没有找到这个接口")
}

fn video_not_found() -> Response {
    error_response(StatusCode::NOT_FOUND, "video_not_found", "没有找到这个视频")
}

fn update_not_found() -> Response {
    error_response(
        StatusCode::NOT_FOUND,
        "update_not_found",
        "没有找到这个升级包",
    )
}

fn error_response(status: StatusCode, code: &'static str, message: &'static str) -> Response {
    (
        status,
        Json(ErrorEnvelope {
            error: ErrorResponse { code, message },
        }),
    )
        .into_response()
}

#[cfg(test)]
mod tests {
    use std::fs;

    use axum::{
        body::Body,
        http::{
            Request,
            header::{ACCESS_CONTROL_ALLOW_ORIGIN, ORIGIN},
        },
    };
    use http_body_util::BodyExt;
    use tempfile::{TempDir, tempdir};

    use crate::discovery::scan_media;

    use super::*;

    fn test_app() -> (TempDir, Router, String) {
        let root = tempdir().expect("临时目录应创建成功");
        let media = root.path().join("media");
        fs::create_dir_all(media.join("课程")).expect("媒体目录应创建成功");
        fs::write(media.join("课程/颜色.mp4"), b"0123456789").expect("视频应写入成功");
        fs::write(media.join("课程/颜色.png"), b"cover").expect("封面应写入成功");

        let report = scan_media(&media).expect("媒体扫描应成功");
        let id = report.catalog.entries()[0].id.clone();
        let updates = root.path().join("updates");
        fs::create_dir_all(&updates).expect("升级包目录应创建成功");
        let app = build_router(AppState {
            catalog: CatalogStore::new(report.catalog),
            update_dir: updates,
        });
        (root, app, id)
    }

    #[tokio::test]
    async fn 返回有序视频列表() {
        let (_root, app, id) = test_app();
        let response = app
            .oneshot(
                Request::builder()
                    .uri("/api/v1/videos")
                    .body(Body::empty())
                    .expect("请求应创建成功"),
            )
            .await
            .expect("请求应成功");
        assert_eq!(response.status(), StatusCode::OK);
        let body = response
            .into_body()
            .collect()
            .await
            .expect("响应体应读取成功")
            .to_bytes();
        let text = String::from_utf8(body.to_vec()).expect("响应应为 UTF-8");
        assert!(text.contains(&id));
        assert!(text.contains("颜色"));
        assert!(text.contains("\"folderPath\":\"课程\""));
        assert!(text.contains("coverUrl"));
    }

    #[tokio::test]
    async fn 视频接口支持_range_与_head() {
        let (_root, app, id) = test_app();
        let range_response = app
            .clone()
            .oneshot(
                Request::builder()
                    .uri(format!("/api/v1/videos/{id}/stream"))
                    .header(RANGE, "bytes=2-5")
                    .body(Body::empty())
                    .expect("请求应创建成功"),
            )
            .await
            .expect("请求应成功");
        assert_eq!(range_response.status(), StatusCode::PARTIAL_CONTENT);
        assert_eq!(range_response.headers()[CONTENT_RANGE], "bytes 2-5/10");
        let body = range_response
            .into_body()
            .collect()
            .await
            .expect("响应体应读取成功")
            .to_bytes();
        assert_eq!(&body[..], b"2345");

        let head_response = app
            .oneshot(
                Request::builder()
                    .method(Method::HEAD)
                    .uri(format!("/api/v1/videos/{id}/stream"))
                    .body(Body::empty())
                    .expect("请求应创建成功"),
            )
            .await
            .expect("请求应成功");
        assert_eq!(head_response.status(), StatusCode::OK);
        assert_eq!(head_response.headers()[CONTENT_LENGTH], "10");
    }

    #[tokio::test]
    async fn 未知视频和未知_api_返回中文_json_错误() {
        let (_root, app, _) = test_app();
        let video_response = app
            .clone()
            .oneshot(
                Request::builder()
                    .uri("/api/v1/videos/missing/stream")
                    .body(Body::empty())
                    .expect("请求应创建成功"),
            )
            .await
            .expect("请求应成功");
        assert_eq!(video_response.status(), StatusCode::NOT_FOUND);

        let api_response = app
            .oneshot(
                Request::builder()
                    .uri("/api/v1/unknown")
                    .body(Body::empty())
                    .expect("请求应创建成功"),
            )
            .await
            .expect("请求应成功");
        assert_eq!(api_response.status(), StatusCode::NOT_FOUND);
        assert_eq!(api_response.headers()[CONTENT_TYPE], "application/json");
    }

    #[tokio::test]
    async fn 无法满足的_range_返回_416() {
        let (_root, app, id) = test_app();
        let response = app
            .oneshot(
                Request::builder()
                    .uri(format!("/api/v1/videos/{id}/stream"))
                    .header(RANGE, "bytes=20-30")
                    .body(Body::empty())
                    .expect("请求应创建成功"),
            )
            .await
            .expect("请求应成功");

        assert_eq!(response.status(), StatusCode::RANGE_NOT_SATISFIABLE);
        assert_eq!(response.headers()[CONTENT_RANGE], "bytes */10");
    }

    #[tokio::test]
    async fn 跨域响应暴露播放器所需响应头() {
        let (_root, app, _) = test_app();
        let response = app
            .oneshot(
                Request::builder()
                    .uri("/api/v1/videos")
                    .header(ORIGIN, "http://localhost:5000")
                    .body(Body::empty())
                    .expect("请求应创建成功"),
            )
            .await
            .expect("请求应成功");

        assert_eq!(response.status(), StatusCode::OK);
        assert_eq!(response.headers()[ACCESS_CONTROL_ALLOW_ORIGIN], "*");
    }

    #[tokio::test]
    async fn 非_api_路径由独立服务返回中文_json_404() {
        let (_root, app, _) = test_app();
        let response = app
            .oneshot(
                Request::builder()
                    .uri("/lesson/colors")
                    .body(Body::empty())
                    .expect("请求应创建成功"),
            )
            .await
            .expect("请求应成功");

        assert_eq!(response.status(), StatusCode::NOT_FOUND);
        assert_eq!(response.headers()[CONTENT_TYPE], "application/json");
    }

    #[tokio::test]
    async fn 无升级清单时返回_204() {
        let (_root, app, _) = test_app();
        let response = app
            .oneshot(
                Request::builder()
                    .uri("/api/v1/app-updates/latest")
                    .body(Body::empty())
                    .expect("请求应创建成功"),
            )
            .await
            .expect("请求应成功");
        assert_eq!(response.status(), StatusCode::NO_CONTENT);
    }

    #[tokio::test]
    async fn 升级清单与安装包支持安全读取和_range() {
        let (root, app, _) = test_app();
        let updates = root.path().join("updates");
        fs::write(updates.join("bobo-learning-2.apk"), b"0123456789").expect("升级包应写入成功");
        fs::write(
            updates.join("latest.json"),
            r#"{
                "versionName":"0.2.0",
                "versionCode":2,
                "apkFile":"bobo-learning-2.apk",
                "sha256":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
                "sizeBytes":10,
                "releaseNotes":["升级测试"],
                "publishedAt":"2026-09-03T00:00:00Z"
            }"#,
        )
        .expect("升级清单应写入成功");

        let manifest_response = app
            .clone()
            .oneshot(
                Request::builder()
                    .uri("/api/v1/app-updates/latest")
                    .body(Body::empty())
                    .expect("请求应创建成功"),
            )
            .await
            .expect("请求应成功");
        assert_eq!(manifest_response.status(), StatusCode::OK);
        assert_eq!(manifest_response.headers()[CACHE_CONTROL], "no-store");
        let manifest_body = manifest_response
            .into_body()
            .collect()
            .await
            .expect("清单响应应读取成功")
            .to_bytes();
        let manifest_text = String::from_utf8(manifest_body.to_vec()).expect("清单应为 UTF-8");
        assert!(manifest_text.contains("/api/v1/app-updates/packages/bobo-learning-2.apk"));
        assert!(!manifest_text.contains("apkFile"));

        let range_response = app
            .clone()
            .oneshot(
                Request::builder()
                    .uri("/api/v1/app-updates/packages/bobo-learning-2.apk")
                    .header(RANGE, "bytes=2-5")
                    .body(Body::empty())
                    .expect("请求应创建成功"),
            )
            .await
            .expect("请求应成功");
        assert_eq!(range_response.status(), StatusCode::PARTIAL_CONTENT);
        assert_eq!(
            range_response.headers()[CONTENT_TYPE],
            "application/vnd.android.package-archive"
        );
        assert_eq!(range_response.headers()[CONTENT_RANGE], "bytes 2-5/10");

        let stale_response = app
            .oneshot(
                Request::builder()
                    .uri("/api/v1/app-updates/packages/old.apk")
                    .body(Body::empty())
                    .expect("请求应创建成功"),
            )
            .await
            .expect("请求应成功");
        assert_eq!(stale_response.status(), StatusCode::NOT_FOUND);
    }
}
