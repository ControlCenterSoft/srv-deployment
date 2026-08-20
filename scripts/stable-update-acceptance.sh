#!/usr/bin/env bash
set -Eeuo pipefail

BASE_URL="${CONTROL_CENTER_ACCEPTANCE_URL:-http://127.0.0.1:8876}"
PRIVATE_KEY="${CONTROL_CENTER_UPDATE_PRIVATE_KEY:-/tmp/control-center-update-private.pem}"
UPDATER="${CONTROL_CENTER_UPDATER:-/usr/local/sbin/control-center-update}"
CURRENT_LINK="/usr/local/lib/control-center/current"
PREVIOUS_LINK="/usr/local/lib/control-center/previous"
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"

fail() { printf 'STABLE UPDATE ACCEPTANCE FAILED: %s\n' "$*" >&2; exit 1; }
[[ $EUID -eq 0 ]] || fail "must run as root"
[[ -x "$UPDATER" ]] || fail "updater is not installed: $UPDATER"
[[ -f "$PRIVATE_KEY" ]] || fail "private signing key is missing: $PRIVATE_KEY"
[[ -L "$CURRENT_LINK" ]] || fail "current release link is missing"
for cmd in go tar curl systemctl python3; do command -v "$cmd" >/dev/null || fail "$cmd is required"; done

work="$(mktemp -d /tmp/control-center-stable-update-acceptance.XXXXXX)"
trap 'rm -rf -- "$work"' EXIT

# Keep acceptance builds hermetic and functional in non-interactive/systemd
# environments where HOME/XDG_CACHE_HOME/GOCACHE may be unset.
export HOME="$work/home"
export GOPATH="$work/go-path"
export GOCACHE="$work/go-cache"
export GOMODCACHE="$work/go-mod-cache"
export GOTOOLCHAIN=local
mkdir -p "$HOME" "$GOPATH" "$GOCACHE" "$GOMODCACHE"
chmod 0700 "$HOME" "$GOPATH" "$GOCACHE" "$GOMODCACHE"

case "$(uname -m)" in
  x86_64) goarch=amd64 ;;
  aarch64|arm64) goarch=arm64 ;;
  *) fail "unsupported architecture" ;;
esac

target_version="1.0.1"
target_commit="aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
broken_version="1.0.2"
broken_commit="bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
downgrade_version="1.0.0-rc.1"
downgrade_commit="cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc"

build_runtime() {
  local output="$1" version="$2" commit="$3"
  (cd "$ROOT" && CGO_ENABLED=0 GOOS=linux GOARCH="$goarch" go build -trimpath \
    -ldflags "-s -w -X github.com/ControlCenterSoft/srv-deployment/internal/buildinfo.Version=$version -X github.com/ControlCenterSoft/srv-deployment/internal/buildinfo.Commit=$commit -X github.com/ControlCenterSoft/srv-deployment/internal/buildinfo.BuiltAt=2026-08-20T00:00:00Z" \
    -o "$output" ./cmd/control-center)
}

package_runtime() {
  local binary="$1" version="$2" commit="$3" output="$4" arch="${5:-$goarch}"
  (cd "$ROOT" && go run ./cmd/release-tool package \
    --binary "$binary" --version "$version" --commit "$commit" --arch "$arch" \
    --private-key "$PRIVATE_KEY" --output "$output" --built-at 2026-08-20T00:00:00Z >/dev/null)
}

wait_version() {
  local expected="$1" body
  for _ in {1..40}; do
    if body="$(curl -fsS --max-time 2 "$BASE_URL/api/v1/version" 2>/dev/null)" && grep -Fq "\"version\":\"$expected\"" <<<"$body"; then return 0; fi
    sleep 0.25
  done
  return 1
}

initial_target="$(readlink "$CURRENT_LINK")"
[[ -n "$initial_target" ]] || fail "initial current target is empty"

# Forward signed update to 1.0.1.
build_runtime "$work/target" "$target_version" "$target_commit"
package_runtime "$work/target" "$target_version" "$target_commit" "$work/target.tar.gz"
"$UPDATER" --package "$work/target.tar.gz"
wait_version "$target_version" || fail "forward update did not become healthy"
after_success="$(readlink "$CURRENT_LINK")"
[[ "$after_success" != "$initial_target" ]] || fail "current link did not switch"
[[ -L "$PREVIOUS_LINK" && "$(readlink "$PREVIOUS_LINK")" == "$initial_target" ]] || fail "previous link not preserved"

# Same version rejection.
if "$UPDATER" --package "$work/target.tar.gz" >"$work/same.out" 2>"$work/same.err"; then fail "same version accepted"; fi
[[ "$(readlink "$CURRENT_LINK")" == "$after_success" ]] || fail "same-version rejection changed current"

# Candidate-byte tamper rejection before execution.
mkdir "$work/artifact-tamper"
tar -xzf "$work/target.tar.gz" -C "$work/artifact-tamper"
printf '#!/bin/sh\ntouch %q\nexit 0\n' "$work/unverified-executed" > "$work/artifact-tamper/control-center"
chmod 0755 "$work/artifact-tamper/control-center"
tar -C "$work/artifact-tamper" -czf "$work/artifact-tamper.tar.gz" manifest.json manifest.sig control-center
if "$UPDATER" --package "$work/artifact-tamper.tar.gz" >/dev/null 2>&1; then fail "artifact tamper accepted"; fi
[[ ! -e "$work/unverified-executed" ]] || fail "unverified candidate executed"

# Strict package whitelist.
mkdir "$work/extra"
tar -xzf "$work/target.tar.gz" -C "$work/extra"
printf 'unexpected\n' > "$work/extra/unexpected.txt"
tar -C "$work/extra" -czf "$work/extra.tar.gz" manifest.json manifest.sig control-center unexpected.txt
if "$UPDATER" --package "$work/extra.tar.gz" >"$work/extra.out" 2>"$work/extra.err"; then fail "extra entry accepted"; fi
grep -Fq 'unexpected entries' "$work/extra.err" || fail "extra-entry reason missing"

# Wrong architecture rejection.
wrong_arch=arm64; [[ "$goarch" == arm64 ]] && wrong_arch=amd64
package_runtime "$work/target" "$target_version" "$target_commit" "$work/wrong-arch.tar.gz" "$wrong_arch"
if "$UPDATER" --package "$work/wrong-arch.tar.gz" >/dev/null 2>&1; then fail "wrong architecture accepted"; fi

# Signed rc.1 downgrade rejection from stable.
build_runtime "$work/downgrade" "$downgrade_version" "$downgrade_commit"
package_runtime "$work/downgrade" "$downgrade_version" "$downgrade_commit" "$work/downgrade.tar.gz"
if "$UPDATER" --package "$work/downgrade.tar.gz" >"$work/down.out" 2>"$work/down.err"; then fail "downgrade accepted"; fi
grep -Fq 'not newer than current' "$work/down.err" || fail "downgrade reason missing"

# Signed metadata tamper rejection.
mkdir "$work/tampered"
tar -xzf "$work/target.tar.gz" -C "$work/tampered"
python3 - "$work/tampered/manifest.json" <<'PY'
import json,sys
p=sys.argv[1]
d=json.load(open(p))
d["channel"]="rc" if d.get("channel") != "rc" else "stable"
open(p,"w").write(json.dumps(d,indent=2)+"\n")
PY
tar -C "$work/tampered" -czf "$work/tampered.tar.gz" manifest.json manifest.sig control-center
if "$UPDATER" --package "$work/tampered.tar.gz" >/dev/null 2>&1; then fail "tampered manifest accepted"; fi

# Correctly signed non-starting 1.0.2 must roll back.
cat > "$work/broken.go" <<'GO'
package main
import("flag";"fmt";"os")
var version="1.0.2"
var commit="bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
func main(){
 if len(os.Args)>1 && os.Args[1]=="build-info"{
  fs:=flag.NewFlagSet("build-info",flag.ExitOnError); field:=fs.String("field","",""); _=fs.Parse(os.Args[2:])
  switch *field{case "version":fmt.Println(version);case "commit":fmt.Println(commit);case "built-at":fmt.Println("2026-08-20T00:00:00Z");default:fmt.Printf("{\"version\":%q,\"commit\":%q}\n",version,commit)}; return
 }
 os.Exit(42)
}
GO
CGO_ENABLED=0 GOOS=linux GOARCH="$goarch" go build -trimpath -o "$work/broken" "$work/broken.go"
package_runtime "$work/broken" "$broken_version" "$broken_commit" "$work/broken.tar.gz"
if "$UPDATER" --package "$work/broken.tar.gz" >"$work/broken.out" 2>"$work/broken.err"; then fail "broken runtime passed acceptance"; fi
[[ "$(readlink "$CURRENT_LINK")" == "$after_success" ]] || fail "broken candidate did not roll back"
wait_version "$target_version" || fail "rolled-back runtime unhealthy"
grep -Fq 'rolling back' "$work/broken.out" || fail "rollback not recorded"

# Known-good must restart immediately after rollback without start-limit-hit.
systemctl restart control-center.service || fail "known-good restart blocked after rollback"
wait_version "$target_version" || fail "known-good runtime not ready after restart"
if systemctl is-failed --quiet control-center.service; then fail "service remains failed after rollback recovery"; fi

printf 'Stable update acceptance passed: signed forward update, fail-closed negative verification, automatic rollback, immediate post-rollback restart.\n'
