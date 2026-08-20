#!/usr/bin/env bash
set -Eeuo pipefail
umask 022
export LC_ALL=C
export TZ=UTC
export GOTOOLCHAIN=local

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
META="$ROOT/release/1.0.0-rc.1.env"
[[ -f "$META" ]] || { echo "ERROR: release metadata missing: $META" >&2; exit 1; }
# shellcheck disable=SC1090
source "$META"

[[ -n ${RELEASE_VERSION:-} && -n ${RELEASE_GO_VERSION:-} ]] || {
  echo "ERROR: incomplete release metadata" >&2
  exit 1
}
command -v git >/dev/null || { echo "ERROR: git is required for exact release build" >&2; exit 1; }
command -v go >/dev/null || { echo "ERROR: go is required for exact release build" >&2; exit 1; }

git rev-parse --is-inside-work-tree >/dev/null 2>&1 || { echo "ERROR: exact release build requires a Git checkout" >&2; exit 1; }
[[ -z "$(git status --porcelain --untracked-files=normal -- . ':(exclude)dist')" ]] || {
  echo "ERROR: source tree is not clean" >&2
  git status --short -- . ':(exclude)dist' >&2 || true
  exit 1
}

COMMIT="$(git rev-parse HEAD)"
BUILT_AT="$(git show -s --format=%cI "$COMMIT")"
actual_go="$(go env GOVERSION)"
[[ "$actual_go" == "go$RELEASE_GO_VERSION" ]] || {
  printf 'ERROR: rc.1 requires Go %s, got %s\n' "$RELEASE_GO_VERSION" "$actual_go" >&2
  exit 1
}

VERSION="$RELEASE_VERSION" \
COMMIT="$COMMIT" \
BUILT_AT="$BUILT_AT" \
EXPECTED_GO_VERSION="$RELEASE_GO_VERSION" \
  "$ROOT/scripts/build.sh"

cat > "$ROOT/dist/BUILDINFO.env" <<EOF
VERSION=$RELEASE_VERSION
COMMIT=$COMMIT
BUILT_AT=$BUILT_AT
GO_VERSION=$RELEASE_GO_VERSION
AMD64_SHA256=$(sha256sum "$ROOT/dist/control-center-linux-amd64" | awk '{print $1}')
ARM64_SHA256=$(sha256sum "$ROOT/dist/control-center-linux-arm64" | awk '{print $1}')
EOF
chmod 0644 "$ROOT/dist/BUILDINFO.env"

"$ROOT/dist/control-center-linux-amd64" build-info
printf 'Exact release build completed from %s with %s.\n' "$COMMIT" "$actual_go"
