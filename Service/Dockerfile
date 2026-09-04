# syntax=docker/dockerfile:1.7

FROM rust:1.98.0-bookworm AS builder
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
    && mkdir --parents /app/cover-cache /app/hls-cache /app/media /app/updates \
    && chown --recursive bobo:bobo /app

COPY --from=builder --chown=bobo:bobo \
    /workspace/Service/target/release/bobo_learning_service /app/bobo-learning-service
COPY --chown=bobo:bobo Service/assets/default-cover.png /app/default-cover.png

ENV BOBO_BIND=0.0.0.0:8080 \
    BOBO_MEDIA_DIR=/app/media \
    BOBO_COVER_CACHE_DIR=/app/cover-cache \
    BOBO_HLS_CACHE_DIR=/app/hls-cache \
    BOBO_UPDATE_DIR=/app/updates \
    BOBO_DEFAULT_COVER_PATH=/app/default-cover.png \
    BOBO_FFMPEG_BIN=ffmpeg \
    BOBO_COVER_CAPTURE_SECS=3 \
    BOBO_HLS_PREWARM_LIMIT=4 \
    BOBO_SCAN_DEBOUNCE_MS=1500 \
    BOBO_SCAN_INTERVAL_SECS=10 \
    RUST_LOG=bobo_learning_service=info

USER 10001:10001
EXPOSE 8080

ENTRYPOINT ["/app/bobo-learning-service"]
