#!/usr/bin/env bash
set -Eeuo pipefail

BASE_URL="${CONTROL_CENTER_ACCEPTANCE_URL:-http://127.0.0.1:8876}"
PRIVATE_KEY="${CONTROL_CENTER_UPDATE_PRIVATE_KEY:-/tmp/control-center-update-private.pem}"
UPDATER="${CONTROL_CENTER_UPDATER:-/usr/local/sbin/control-center-update}"
CURRENT_LINK="/usr/local/lib/control-center/current"
PREVIOUS_LINK="/usr/local/lib/control-center/previous"
WORKER_SERVICE="control-center-privileged-worker.service"
WORKER_SOCKET="/run/control-center/privileged-worker.sock"
ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
V2_ENTRIES=$'bootstrap-manifest.json\nbootstrap-manifest.sig\nmanifest.json\nmanifest.sig\ncontrol-center\ncontrol-center-privileged-worker'

fail() { printf 'UPDATE V2 ACCEPTANCE FAILED: %s\n' "$*" >&2; exit 1; }
[[ $EUID -eq 0 ]] || fail "must run as root"
[[ -x "$UPDATER" ]] || fail "updater is not installed: $UPDATER"
[[ -f "$PRIVATE_KEY" ]] || fail "private signing key is missing: $PRIVATE_KEY"
[[ -L "$CURRENT_LINK" ]] || fail "current release link is missing"
command -v go >/dev/null || fail "go is required for acceptance build"
command -v tar >/dev/null || fail "tar is required"
command -v curl >/dev/null || fail "curl is required"
command -v stat >/dev/null || fail "stat is required"
systemctl cat "$WORKER_SERVICE" >/dev/null 2>&1 || fail "privileged worker unit is not installed"

work="$(mktemp -d /tmp/control-center-update-v2-acceptance.XXXXXX)"
trap 'rm -rf -- "$work"' EXIT

arch="$(uname -m)"
case "$arch" in
  x86_64) goarch=amd64 ;;
  aarch64|arm64) goarch=arm64 ;;
  *) fail "unsupported architecture: $arch" ;;
esac

target_version="${CONTROL_CENTER_UPDATE_TEST_TARGET_VERSION:-1.1.1-beta.1}"
target_commit="aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
same_version_drift_commit="dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd"
broken_version="${CONTROL_CENTER_UPDATE_TEST_BROKEN_VERSION:-1.1.1-beta.2}"
broken_commit="bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
downgrade_version="${CONTROL_CENTER_UPDATE_TEST_DOWNGRADE_VERSION:-1.1.0-rc.1}"
downgrade_commit="cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc"

build_main() {
  local output="$1" version="$2" commit="$3"
  (
    cd "$ROOT"
    CGO_ENABLED=0 GOOS=linux GOARCH="$goarch" go build -trimpath -buildvcs=false \
      -ldflags "-s -w -X github.com/ControlCenterSoft/srv-deployment/internal/buildinfo.Version=$version -X github.com/ControlCenterSoft/srv-deployment/internal/buildinfo.Commit=$commit -X github.com/ControlCenterSoft/srv-deployment/internal/buildinfo.BuiltAt=2026-08-20T00:00:00Z" \
      -o "$output" ./cmd/control-center
  )
}

build_worker() {
  local output="$1"
  (
    cd "$ROOT"
    CGO_ENABLED=0 GOOS=linux GOARCH="$goarch" go build -trimpath -buildvcs=false -ldflags "-s -w" \
      -o "$output" ./cmd/control-center-privileged-worker
  )
}

package_v2() {
  local binary="$1" worker="$2" version="$3" commit="$4" output="$5" package_arch="${6:-$goarch}"
  (
    cd "$ROOT"
    go run ./cmd/release-tool package-v2 \
      --binary "$binary" \
      --worker "$worker" \
      --version "$version" \
      --channel beta \
      --commit "$commit" \
      --arch "$package_arch" \
      --private-key "$PRIVATE_KEY" \
      --output "$output" \
      --built-at 2026-08-20T00:00:00Z >/dev/null
  )
  [[ "$(tar -tzf "$output")" == "$V2_ENTRIES" ]] || fail "package-v2 entry contract changed"
}

repack_v2() {
  local directory="$1" output="$2"
  tar -C "$directory" -czf "$output" \
    bootstrap-manifest.json \
    bootstrap-manifest.sig \
    manifest.json \
    manifest.sig \
    control-center \
    control-center-privileged-worker
}

wait_version() {
  local expected="$1"
  for _ in {1..40}; do
    if body="$(curl -fsS --max-time 2 "$BASE_URL/api/v1/version" 2>/dev/null)" && \
       grep -Fq "\"version\":\"$expected\"" <<<"$body"; then
      return 0
    fi
    sleep 0.25
  done
  return 1
}

assert_worker_ready() {
  systemctl is-active --quiet "$WORKER_SERVICE" || fail "privileged worker is not active"
  systemctl is-enabled --quiet "$WORKER_SERVICE" || fail "privileged worker is not enabled"
  [[ -S "$WORKER_SOCKET" ]] || fail "privileged worker socket is missing"
  [[ "$(stat -Lc '%U:%G:%a' "$WORKER_SOCKET")" == "root:control-center:660" ]] \
    || fail "privileged worker socket boundary is invalid"
}

assert_runtime() {
  local expected="$1"
  curl -fsS --max-time 2 "$BASE_URL/api/v1/health" >/dev/null \
    || fail "health failed at $expected"
  curl -fsS --max-time 2 "$BASE_URL/api/v1/readiness" | grep -Fq '"ready":true' \
    || fail "readiness failed at $expected"
  wait_version "$expected" || fail "runtime did not report $expected"
  assert_worker_ready
}

initial_target="$(readlink "$CURRENT_LINK")"
[[ -n "$initial_target" ]] || fail "initial current target is empty"
initial_version="$("$CURRENT_LINK/control-center" build-info --field version)"
assert_runtime "$initial_version"

# Build one known-good worker for signed package-v2 cases.
build_worker "$work/worker-good"

# 1. Successful signed dual-runtime update.
build_main "$work/target" "$target_version" "$target_commit"
package_v2 "$work/target" "$work/worker-good" "$target_version" "$target_commit" "$work/target.tar.gz"
"$UPDATER" --package "$work/target.tar.gz"
assert_runtime "$target_version"
after_success="$(readlink "$CURRENT_LINK")"
[[ "$after_success" != "$initial_target" ]] || fail "current link did not change after successful update"
[[ -L "$PREVIOUS_LINK" && "$(readlink "$PREVIOUS_LINK")" == "$initial_target" ]] \
  || fail "previous link was not set to the original release"

# 2. Replaying the exact same signed runtime must be an idempotent no-op.
"$UPDATER" --package "$work/target.tar.gz" >"$work/same.out" 2>"$work/same.err" \
  || fail "exact same-version replay was rejected"
grep -Fq 'already active with exact signed identity; no update required' "$work/same.out" \
  || fail "exact replay no-op was not recorded"
[[ "$(readlink "$CURRENT_LINK")" == "$after_success" ]] || fail "exact replay changed current link"
[[ "$(readlink "$PREVIOUS_LINK")" == "$initial_target" ]] || fail "exact replay changed previous link"
assert_runtime "$target_version"

# 3. Reusing the same version with a different signed commit identity must fail closed.
build_main "$work/same-version-drift" "$target_version" "$same_version_drift_commit"
package_v2 "$work/same-version-drift" "$work/worker-good" "$target_version" "$same_version_drift_commit" "$work/same-version-drift.tar.gz"
if "$UPDATER" --package "$work/same-version-drift.tar.gz" >"$work/same-version-drift.out" 2>"$work/same-version-drift.err"; then
  fail "same-version identity drift was accepted"
fi
grep -Fq 'reuses the current version with a different commit identity' "$work/same-version-drift.err" \
  || fail "same-version identity drift rejection reason was not recorded"
[[ "$(readlink "$CURRENT_LINK")" == "$after_success" ]] || fail "same-version drift rejection changed current link"
assert_runtime "$target_version"

# 4. Unverified main bytes must be rejected by the trusted schema-1 bridge
# before candidate code is ever executed.
mkdir "$work/artifact-tamper"
tar -xzf "$work/target.tar.gz" -C "$work/artifact-tamper"
cat > "$work/artifact-tamper/control-center" <<EOF
#!/bin/sh
touch "$work/unverified-candidate-executed"
exit 0
EOF
chmod 0755 "$work/artifact-tamper/control-center"
repack_v2 "$work/artifact-tamper" "$work/artifact-tamper.tar.gz"
if "$UPDATER" --package "$work/artifact-tamper.tar.gz" >"$work/artifact-tamper.out" 2>"$work/artifact-tamper.err"; then
  fail "artifact-tampered package was accepted"
fi
[[ ! -e "$work/unverified-candidate-executed" ]] || fail "unverified candidate code executed before digest verification"
[[ "$(readlink "$CURRENT_LINK")" == "$after_success" ]] || fail "artifact rejection changed current link"
assert_runtime "$target_version"

# 5. A seventh/unexpected package entry must fail before extraction/activation.
mkdir "$work/extra-entry"
tar -xzf "$work/target.tar.gz" -C "$work/extra-entry"
printf 'unexpected\n' > "$work/extra-entry/unexpected.txt"
tar -C "$work/extra-entry" -czf "$work/extra-entry.tar.gz" \
  bootstrap-manifest.json bootstrap-manifest.sig manifest.json manifest.sig \
  control-center control-center-privileged-worker unexpected.txt
if "$UPDATER" --package "$work/extra-entry.tar.gz" >"$work/extra-entry.out" 2>"$work/extra-entry.err"; then
  fail "package with unexpected entry was accepted"
fi
grep -Fq 'unexpected entries' "$work/extra-entry.err" || fail "unexpected-entry rejection reason was not recorded"
[[ "$(readlink "$CURRENT_LINK")" == "$after_success" ]] || fail "unexpected-entry rejection changed current link"
assert_runtime "$target_version"

# 6. Correctly signed package-v2 for the wrong architecture must fail closed.
wrong_arch=arm64
[[ "$goarch" == arm64 ]] && wrong_arch=amd64
package_v2 "$work/target" "$work/worker-good" "$target_version" "$target_commit" "$work/wrong-arch.tar.gz" "$wrong_arch"
if "$UPDATER" --package "$work/wrong-arch.tar.gz" >"$work/wrong-arch.out" 2>"$work/wrong-arch.err"; then
  fail "wrong-architecture package was accepted"
fi
[[ "$(readlink "$CURRENT_LINK")" == "$after_success" ]] || fail "platform rejection changed current link"
assert_runtime "$target_version"

# 7. A correctly signed downgrade package-v2 must be rejected by version policy.
build_main "$work/downgrade" "$downgrade_version" "$downgrade_commit"
package_v2 "$work/downgrade" "$work/worker-good" "$downgrade_version" "$downgrade_commit" "$work/downgrade.tar.gz"
if "$UPDATER" --package "$work/downgrade.tar.gz" >"$work/downgrade.out" 2>"$work/downgrade.err"; then
  fail "downgrade was accepted without --allow-downgrade"
fi
grep -Fq 'is older than current' "$work/downgrade.err" || fail "downgrade rejection reason was not recorded"
[[ "$(readlink "$CURRENT_LINK")" == "$after_success" ]] || fail "downgrade rejection changed current link"
assert_runtime "$target_version"

# 8. The main candidate may pass the schema-1 trust bridge, but a tampered
# schema-2 manifest must still fail its Ed25519 signature before any switch.
mkdir "$work/tampered-manifest"
tar -xzf "$work/target.tar.gz" -C "$work/tampered-manifest"
python3 - "$work/tampered-manifest/manifest.json" <<'PY'
import json,sys
p=sys.argv[1]
d=json.load(open(p, encoding="utf-8"))
d["channel"]="stable" if d["channel"]=="beta" else "beta"
open(p,"w",encoding="utf-8").write(json.dumps(d,indent=2)+"\n")
PY
repack_v2 "$work/tampered-manifest" "$work/tampered-manifest.tar.gz"
if "$UPDATER" --package "$work/tampered-manifest.tar.gz" >"$work/tampered-manifest.out" 2>"$work/tampered-manifest.err"; then
  fail "tampered schema-2 manifest was accepted"
fi
[[ "$(readlink "$CURRENT_LINK")" == "$after_success" ]] || fail "signature rejection changed current link"
assert_runtime "$target_version"

# 9. A correctly signed pair with a deliberately non-starting worker must
# switch neither runtime permanently. Rollback must restore current pointer,
# main readiness, worker enable/active state and socket boundary.
build_main "$work/broken-main" "$broken_version" "$broken_commit"
printf '#!/bin/sh\nexit 70\n' > "$work/worker-broken"
chmod 0755 "$work/worker-broken"
package_v2 "$work/broken-main" "$work/worker-broken" "$broken_version" "$broken_commit" "$work/broken-worker.tar.gz"
if "$UPDATER" --package "$work/broken-worker.tar.gz" >"$work/broken-worker.out" 2>"$work/broken-worker.err"; then
  fail "broken signed worker unexpectedly passed dual-runtime acceptance"
fi
[[ "$(readlink "$CURRENT_LINK")" == "$after_success" ]] || fail "failed worker update did not roll back current link"
[[ "$(readlink "$PREVIOUS_LINK")" == "$initial_target" ]] || fail "failed update changed previous release pointer"
assert_runtime "$target_version"
grep -Fq 'rolling back' "$work/broken-worker.out" || fail "worker rollback was not recorded in updater output"

printf 'Safe update-v2 acceptance passed: signed dual-runtime update, exact idempotent replay, same-version identity-drift rejection, trusted-bridge artifact rejection without execution, package whitelist rejection, platform rejection, downgrade rejection, schema-2 signature rejection, and worker-first automatic rollback.\n'
