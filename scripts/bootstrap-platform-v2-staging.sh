#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

REPO="ControlCenterSoft/srv-deployment"
SOURCE_COMMIT="66e751d5bd5bd2fe85e48041c75e136d033c6366"
EXPECTED_UPDATE_BLOB="4b535cc41f88f99ba0ac114b238ee111af8155f6"
EXPECTED_MIGRATION_BLOB="2afb7455a91de6e61bc3ab6d0a0b0e7bd4828275"
EXPECTED_RUNTIME_VERSION="1.0.0"
EXPECTED_RUNTIME_COMMIT="1b364ae88789696bf98537d21544de8a259d086d"
INSTALL_ROOT="/usr/local/lib/control-center"
CURRENT_BIN="$INSTALL_ROOT/current/control-center"
UPDATER="/usr/local/sbin/control-center-update"
STATE_DIR="/var/lib/control-center/staging-v2-bootstrap"
WORK=""

log() { printf '[control-center-staging-v2] %s\n' "$*"; }
fail() { printf 'STAGING_PLATFORM_V2_BOOTSTRAP_FAILED: %s\n' "$*" >&2; exit 1; }
cleanup() { [[ -n "$WORK" ]] && rm -rf -- "$WORK"; }
trap cleanup EXIT

[[ ${EUID:-$(id -u)} -eq 0 ]] || fail "run as root"
for bin in python3 systemctl install stat cmp; do command -v "$bin" >/dev/null 2>&1 || fail "missing $bin"; done
[[ -x "$CURRENT_BIN" ]] || fail "trusted current runtime is missing"
[[ -f "$UPDATER" && ! -L "$UPDATER" ]] || fail "existing updater is missing or unsafe"

current_version="$("$CURRENT_BIN" build-info --field version)" || fail "cannot read current runtime version"
current_commit="$("$CURRENT_BIN" build-info --field commit)" || fail "cannot read current runtime commit"
[[ "$current_version" == "$EXPECTED_RUNTIME_VERSION" ]] || fail "runtime version rejected: $current_version"
[[ "$current_commit" == "$EXPECTED_RUNTIME_COMMIT" ]] || fail "runtime commit rejected: $current_commit"

if systemctl is-active --quiet control-center-privileged-worker.service 2>/dev/null; then
  fail "privileged worker is already active; staging bootstrap source state is not exact 1.0.0"
fi

WORK="$(mktemp -d /tmp/control-center-staging-v2.XXXXXX)"
install -d -o root -g root -m 0700 "$STATE_DIR"

python3 - "$REPO" "$SOURCE_COMMIT" "$EXPECTED_UPDATE_BLOB" "$EXPECTED_MIGRATION_BLOB" "$WORK" <<'PY'
import base64
import json
import pathlib
import sys
import urllib.error
import urllib.parse
import urllib.request

repo, commit, update_blob, migration_blob, work_raw = sys.argv[1:]
work = pathlib.Path(work_raw)
owner, name = repo.split('/', 1)
files = {
    'install/update-v2.sh': ('update-v2.sh', update_blob),
    'install/migrate-platform-v2.sh': ('migrate-platform-v2.sh', migration_blob),
}
headers = {
    'Accept': 'application/vnd.github+json',
    'User-Agent': 'control-center-staging-v2-bootstrap/1',
    'X-GitHub-Api-Version': '2022-11-28',
}
for source, (destination, expected_blob) in files.items():
    encoded = '/'.join(urllib.parse.quote(part, safe='') for part in source.split('/'))
    url = (
        f'https://api.github.com/repos/{urllib.parse.quote(owner, safe="")}/'
        f'{urllib.parse.quote(name, safe="")}/contents/{encoded}?ref={urllib.parse.quote(commit, safe="")}'
    )
    req = urllib.request.Request(url, headers=headers, method='GET')
    try:
        with urllib.request.urlopen(req, timeout=20) as response:
            payload = json.load(response)
    except urllib.error.HTTPError as exc:
        raise SystemExit(f'cannot fetch {source}: HTTP {exc.code}') from None
    if not isinstance(payload, dict) or payload.get('sha') != expected_blob:
        raise SystemExit(f'pinned blob mismatch for {source}')
    content = payload.get('content')
    if not isinstance(content, str):
        raise SystemExit(f'missing content for {source}')
    (work / destination).write_bytes(base64.b64decode(content, validate=False))
PY

chmod 0755 "$WORK/update-v2.sh" "$WORK/migrate-platform-v2.sh"
bash -n "$WORK/update-v2.sh"
bash -n "$WORK/migrate-platform-v2.sh"

if [[ ! -f "$STATE_DIR/previous-updater" ]]; then
  install -o root -g root -m 0755 "$UPDATER" "$STATE_DIR/previous-updater"
fi

rollback() {
  local rc=$?
  trap - ERR
  if [[ -f "$STATE_DIR/previous-updater" ]]; then
    install -o root -g root -m 0755 "$STATE_DIR/previous-updater" "$UPDATER" || true
  fi
  exit "$rc"
}
trap rollback ERR

install -o root -g root -m 0755 "$WORK/update-v2.sh" "$UPDATER"
cmp -s "$WORK/update-v2.sh" "$UPDATER" || fail "installed updater-v2 differs from pinned source"

bash "$WORK/migrate-platform-v2.sh"

systemctl cat control-center-privileged-worker.service >/dev/null 2>&1 \
  || fail "privileged worker unit is not installed"
if systemctl is-active --quiet control-center-privileged-worker.service 2>/dev/null; then
  fail "privileged worker unexpectedly active before signed package-v2 switch"
fi
if systemctl is-enabled --quiet control-center-privileged-worker.service 2>/dev/null; then
  fail "privileged worker unexpectedly enabled before signed package-v2 switch"
fi
[[ "$("$CURRENT_BIN" build-info --field version)" == "$EXPECTED_RUNTIME_VERSION" ]] \
  || fail "runtime identity changed during bootstrap"
[[ "$("$CURRENT_BIN" build-info --field commit)" == "$EXPECTED_RUNTIME_COMMIT" ]] \
  || fail "runtime commit changed during bootstrap"

trap - ERR
log "staging platform-v2 bridge installed; accepted runtime remains frozen until signed package-v2 switch"
printf 'STAGING_PLATFORM_V2_BOOTSTRAP=PASSED\n'
printf 'SOURCE_COMMIT=%s\n' "$SOURCE_COMMIT"
printf 'RUNTIME_VERSION=%s\n' "$EXPECTED_RUNTIME_VERSION"
printf 'RUNTIME_COMMIT=%s\n' "$EXPECTED_RUNTIME_COMMIT"
printf 'UPDATER_V2_INSTALLED=true\n'
printf 'WORKER_UNIT_INSTALLED=true\n'
printf 'WORKER_ACTIVE=false\n'
printf 'FROZEN_RUNTIME_UNCHANGED=true\n'
