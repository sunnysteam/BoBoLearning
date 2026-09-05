use std::{path::PathBuf, sync::Arc};

use axum::{
    Json, Router,
    body::Body,
    extract::{Path, Request, State},
    http::{
        HeaderName, HeaderValue, Method, StatusCode,
        header::{
            ACCEPT_RANGES, CACHE_CONTROL, CONTENT_DISPOSITION, CONTENT_LENGTH, CONTENT_RANGE,
            CONTENT_TYPE, ETAG, LAST_MODIFIED, RANGE,
        },
    },
    response::{IntoResponse, Redirect, Response},
    routing::{any, get},
};
use serde::Serialize;
use tower::ServiceExt;
use tower_http::{
    cors::{Any, CorsLayer},
    services::ServeFile,
};

use crate::baidu::{BaiduCloud, BaiduCloudError, CloudMediaKind};
use crate::discovery::{CatalogStore, VideoEntry};
use crate::hls::HlsManager;
use crate::update::UpdateManifest;
use tracing::warn;

/// Axum 共享状态。
#[derive(Clone)]
pub struct AppState {
    pub catalog: CatalogStore,
    pub hls: HlsManager,
    pub update_dir: PathBuf,
    pub baidu: Option<BaiduCloud>,
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
    hls_url: Option<String>,
    hls_status: &'static str,
}

#[derive(Serialize)]
struct CloudMediaListResponse {
    items: Vec<CloudMediaResponse>,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct CloudMediaResponse {
    id: String,
    title: String,
    file_name: String,
    kind: &'static str,
    size_bytes: i64,
    modified_at: i64,
    thumbnail_url: String,
    content_url: String,
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
        .route("/videos/{id}/hls/{version}/{file}", get(serve_hls_asset))
        .route("/cloud/videos", get(list_cloud_videos))
        .route("/cloud/photos", get(list_cloud_photos))
        .route("/cloud/media/{id}/thumbnail", get(serve_cloud_thumbnail))
        .route("/cloud/media/{id}/content", get(serve_cloud_content))
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
    let mut items = Vec::with_capacity(snapshot.len());
    for entry in snapshot.entries() {
        let hls = state.hls.snapshot(&entry.id).await;
        let hls_url = hls
            .version
            .map(|version| format!("/api/v1/videos/{}/hls/{version}/index.m3u8", entry.id));
        let stream_url = if entry.is_incoming() {
            format!("/api/v1/videos/{}/stream", entry.id)
        } else {
            hls_url
                .clone()
                .unwrap_or_else(|| format!("/api/v1/videos/{}/stream", entry.id))
        };
        items.push(VideoResponse {
            id: entry.id.clone(),
            title: entry.title.clone(),
            folder_path: entry.folder_path.clone(),
            cover_url: format!("/api/v1/videos/{}/cover", entry.id),
            stream_url,
            hls_url,
            hls_status: hls.status.as_str(),
        });
    }
    Json(VideoListResponse { items })
}

async fn list_cloud_videos(State(state): State<AppState>) -> Response {
    list_cloud_media(state, CloudMediaKind::Video).await
}

async fn list_cloud_photos(State(state): State<AppState>) -> Response {
    list_cloud_media(state, CloudMediaKind::Photo).await
}

async fn list_cloud_media(state: AppState, kind: CloudMediaKind) -> Response {
    let Some(baidu) = state.baidu else {
        return baidu_disabled();
    };
    match baidu.list_media(kind).await {
        Ok(entries) => {
            let items = entries
                .into_iter()
                .map(|entry| {
                    let id = entry.fs_id.to_string();
                    CloudMediaResponse {
                        id: id.clone(),
                        title: entry.file_name.clone(),
                        file_name: entry.file_name,
                        kind: entry.kind.as_str(),
                        size_bytes: entry.size_bytes,
                        modified_at: entry.modified_at,
                        thumbnail_url: format!("/api/v1/cloud/media/{id}/thumbnail"),
                        content_url: format!("/api/v1/cloud/media/{id}/content"),
                    }
                })
                .collect();
            let mut response = Json(CloudMediaListResponse { items }).into_response();
            response
                .headers_mut()
                .insert(CACHE_CONTROL, HeaderValue::from_static("no-store"));
            response
        }
        Err(error) => baidu_error_response(error),
    }
}

async fn serve_cloud_thumbnail(
    State(state): State<AppState>,
    Path(id): Path<i64>,
    request: Request,
) -> Response {
    let Some(baidu) = state.baidu else {
        return baidu_disabled();
    };
    let method = to_reqwest_method(request.method());
    match baidu.proxy_thumbnail(id, method).await {
        Ok(upstream) => proxy_baidu_response(upstream, "public, max-age=3600"),
        Err(error) => baidu_error_response(error),
    }
}

async fn serve_cloud_content(
    State(state): State<AppState>,
    Path(id): Path<i64>,
    request: Request,
) -> Response {
    let Some(baidu) = state.baidu else {
        return baidu_disabled();
    };
    let method = to_reqwest_method(request.method());
    let range = request
        .headers()
        .get(RANGE)
        .and_then(|value| value.to_str().ok());
    match baidu.proxy_content(id, method, range).await {
        Ok(upstream) => proxy_baidu_response(upstream, "private, max-age=300"),
        Err(error) => baidu_error_response(error),
    }
}

fn to_reqwest_method(method: &Method) -> reqwest::Method {
    if *method == Method::HEAD {
        reqwest::Method::HEAD
    } else {
        reqwest::Method::GET
    }
}

fn proxy_baidu_response(upstream: reqwest::Response, cache_control: &'static str) -> Response {
    let status = upstream.status();
    let headers = upstream.headers().clone();
    let mut response = Response::new(Body::from_stream(upstream.bytes_stream()));
    *response.status_mut() = status;
    for name in [
        CONTENT_TYPE,
        CONTENT_LENGTH,
        CONTENT_RANGE,
        ACCEPT_RANGES,
        ETAG,
        LAST_MODIFIED,
    ] {
        if let Some(value) = headers.get(&name) {
            response.headers_mut().insert(name, value.clone());
        }
    }
    response
        .headers_mut()
        .insert(CACHE_CONTROL, HeaderValue::from_static(cache_control));
    response.headers_mut().insert(
        HeaderName::from_static("x-accel-buffering"),
        HeaderValue::from_static("no"),
    );
    response
}

async fn serve_cover(
    State(state): State<AppState>,
    Path(id): Path<String>,
    request: Request,
) -> Response {
    let Some(entry) = find_entry(&state, &id).await else {
        return video_not_found();
    };
    let cover_path = state
        .hls
        .resolve_cover_path(&id)
        .await
        .unwrap_or_else(|| entry.cover_path.clone());
    serve_file(cover_path, request, "public, max-age=3600").await
}

async fn serve_stream(
    State(state): State<AppState>,
    Path(id): Path<String>,
    request: Request,
) -> Response {
    let Some(entry) = find_entry(&state, &id).await else {
        return video_not_found();
    };
    if let Some(video_path) = entry.video_path.clone()
        && video_path.is_file()
    {
        let mut response = serve_file(video_path, request, "public, max-age=600").await;
        // 让多层 Nginx 立即转发视频字节，避免旧版 HTTP/2 代理先缓冲大段 Range。
        response.headers_mut().insert(
            HeaderName::from_static("x-accel-buffering"),
            HeaderValue::from_static("no"),
        );
        return response;
    }

    let hls = state.hls.snapshot(&id).await;
    let version = hls.version.or_else(|| entry.published_hls_version.clone());
    let Some(version) = version else {
        return video_not_found();
    };
    Redirect::temporary(&format!("/api/v1/videos/{id}/hls/{version}/index.m3u8")).into_response()
}

async fn serve_hls_asset(
    State(state): State<AppState>,
    Path((id, version, file)): Path<(String, String, String)>,
    request: Request,
) -> Response {
    if find_entry(&state, &id).await.is_none() {
        return video_not_found();
    }
    let Some(path) = state.hls.resolve_asset_path(&id, &version, &file).await else {
        return hls_asset_not_found();
    };
    let mut response = serve_file(path, request, "public, max-age=31536000, immutable").await;
    let content_type = if file.ends_with(".m3u8") {
        HeaderValue::from_static("application/vnd.apple.mpegurl")
    } else if file.ends_with(".m4s") {
        HeaderValue::from_static("video/iso.segment")
    } else {
        HeaderValue::from_static("video/mp4")
    };
    response.headers_mut().insert(CONTENT_TYPE, content_type);
    response
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

fn hls_asset_not_found() -> Response {
    error_response(
        StatusCode::NOT_FOUND,
        "hls_asset_not_found",
        "这个视频的流媒体资源还没有准备好",
    )
}

fn update_not_found() -> Response {
    error_response(
        StatusCode::NOT_FOUND,
        "update_not_found",
        "没有找到这个升级包",
    )
}

fn baidu_disabled() -> Response {
    error_response(
        StatusCode::SERVICE_UNAVAILABLE,
        "baidu_cloud_disabled",
        "百度网盘内容尚未启用",
    )
}

fn baidu_error_response(error: BaiduCloudError) -> Response {
    let (status, code, message) = match error {
        BaiduCloudError::NotFound => (
            StatusCode::NOT_FOUND,
            "baidu_media_not_found",
            "没有找到这个百度网盘文件",
        ),
        BaiduCloudError::Unauthorized => (
            StatusCode::SERVICE_UNAVAILABLE,
            "baidu_unauthorized",
            "百度网盘授权已失效，请重新授权",
        ),
        BaiduCloudError::RootNotFound => (
            StatusCode::SERVICE_UNAVAILABLE,
            "baidu_root_not_found",
            "百度网盘目录 /菠萝乐园 不存在",
        ),
        BaiduCloudError::RateLimited => (
            StatusCode::TOO_MANY_REQUESTS,
            "baidu_rate_limited",
            "百度网盘访问过于频繁，请稍后再试",
        ),
        BaiduCloudError::Unavailable => (
            StatusCode::BAD_GATEWAY,
            "baidu_unavailable",
            "百度网盘暂时不可用，请稍后再试",
        ),
    };
    warn!("百度网盘请求失败：{message}");
    error_response(status, code, message)
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
    use tokio::sync::watch;

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
        let (_stop_tx, stop_rx) = watch::channel(false);
        let (hls, _worker) =
            HlsManager::start(root.path().join("hls-cache"), "ffmpeg".into(), 4, stop_rx)
                .expect("HLS 管理器应创建成功");
        let app = build_router(AppState {
            catalog: CatalogStore::new(report.catalog),
            hls,
            update_dir: updates,
            baidu: None,
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
        assert!(text.contains("\"hlsUrl\":null"));
        assert!(text.contains("\"hlsStatus\":\"pending\""));
    }

    #[tokio::test]
    async fn 就绪_hls_清单与分片使用正确类型和长期缓存() {
        let root = tempdir().expect("临时目录应创建成功");
        let media = root.path().join("media");
        fs::create_dir_all(media.join("课程")).expect("媒体目录应创建成功");
        fs::write(media.join("课程/颜色.mp4"), b"0123456789").expect("视频应写入成功");
        fs::write(media.join("课程/颜色.png"), b"cover").expect("封面应写入成功");
        let report = scan_media(&media).expect("媒体扫描应成功");
        let id = report.catalog.entries()[0].id.clone();
        let catalog = CatalogStore::new(report.catalog);
        let updates = root.path().join("updates");
        fs::create_dir_all(&updates).expect("升级包目录应创建成功");
        let (_stop_tx, stop_rx) = watch::channel(false);
        let (hls, _worker) =
            HlsManager::start(root.path().join("hls-cache"), "ffmpeg".into(), 4, stop_rx)
                .expect("HLS 管理器应创建成功");
        hls.publish_test_asset(&id, "version-1")
            .await
            .expect("测试 HLS 资源应发布成功");
        let app = build_router(AppState {
            catalog,
            hls,
            update_dir: updates,
            baidu: None,
        });

        let list_response = app
            .clone()
            .oneshot(
                Request::builder()
                    .uri("/api/v1/videos")
                    .body(Body::empty())
                    .expect("请求应创建成功"),
            )
            .await
            .expect("请求应成功");
        let list_body = list_response
            .into_body()
            .collect()
            .await
            .expect("响应体应读取成功")
            .to_bytes();
        let list_text = String::from_utf8(list_body.to_vec()).expect("响应应为 UTF-8");
        assert!(list_text.contains("\"hlsStatus\":\"ready\""));
        assert!(list_text.contains(&format!("/api/v1/videos/{id}/hls/version-1/index.m3u8")));

        let playlist_response = app
            .clone()
            .oneshot(
                Request::builder()
                    .uri(format!("/api/v1/videos/{id}/hls/version-1/index.m3u8"))
                    .body(Body::empty())
                    .expect("请求应创建成功"),
            )
            .await
            .expect("请求应成功");
        assert_eq!(playlist_response.status(), StatusCode::OK);
        assert_eq!(
            playlist_response.headers()[CONTENT_TYPE],
            "application/vnd.apple.mpegurl"
        );
        assert_eq!(
            playlist_response.headers()[CACHE_CONTROL],
            "public, max-age=31536000, immutable"
        );

        let segment_response = app
            .oneshot(
                Request::builder()
                    .uri(format!("/api/v1/videos/{id}/hls/version-1/seg_00000.m4s"))
                    .body(Body::empty())
                    .expect("请求应创建成功"),
            )
            .await
            .expect("请求应成功");
        assert_eq!(segment_response.status(), StatusCode::OK);
        assert_eq!(
            segment_response.headers()[CONTENT_TYPE],
            "video/iso.segment"
        );
    }

    #[tokio::test]
    async fn 分类资产重启后保持原播放地址且支持封面与分片范围请求() {
        let temporary = tempdir().unwrap();
        let root = temporary.path().canonicalize().unwrap();
        let legacy = crate::hls_migration::tests::create_legacy(&root, "早教/佩奇 英语/第一集.mp4");
        let id = crate::discovery::stable_id("早教/佩奇 英语/第一集.mp4");
        let target = crate::asset_layout::grouped_video_dir(&root, "早教/佩奇 英语", &id).unwrap();
        fs::create_dir_all(target.parent().unwrap()).unwrap();
        fs::rename(legacy.parent().unwrap(), &target).unwrap();
        let (entries, warnings) = crate::discovery::scan_published_assets(&root).unwrap();
        assert!(warnings.is_empty());
        let catalog = CatalogStore::new(crate::discovery::Catalog::new(entries));
        let (_stop_tx, stop_rx) = watch::channel(false);
        let (hls, _worker) =
            HlsManager::start(root.clone(), "不存在的转码器".into(), 0, stop_rx).unwrap();
        hls.restore_published_entries(catalog.snapshot().await.entries())
            .await;
        hls.enqueue_entries(catalog.snapshot().await.entries())
            .await;
        let app = build_router(AppState {
            catalog: catalog.clone(),
            hls,
            update_dir: root.join("updates"),
            baidu: None,
        });
        let playlist_url = format!("/api/v1/videos/{id}/hls/version-1/index.m3u8");
        let response = app
            .clone()
            .oneshot(
                Request::builder()
                    .uri("/api/v1/videos")
                    .body(Body::empty())
                    .unwrap(),
            )
            .await
            .unwrap();
        let body = response.into_body().collect().await.unwrap().to_bytes();
        let text = String::from_utf8(body.to_vec()).unwrap();
        assert!(text.contains(&playlist_url));
        assert!(text.contains("\"hlsStatus\":\"ready\""));
        assert!(text.contains("早教/佩奇 英语"));
        for url in [&playlist_url, &format!("/api/v1/videos/{id}/cover")] {
            let response = app
                .clone()
                .oneshot(Request::builder().uri(url).body(Body::empty()).unwrap())
                .await
                .unwrap();
            assert_eq!(response.status(), StatusCode::OK);
            assert!(
                !response
                    .into_body()
                    .collect()
                    .await
                    .unwrap()
                    .to_bytes()
                    .is_empty()
            );
        }
        let segment_url = format!("/api/v1/videos/{id}/hls/version-1/seg_00000.m4s");
        let response = app
            .clone()
            .oneshot(
                Request::builder()
                    .uri(&segment_url)
                    .header(RANGE, "bytes=0-3")
                    .body(Body::empty())
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(response.status(), StatusCode::PARTIAL_CONTENT);
        assert_eq!(
            response
                .into_body()
                .collect()
                .await
                .unwrap()
                .to_bytes()
                .len(),
            4
        );
        let response = app
            .clone()
            .oneshot(
                Request::builder()
                    .uri(&playlist_url)
                    .method(Method::HEAD)
                    .body(Body::empty())
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(response.status(), StatusCode::OK);
        fs::remove_dir_all(root.join("早教")).unwrap();
        catalog
            .replace(crate::discovery::Catalog::new(
                crate::discovery::scan_published_assets(&root).unwrap().0,
            ))
            .await;
        let response = app
            .oneshot(
                Request::builder()
                    .uri(&segment_url)
                    .body(Body::empty())
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(response.status(), StatusCode::NOT_FOUND);
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
        assert_eq!(range_response.headers()["x-accel-buffering"], "no");
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
    async fn 百度网盘未启用时返回中文_503() {
        let (_root, app, _) = test_app();
        let response = app
            .oneshot(
                Request::builder()
                    .uri("/api/v1/cloud/videos")
                    .body(Body::empty())
                    .expect("请求应创建成功"),
            )
            .await
            .expect("请求应成功");

        assert_eq!(response.status(), StatusCode::SERVICE_UNAVAILABLE);
        let body = response
            .into_body()
            .collect()
            .await
            .expect("响应体应读取成功")
            .to_bytes();
        let text = String::from_utf8(body.to_vec()).expect("响应应为 UTF-8");
        assert!(text.contains("百度网盘内容尚未启用"));
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
