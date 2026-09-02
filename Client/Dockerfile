# syntax=docker/dockerfile:1.7

FROM debian:bookworm-slim AS builder

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
COPY Client/assets ./assets
COPY Client/analysis_options.yaml Client/.metadata ./
RUN flutter build web --release --base-href=/

FROM nginx:1.28-alpine AS runtime

COPY Client/nginx.conf /etc/nginx/nginx.conf
COPY --from=builder /workspace/Client/build/web /usr/share/nginx/html

USER nginx
EXPOSE 8080

ENTRYPOINT ["nginx", "-g", "daemon off;"]
