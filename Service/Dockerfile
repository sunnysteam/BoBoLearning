# syntax=docker/dockerfile:1.7

FROM debian:bookworm-slim AS flutter-builder

ARG FLUTTER_VERSION=3.47.2
RUN apt-get update \
    && apt-get install --yes --no-install-recommends ca-certificates curl git unzip xz-utils zip \
    && rm -rf /var/lib/apt/lists/* \
    && git clone --branch "${FLUTTER_VERSION}" --depth 1 \
        https://github.com/flutter/flutter.git /opt/flutter

ENV PATH=/opt/flutter/bin:/opt/flutter/bin/cache/dart-sdk/bin:${PATH}
RUN flutter config --no-analytics --enable-web \
    && flutter precache --web

WORKDIR /workspace/Client

COPY Client/pubspec.yaml Client/pubspec.lock ./
RUN flutter pub get

COPY Client/lib ./lib
COPY Client/web ./web
COPY Client/analysis_options.yaml Client/.metadata ./
RUN flutter build web --release --base-href=/

FROM rust:1.95.0-bookworm AS rust-builder
WORKDIR /workspace/Service

COPY Service/Cargo.toml Service/Cargo.lock ./
COPY Service/src ./src
RUN cargo build --release --locked

FROM debian:bookworm-slim AS runtime

RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt/lists,sharing=locked \
    rm -f /etc/apt/apt.conf.d/docker-clean \
    && apt-get -o Acquire::Retries=5 update \
    && install_succeeded=0 \
    && for attempt in 1 2 3; do \
        if DEBIAN_FRONTEND=noninteractive apt-get -o Acquire::Retries=5 install \
            --yes --no-install-recommends --fix-missing ca-certificates curl ffmpeg; then \
            install_succeeded=1; \
            break; \
        fi; \
        if [ "${attempt}" -lt 3 ]; then \
            echo "依赖下载失败，准备进行第 $((attempt + 1)) 次尝试"; \
            sleep $((attempt * 2)); \
        fi; \
    done \
    && test "${install_succeeded}" = "1" \
    && groupadd --system --gid 10001 bobo \
    && useradd --system --uid 10001 --gid bobo --home-dir /nonexistent --shell /usr/sbin/nologin bobo \
    && mkdir --parents /app/cover-cache /app/media /app/web \
    && chown --recursive bobo:bobo /app

COPY --from=rust-builder --chown=bobo:bobo \
    /workspace/Service/target/release/bobo_learning_service /app/bobo-learning-service
COPY --from=flutter-builder --chown=bobo:bobo /workspace/Client/build/web /app/web
COPY --from=flutter-builder --chown=bobo:bobo \
    /workspace/Client/build/web/icons/Icon-512.png /app/default-cover.png

ENV BOBO_BIND=0.0.0.0:8080 \
    BOBO_MEDIA_DIR=/app/media \
    BOBO_WEB_DIR=/app/web \
    BOBO_COVER_CACHE_DIR=/app/cover-cache \
    BOBO_DEFAULT_COVER_PATH=/app/default-cover.png \
    BOBO_FFMPEG_BIN=ffmpeg \
    BOBO_COVER_CAPTURE_SECS=3 \
    BOBO_SCAN_DEBOUNCE_MS=1500 \
    BOBO_SCAN_INTERVAL_SECS=10 \
    RUST_LOG=bobo_learning_service=info

USER 10001:10001
EXPOSE 8080

ENTRYPOINT ["/app/bobo-learning-service"]
