#!/usr/bin/env bash
set -Eeuo pipefail
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
VERSION="${VERSION:-1.0.0-alpha.3+dev}"
COMMIT="${COMMIT:-$(git rev-parse --short=12 HEAD 2>/dev/null || printf unknown)}"
BUILT_AT="${BUILT_AT:-$(date -u +%Y-%m-%dT%H:%M:%SZ)}"
mkdir -p dist
for target in linux/amd64 linux/arm64; do
  os="${target%/*}"; arch="${target#*/}"
  echo "building $os/$arch"
  CGO_ENABLED=0 GOOS="$os" GOARCH="$arch" go build -trimpath \
    -ldflags "-s -w -X github.com/ControlCenterSoft/srv-deployment/internal/buildinfo.Version=$VERSION -X github.com/ControlCenterSoft/srv-deployment/internal/buildinfo.Commit=$COMMIT -X github.com/ControlCenterSoft/srv-deployment/internal/buildinfo.BuiltAt=$BUILT_AT" \
    -o "dist/control-center-$os-$arch" ./cmd/control-center
 done
sha256sum dist/control-center-linux-* > dist/SHA256SUMS
