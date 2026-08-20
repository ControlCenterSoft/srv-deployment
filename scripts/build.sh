#!/usr/bin/env bash
set -Eeuo pipefail
umask 022
export LC_ALL=C
export TZ=UTC

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

VERSION="${VERSION:-1.0.0-rc.1+dev}"
COMMIT="${COMMIT:-$(git rev-parse HEAD 2>/dev/null || printf unknown)}"
BUILT_AT="${BUILT_AT:-$(date -u +%Y-%m-%dT%H:%M:%SZ)}"
EXPECTED_GO_VERSION="${EXPECTED_GO_VERSION:-}"

if [[ -n "$EXPECTED_GO_VERSION" ]]; then
  actual_go="$(GOTOOLCHAIN=local go env GOVERSION)"
  [[ "$actual_go" == "go$EXPECTED_GO_VERSION" ]] || {
    printf 'ERROR: expected Go %s, got %s\n' "$EXPECTED_GO_VERSION" "$actual_go" >&2
    exit 1
  }
fi

mkdir -p dist
rm -f dist/control-center-linux-amd64 dist/control-center-linux-arm64 dist/SHA256SUMS
for target in linux/amd64 linux/arm64; do
  os="${target%/*}"
  arch="${target#*/}"
  echo "building $os/$arch"
  GOTOOLCHAIN=local CGO_ENABLED=0 GOOS="$os" GOARCH="$arch" go build \
    -trimpath -buildvcs=false \
    -ldflags "-s -w -X github.com/ControlCenterSoft/srv-deployment/internal/buildinfo.Version=$VERSION -X github.com/ControlCenterSoft/srv-deployment/internal/buildinfo.Commit=$COMMIT -X github.com/ControlCenterSoft/srv-deployment/internal/buildinfo.BuiltAt=$BUILT_AT" \
    -o "dist/control-center-$os-$arch" ./cmd/control-center
done
sha256sum dist/control-center-linux-amd64 dist/control-center-linux-arm64 > dist/SHA256SUMS
