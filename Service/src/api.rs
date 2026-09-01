use std::{path::PathBuf, sync::Arc};

use axum::{
    Json, Router,
    body::Body,
    extract::{Path, Request, State},
    http::{
        HeaderValue, Method, StatusCode,
        header::{
            ACCEPT_RANGES, CACHE_CONTROL, CONTENT_LENGTH, CONTENT_RANGE, CONTENT_TYPE, RANGE,
        },
    },
    response::{IntoResponse, Response},
    routing::{any, get},
};
use serde::Serialize;
use tower::ServiceExt;
use tower_http::{
    cors::{Any, CorsLayer},
    services::{ServeDir, ServeFile},
};

use crate::discovery::{CatalogStore, VideoEntry};

/// Axum 共享状态。
#[derive(Clone)]
pub struct AppState {
    pub catalog: CatalogStore,
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

/// 构建 API 与 Flutter Web 同源路由。
pub fn build_router(state: AppState, web_dir: PathBuf) -> Router {
    let index_file = web_dir.join("index.html");
    let api = Router::new()
        .route("/videos", get(list_videos))
        .route("/videos/{id}/cover", get(serve_cover))
        .route("/videos/{id}/stream", get(serve_stream))
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
        .fallback_service(ServeDir::new(web_dir).fallback(ServeFile::new(index_file)))
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
    serve_file(entry.cover_path.clone(), request, true).await
}

async fn serve_stream(
    State(state): State<AppState>,
    Path(id): Path<String>,
    request: Request,
) -> Response {
    let Some(entry) = find_entry(&state, &id).await else {
        return video_not_found();
    };
    serve_file(entry.video_path.clone(), request, false).await
}

async fn find_entry(state: &AppState, id: &str) -> Option<Arc<VideoEntry>> {
    state.catalog.snapshot().await.find(id)
}

async fn serve_file(path: PathBuf, request: Request, cache_cover: bool) -> Response {
    let response = match ServeFile::new(path).oneshot(request).await {
        Ok(response) => response.map(Body::new),
        Err(error) => match error {},
    };
    let mut response = response;
    let cache_value = if cache_cover {
        HeaderValue::from_static("public, max-age=3600")
    } else {
        HeaderValue::from_static("public, max-age=600")
    };
    response.headers_mut().insert(CACHE_CONTROL, cache_value);
    response
}

async fn api_not_found() -> Response {
    error_response(StatusCode::NOT_FOUND, "api_not_found", "没有找到这个接口")
}

fn video_not_found() -> Response {
    error_response(StatusCode::NOT_FOUND, "video_not_found", "没有找到这个视频")
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
        let web = root.path().join("web");
        fs::create_dir_all(media.join("课程")).expect("媒体目录应创建成功");
        fs::create_dir_all(&web).expect("网页目录应创建成功");
        fs::write(web.join("index.html"), "<html>菠萝早教</html>").expect("首页应写入成功");
        fs::write(media.join("课程/颜色.mp4"), b"0123456789").expect("视频应写入成功");
        fs::write(media.join("课程/颜色.png"), b"cover").expect("封面应写入成功");

        let report = scan_media(&media).expect("媒体扫描应成功");
        let id = report.catalog.entries()[0].id.clone();
        let app = build_router(
            AppState {
                catalog: CatalogStore::new(report.catalog),
            },
            web,
        );
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
    async fn 前端路径回退到_flutter_首页() {
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

        assert_eq!(response.status(), StatusCode::OK);
        let body = response
            .into_body()
            .collect()
            .await
            .expect("响应体应读取成功")
            .to_bytes();
        assert_eq!(&body[..], "<html>菠萝早教</html>".as_bytes());
    }
}
