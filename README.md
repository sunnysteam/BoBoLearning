# 菠萝早教

菠萝早教是一个面向儿童的轻量早教视频应用。Rust 服务会自动发现资源文件夹中的 MP4 视频；有同名图片时使用人工封面，没有图片时通过 FFmpeg 自动截取封面。Flutter 客户端按媒体文件夹分区展示横向视频书架，并提供进度拖动、点击播放/暂停以及分类内上下滑切换。

## 推荐部署方式

准备 Docker Desktop（支持 Docker Compose V2），在仓库根目录执行：

```powershell
docker compose up --build -d
docker compose ps
```

容器健康后访问 <http://localhost:8080>。停止服务：

```powershell
docker compose down
```

默认配置具有以下特点：

- Rust 服务与 Flutter Web 打包在同一个运行镜像中。
- 宿主机 `Service/media` 只读映射到容器 `/app/media`，媒体不会进入镜像。
- 自动封面保存在 Docker 命名卷 `/app/cover-cache`，不会修改宿主机媒体文件。
- 服务以非 root 用户运行，容器根文件系统只读，并禁用新增权限。
- 容器每 10 秒进行一次兜底扫描；文件系统事件正常时会更快更新。
- 健康检查地址为 <http://localhost:8080/healthz>。

## 放入视频资源

一个文件夹内可以放多个视频，也可以创建任意层级的子文件夹。封面图片是可选的：

```text
Service/media/
├── 动物世界/
│   ├── 01-认识小猫.mp4
│   ├── 01-认识小猫.webp
│   └── 02-认识小狗.mp4        # 无图片时自动截取封面
└── 颜色启蒙/
    └── 01-认识红色.mp4
```

每个包含视频的文件夹会自动成为首页分类，嵌套目录显示完整相对路径，例如 `启蒙/英语`；直接放在媒体根目录的视频统一显示在“未分类”。播放器上下滑只切换当前文件夹中的视频，不会跨分类串播。

首页的每个分类可独立横向滚动，最多占用 5 个位置。分类不超过 4 个视频时全部显示；超过 4 个时首页显示前 4 个视频，第 5 个位置显示“查看更多”。点击后进入带返回键的完整文件夹页面，以响应式网格平铺该分类的全部视频。首次加载期间会显示与分类书架结构一致的骨架屏。

视频支持 `.mp4`；人工封面支持 `.webp`、`.png`、`.jpg`、`.jpeg`，必须与视频位于同一文件夹且基础文件名完全相同。人工封面始终优先；缺少人工封面时，后端默认截取第 3 秒画面并生成 `640×360` WebP，短视频会回退到首帧。截帧失败时使用应用默认封面，视频仍会进入列表。

文件复制完成后，默认在 15 秒内自动反映到列表，无需重启容器。网页已经打开时，请下拉刷新或刷新浏览器以获取新列表。

查看自动发现日志：

```powershell
docker compose logs --follow bobo-learning
```

## 自定义端口和资源目录

复制 `.env.example` 为 `.env`，按需设置：

```dotenv
BOBO_PORT=8080
BOBO_MEDIA_HOST_PATH=G:/BoBoMedia
BOBO_COVER_CAPTURE_SECS=3
```

`BOBO_MEDIA_HOST_PATH` 必须指向已经存在的目录。Compose 不会替你创建目录，路径错误会直接启动失败，从而避免误挂载空目录。Windows Docker Desktop 需允许 Docker 访问该盘符。

自动封面缓存由 Compose 命名卷 `cover-cache` 持久化。执行普通的 `docker compose down` 不会删除缓存；只有显式执行 `docker compose down --volumes` 才会删除，之后服务会重新截取。

## Android 调试

Android 模拟器访问本机服务：

```powershell
cd Client
C:\Users\yxb\fvm\default\bin\flutter.bat run --dart-define=API_BASE_URL=http://10.0.2.2:8080
```

真机调试时，把地址改成电脑在同一局域网中的 IP，例如：

```powershell
C:\Users\yxb\fvm\default\bin\flutter.bat run --dart-define=API_BASE_URL=http://192.168.1.20:8080
```

Android Debug 允许局域网 HTTP；Release 部署应通过 HTTPS 访问。

## 本地开发

先安装 FFmpeg 并确保 `ffmpeg` 位于 `PATH`，然后构建 Flutter Web、启动 Rust 服务：

```powershell
cd Client
C:\Users\yxb\fvm\default\bin\flutter.bat pub get
C:\Users\yxb\fvm\default\bin\flutter.bat build web --release

cd ..\Service
cargo run
```

服务默认监听 `0.0.0.0:8080`，本地媒体目录为 `Service/media`，自动封面缓存为 `Service/cover-cache`，Web 目录为 `Client/build/web`。可通过 `BOBO_BIND`、`BOBO_MEDIA_DIR`、`BOBO_WEB_DIR`、`BOBO_COVER_CACHE_DIR`、`BOBO_DEFAULT_COVER_PATH`、`BOBO_FFMPEG_BIN`、`BOBO_COVER_CAPTURE_SECS`、`BOBO_SCAN_DEBOUNCE_MS` 和 `BOBO_SCAN_INTERVAL_SECS` 覆盖。

## 验收命令

```powershell
cd Service
cargo fmt --check
cargo clippy --all-targets --all-features -- -D warnings
cargo test

cd ..\Client
C:\Users\yxb\fvm\default\bin\flutter.bat analyze
C:\Users\yxb\fvm\default\bin\flutter.bat test
C:\Users\yxb\fvm\default\bin\flutter.bat build web --release
C:\Users\yxb\fvm\default\bin\flutter.bat build apk --debug

cd ..
docker compose config
docker compose build
docker compose up -d
docker compose exec bobo-learning ffmpeg -version
```

接口快速检查：

```powershell
Invoke-RestMethod http://localhost:8080/healthz
Invoke-RestMethod http://localhost:8080/api/v1/videos
```

完整产品范围、接口契约和验收标准见 [需求说明.md](需求说明.md)。
