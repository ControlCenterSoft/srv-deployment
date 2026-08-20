#!/usr/bin/env bash
set -Eeuo pipefail

BASE_URL="${CONTROL_CENTER_ACCEPTANCE_URL:-http://127.0.0.1:8876}"
PRIVATE_KEY="${CONTROL_CENTER_UPDATE_PRIVATE_KEY:-/tmp/control-center-update-private.pem}"
UPDATER="${CONTROL_CENTER_UPDATER:-/usr/local/sbin/control-center-update}"
CURRENT_LINK="/usr/local/lib/control-center/current"
PREVIOUS_LINK="/usr/local/lib/control-center/previous"
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"

fail() { printf 'UPDATE ACCEPTANCE FAILED: %s\n' "$*" >&2; exit 1; }
[[ $EUID -eq 0 ]] || fail "must run as root"
[[ -x "$UPDATER" ]] || fail "updater is not installed: $UPDATER"
[[ -f "$PRIVATE_KEY" ]] || fail "private signing key is missing: $PRIVATE_KEY"
[[ -L "$CURRENT_LINK" ]] || fail "current release link is missing"
command -v go >/dev/null || fail "go is required for acceptance build"
command -v tar >/dev/null || fail "tar is required"
command -v curl >/dev/null || fail "curl is required"

work="$(mktemp -d /tmp/control-center-update-acceptance.XXXXXX)"
trap 'rm -rf -- "$work"' EXIT

arch="$(uname -m)"
case "$arch" in
  x86_64) goarch=amd64 ;;
  aarch64|arm64) goarch=arm64 ;;
  *) fail "unsupported architecture: $arch" ;;
esac

target_version="1.0.0-beta.2"
target_commit="aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
broken_version="1.0.0-beta.3"
broken_commit="bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"

build_runtime() {
  local output="$1" version="$2" commit="$3"
  (
    cd "$ROOT"
    CGO_ENABLED=0 GOOS=linux GOARCH="$goarch" go build -trimpath \
      -ldflags "-s -w -X github.com/ControlCenterSoft/srv-deployment/internal/buildinfo.Version=$version -X github.com/ControlCenterSoft/srv-deployment/internal/buildinfo.Commit=$commit -X github.com/ControlCenterSoft/srv-deployment/internal/buildinfo.BuiltAt=2026-08-20T00:00:00Z" \
      -o "$output" ./cmd/control-center
  )
}

package_runtime() {
  local binary="$1" version="$2" commit="$3" output="$4"
  (
    cd "$ROOT"
    go run ./cmd/release-tool package \
      --binary "$binary" --version "$version" --commit "$commit" --arch "$goarch" \
      --private-key "$PRIVATE_KEY" --output "$output" --built-at 2026-08-20T00:00:00Z >/dev/null
  )
}

wait_version() {
  local expected="$1"
  for _ in {1..30}; do
    if body="$(curl -fsS --max-time 2 "$BASE_URL/api/v1/version" 2>/dev/null)" && grep -Fq "\"version\":\"$expected\"" <<<"$body"; then
      return 0
    fi
    sleep 0.25
  done
  return 1
}

initial_target="$(readlink "$CURRENT_LINK")"
[[ -n "$initial_target" ]] || fail "initial current target is empty"

# 1. Successful signed update.
build_runtime "$work/target" "$target_version" "$target_commit"
package_runtime "$work/target" "$target_version" "$target_commit" "$work/target.tar.gz"
"$UPDATER" --package "$work/target.tar.gz"
wait_version "$target_version" || fail "successful update did not become healthy at $target_version"
after_success="$(readlink "$CURRENT_LINK")"
[[ "$after_success" != "$initial_target" ]] || fail "current link did not change after successful update"
[[ -L "$PREVIOUS_LINK" && "$(readlink "$PREVIOUS_LINK")" == "$initial_target" ]] || fail "previous link was not set to the original release"

# 2. Same-version package must be rejected without changing current.
if "$UPDATER" --package "$work/target.tar.gz" >"$work/same.out" 2>"$work/same.err"; then
  fail "same-version update was accepted"
fi
[[ "$(readlink "$CURRENT_LINK")" == "$after_success" ]] || fail "same-version rejection changed current link"
wait_version "$target_version" || fail "service unhealthy after same-version rejection"

# 3. Tampered manifest must fail signature verification before switch.
mkdir "$work/tampered"
tar -xzf "$work/target.tar.gz" -C "$work/tampered"
python3 - "$work/tampered/manifest.json" <<'PY'
import json,sys
p=sys.argv[1]
d=json.load(open(p))
d["channel"]="stable" if d["channel"]=="beta" else "beta"
open(p,"w").write(json.dumps(d,indent=2)+"\n")
PY
tar -C "$work/tampered" -czf "$work/tampered.tar.gz" manifest.json manifest.sig control-center
if "$UPDATER" --package "$work/tampered.tar.gz" >"$work/tampered.out" 2>"$work/tampered.err"; then
  fail "tampered manifest was accepted"
fi
[[ "$(readlink "$CURRENT_LINK")" == "$after_success" ]] || fail "signature rejection changed current link"
wait_version "$target_version" || fail "service unhealthy after signature rejection"

# 4. A correctly signed but non-starting runtime must roll back automatically.
cat > "$work/broken.go" <<'GO'
package main
import (
  "flag"
  "fmt"
  "os"
)
var version = "1.0.0-beta.3"
var commit = "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
func main() {
  if len(os.Args) > 1 && os.Args[1] == "build-info" {
    fs := flag.NewFlagSet("build-info", flag.ExitOnError)
    field := fs.String("field", "", "")
    _ = fs.Parse(os.Args[2:])
    switch *field { case "version": fmt.Println(version); case "commit": fmt.Println(commit); case "built-at": fmt.Println("2026-08-20T00:00:00Z"); default: fmt.Printf("{\"version\":%q,\"commit\":%q}\n",version,commit) }
    return
  }
  os.Exit(42)
}
GO
CGO_ENABLED=0 GOOS=linux GOARCH="$goarch" go build -trimpath -o "$work/broken" "$work/broken.go"
package_runtime "$work/broken" "$broken_version" "$broken_commit" "$work/broken.tar.gz"
if "$UPDATER" --package "$work/broken.tar.gz" >"$work/broken.out" 2>"$work/broken.err"; then
  fail "broken signed runtime unexpectedly passed post-update acceptance"
fi
[[ "$(readlink "$CURRENT_LINK")" == "$after_success" ]] || fail "failed update did not roll back current link"
wait_version "$target_version" || fail "rolled-back service did not recover"

grep -Fq 'rolling back' "$work/broken.out" || fail "rollback was not recorded in updater output"

printf 'Safe update acceptance passed: signed update, same-version rejection, signature rejection, automatic rollback.\n'
