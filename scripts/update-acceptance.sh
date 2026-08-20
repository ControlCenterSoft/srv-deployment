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
downgrade_version="1.0.0-beta.1"
downgrade_commit="cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc"

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

# 3. Unverified candidate bytes must be rejected before candidate execution.
mkdir "$work/artifact-tamper"
tar -xzf "$work/target.tar.gz" -C "$work/artifact-tamper"
cat > "$work/artifact-tamper/control-center" <<EOF
#!/bin/sh
touch "$work/unverified-candidate-executed"
exit 0
EOF
chmod 0755 "$work/artifact-tamper/control-center"
tar -C "$work/artifact-tamper" -czf "$work/artifact-tamper.tar.gz" manifest.json manifest.sig control-center
if "$UPDATER" --package "$work/artifact-tamper.tar.gz" >"$work/artifact-tamper.out" 2>"$work/artifact-tamper.err"; then
  fail "artifact-tampered package was accepted"
fi
[[ ! -e "$work/unverified-candidate-executed" ]] || fail "unverified candidate code executed before digest verification"
[[ "$(readlink "$CURRENT_LINK")" == "$after_success" ]] || fail "artifact rejection changed current link"
wait_version "$target_version" || fail "service unhealthy after artifact rejection"

# 4. Packages with unexpected entries must be rejected before extraction/activation.
mkdir "$work/extra-entry"
tar -xzf "$work/target.tar.gz" -C "$work/extra-entry"
printf 'unexpected\n' > "$work/extra-entry/unexpected.txt"
tar -C "$work/extra-entry" -czf "$work/extra-entry.tar.gz" manifest.json manifest.sig control-center unexpected.txt
if "$UPDATER" --package "$work/extra-entry.tar.gz" >"$work/extra-entry.out" 2>"$work/extra-entry.err"; then
  fail "package with unexpected entry was accepted"
fi
grep -Fq 'unexpected entries' "$work/extra-entry.err" || fail "unexpected-entry rejection reason was not recorded"
[[ "$(readlink "$CURRENT_LINK")" == "$after_success" ]] || fail "unexpected-entry rejection changed current link"

# 5. Correctly signed package for the wrong architecture must fail closed.
wrong_arch=arm64
[[ "$goarch" == arm64 ]] && wrong_arch=amd64
(
  cd "$ROOT"
  go run ./cmd/release-tool package \
    --binary "$work/target" --version "$target_version" --commit "$target_commit" --arch "$wrong_arch" \
    --private-key "$PRIVATE_KEY" --output "$work/wrong-arch.tar.gz" --built-at 2026-08-20T00:00:00Z >/dev/null
)
if "$UPDATER" --package "$work/wrong-arch.tar.gz" >"$work/wrong-arch.out" 2>"$work/wrong-arch.err"; then
  fail "wrong-architecture package was accepted"
fi
[[ "$(readlink "$CURRENT_LINK")" == "$after_success" ]] || fail "platform rejection changed current link"
wait_version "$target_version" || fail "service unhealthy after platform rejection"

# 6. A correctly signed downgrade must be rejected by policy.
build_runtime "$work/downgrade" "$downgrade_version" "$downgrade_commit"
package_runtime "$work/downgrade" "$downgrade_version" "$downgrade_commit" "$work/downgrade.tar.gz"
if "$UPDATER" --package "$work/downgrade.tar.gz" >"$work/downgrade.out" 2>"$work/downgrade.err"; then
  fail "downgrade was accepted without --allow-downgrade"
fi
grep -Fq 'not newer than current' "$work/downgrade.err" || fail "downgrade rejection reason was not recorded"
[[ "$(readlink "$CURRENT_LINK")" == "$after_success" ]] || fail "downgrade rejection changed current link"
wait_version "$target_version" || fail "service unhealthy after downgrade rejection"

# 7. Tampered manifest must fail signature verification before switch.
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

# 8. A correctly signed but non-starting runtime must roll back automatically.
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

printf 'Safe update acceptance passed: signed update, same-version rejection, artifact rejection without execution, package whitelist rejection, platform rejection, downgrade rejection, signature rejection, automatic rollback.\n'
