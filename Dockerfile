# 统一网关 + 网页版 App 的镜像。在仓库根目录构建：docker build -t smarthome-gateway .

# 1. 构建网页版 App
FROM ghcr.io/cirruslabs/flutter:3.44.0 AS web
WORKDIR /src/mobile
COPY mobile/pubspec.yaml mobile/pubspec.lock ./
RUN flutter pub get
COPY mobile/ ./
RUN flutter build web --release

# 2. 网关
FROM python:3.12-slim
WORKDIR /app
COPY backend/pyproject.toml ./
COPY backend/gateway ./gateway
RUN pip install --no-cache-dir .
COPY --from=web /src/mobile/build/web /app/web
ENV GATEWAY_WEB_DIR=/app/web \
    GATEWAY_DATA_DIR=/data
VOLUME /data
EXPOSE 8000
CMD ["uvicorn", "gateway.main:app", "--factory", "--host", "0.0.0.0", "--port", "8000"]
