#!/usr/bin/env bash
# Build server-watch: frontend (vite) -> embed -> Go binaries.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

echo "==> frontend build"
(cd frontend && npm run build)

echo "==> embed dist"
rm -rf backend/internal/webdist/dist
mkdir -p backend/internal/webdist/dist
cp -R frontend/dist/. backend/internal/webdist/dist/

cd backend
export GOSUMDB=off
export GOPROXY="${GOPROXY:-https://goproxy.cn,direct}"

echo "==> build linux/arm64"
CGO_ENABLED=0 GOOS=linux GOARCH=arm64 go build -trimpath -ldflags "-s -w" \
  -o "$ROOT/dist/server-watch-agent-linux-arm64" ./cmd/monitor-agent

echo "==> build host ($(go env GOOS)/$(go env GOARCH))"
CGO_ENABLED=0 go build -trimpath -ldflags "-s -w" \
  -o "$ROOT/dist/server-watch-agent-$(go env GOOS)-$(go env GOARCH)" ./cmd/monitor-agent

ls -la "$ROOT/dist/"
