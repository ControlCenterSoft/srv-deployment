#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

REPO="ControlCenterSoft/srv-deployment"
BRIDGE_COMMIT="e3eb433684b8dc9dc82e02489f2b57f31d11bdb7"
BRIDGE_BLOB="9213d736c05686a0b581d5a5c909cec07dc7b266"
OPS_COMMIT="2369cca3cf9bee6e428e946bbe72a239baa7b444"
OPS_BLOB="bd5ac39a8c4353cf19260879be8e2ee888bc5197"
EXPECTED_RUNTIME_VERSION="1.0.0"
EXPECTED_RUNTIME_COMMIT="1b364ae88789696bf98537d21544de8a259d086d"
CURRENT_BIN="/usr/local/lib/control-center/current/control-center"
WORK=""

log() { printf '[control-center-staging-complete] %s\n' "$*"; }
fail() { printf 'STAGING_PLATFORM_V2_COMPLETE_FAILED: %s\n' "$*" >&2; exit 1; }
cleanup() { [[ -n "$WORK" ]] && rm -rf -- "$WORK"; }
trap cleanup EXIT

[[ ${EUID:-$(id -u)} -eq 0 ]] || fail "run as root"
for bin in python3 bash systemctl; do command -v "$bin" >/dev/null 2>&1 || fail "missing $bin"; done
[[ -x "$CURRENT_BIN" ]] || fail "trusted current runtime is missing"

assert_frozen_runtime() {
  local version commit
  version="$("$CURRENT_BIN" build-info --field version)" || fail "cannot read current runtime version"
  commit="$("$CURRENT_BIN" build-info --field commit)" || fail "cannot read current runtime commit"
  [[ "$version" == "$EXPECTED_RUNTIME_VERSION" ]] || fail "runtime version rejected: $version"
  [[ "$commit" == "$EXPECTED_RUNTIME_COMMIT" ]] || fail "runtime commit rejected: $commit"
}

assert_worker_dormant() {
  systemctl cat control-center-privileged-worker.service >/dev/null 2>&1 \
    || fail "privileged worker unit is not installed"
  if systemctl is-active --quiet control-center-privileged-worker.service 2>/dev/null; then
    fail "privileged worker unexpectedly active before signed package-v2 switch"
  fi
  if systemctl is-enabled --quiet control-center-privileged-worker.service 2>/dev/null; then
    fail "privileged worker unexpectedly enabled before signed package-v2 switch"
  fi
}

assert_frozen_runtime
if systemctl is-active --quiet control-center-privileged-worker.service 2>/dev/null; then
  fail "privileged worker already active; source state is not the accepted 1.0.0 staging baseline"
fi

WORK="$(mktemp -d /tmp/control-center-staging-complete.XXXXXX)"

python3 - "$REPO" "$BRIDGE_COMMIT" "$BRIDGE_BLOB" "$OPS_COMMIT" "$OPS_BLOB" "$WORK" <<'PY'
import base64
import json
import pathlib
import sys
import urllib.error
import urllib.parse
import urllib.request

repo, bridge_commit, bridge_blob, ops_commit, ops_blob, work_raw = sys.argv[1:]
work = pathlib.Path(work_raw)
owner, name = repo.split('/', 1)
items = [
    (bridge_commit, 'scripts/bootstrap-platform-v2-staging.sh', bridge_blob, 'platform-v2-bridge.sh'),
    (ops_commit, 'scripts/bootstrap-ops-agent.sh', ops_blob, 'ops-bootstrap.sh'),
]
headers = {
    'Accept': 'application/vnd.github+json',
    'User-Agent': 'control-center-staging-complete/1',
    'X-GitHub-Api-Version': '2022-11-28',
}
for commit, source, expected_blob, destination in items:
    encoded = '/'.join(urllib.parse.quote(part, safe='') for part in source.split('/'))
    url = (
        f'https://api.github.com/repos/{urllib.parse.quote(owner, safe="")}/'
        f'{urllib.parse.quote(name, safe="")}/contents/{encoded}?ref={urllib.parse.quote(commit, safe="")}'
    )
    request = urllib.request.Request(url, headers=headers, method='GET')
    try:
        with urllib.request.urlopen(request, timeout=20) as response:
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

chmod 0755 "$WORK/platform-v2-bridge.sh" "$WORK/ops-bootstrap.sh"
bash -n "$WORK/platform-v2-bridge.sh"
bash -n "$WORK/ops-bootstrap.sh"

log "installing authenticated updater-v2 and dormant worker platform"
bash "$WORK/platform-v2-bridge.sh"
assert_frozen_runtime
assert_worker_dormant

log "upgrading autonomous typed Ops Agent to accepted 1.1.6"
bash "$WORK/ops-bootstrap.sh"
assert_frozen_runtime
assert_worker_dormant

systemctl is-active --quiet control-center-ops-broker.service \
  || fail "ops broker is not active"
systemctl is-active --quiet control-center-ops-agent.timer \
  || fail "ops timer is not active"
systemctl cat control-center-platform-v2-prepare.service >/dev/null 2>&1 \
  || fail "typed platform-v2 prepare oneshot is not installed"

log "staging bridge and autonomous typed preparation channel are ready; frozen runtime is unchanged"
printf 'STAGING_PLATFORM_V2_COMPLETE=PASSED\n'
printf 'RUNTIME_VERSION=%s\n' "$EXPECTED_RUNTIME_VERSION"
printf 'RUNTIME_COMMIT=%s\n' "$EXPECTED_RUNTIME_COMMIT"
printf 'UPDATER_V2_INSTALLED=true\n'
printf 'WORKER_UNIT_INSTALLED=true\n'
printf 'WORKER_ACTIVE=false\n'
printf 'OPS_AGENT_VERSION=1.1.6\n'
printf 'PLATFORM_PREPARE_V2=typed-oneshot\n'
printf 'FROZEN_RUNTIME_UNCHANGED=true\n'
printf 'ROOT_INTERACTION_COMPLETE=true\n'
