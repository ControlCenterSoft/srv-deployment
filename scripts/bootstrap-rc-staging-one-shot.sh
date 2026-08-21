#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

REPO="ControlCenterSoft/srv-deployment"
PLATFORM_COMMIT="9ab8ea4acf46dedbf7309803c87da2b2f4632ceb"
PLATFORM_BLOB="59cc26c72876d7e2d0a9b98205f26a8a5bdc77f9"
STAGING_COMMIT="9ab8ea4acf46dedbf7309803c87da2b2f4632ceb"
STAGING_BLOB="a4fbb16a3acc00213dfebc0a64a936c28b4e7350"
EXPECTED_RUNTIME_VERSION="1.0.0"
EXPECTED_RUNTIME_COMMIT="1b364ae88789696bf98537d21544de8a259d086d"
CURRENT_BIN="/usr/local/lib/control-center/current/control-center"
WORK=""

log() { printf '[control-center-rc-staging] %s\n' "$*"; }
fail() { printf 'RC_STAGING_BOOTSTRAP_FAILED: %s\n' "$*" >&2; exit 1; }
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
  ! systemctl is-active --quiet control-center-privileged-worker.service 2>/dev/null \
    || fail "privileged worker unexpectedly active before signed RC switch"
  ! systemctl is-enabled --quiet control-center-privileged-worker.service 2>/dev/null \
    || fail "privileged worker unexpectedly enabled before signed RC switch"
}

assert_frozen_runtime
WORK="$(mktemp -d /tmp/control-center-rc-staging.XXXXXX)"

python3 - "$REPO" "$PLATFORM_COMMIT" "$PLATFORM_BLOB" "$STAGING_COMMIT" "$STAGING_BLOB" "$WORK" <<'PY'
import base64
import json
import pathlib
import sys
import urllib.error
import urllib.parse
import urllib.request

repo, platform_commit, platform_blob, staging_commit, staging_blob, work_raw = sys.argv[1:]
work = pathlib.Path(work_raw)
owner, name = repo.split('/', 1)
items = [
    (platform_commit, 'scripts/bootstrap-platform-v2-staging-complete.sh', platform_blob, 'platform-complete.sh'),
    (staging_commit, 'scripts/bootstrap-real-staging.sh', staging_blob, 'real-staging.sh'),
]
headers = {
    'Accept': 'application/vnd.github+json',
    'User-Agent': 'control-center-rc-staging-one-shot/1',
    'X-GitHub-Api-Version': '2022-11-28',
}
for commit, source, expected_blob, destination in items:
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

chmod 0700 "$WORK/platform-complete.sh" "$WORK/real-staging.sh"
bash -n "$WORK/platform-complete.sh" "$WORK/real-staging.sh"

log "preparing updater-v2, dormant privileged worker and Ops Agent 1.1.6"
bash "$WORK/platform-complete.sh"
assert_frozen_runtime
assert_worker_dormant

log "configuring restricted GitHub Actions real-staging identity and signing trust"
# This step reuses an existing GitHub credential if it has repository secret
# access. Only if that credential is absent/insufficient will gh request device
# authorization interactively; no token/private key is printed by this wrapper.
bash "$WORK/real-staging.sh"
assert_frozen_runtime
assert_worker_dormant

systemctl is-active --quiet control-center-ops-broker.service \
  || fail "ops broker is not active"
systemctl is-active --quiet control-center-ops-agent.timer \
  || fail "ops timer is not active"
systemctl cat control-center-platform-v2-prepare.service >/dev/null 2>&1 \
  || fail "typed platform-v2 prepare oneshot is not installed"
[[ -x /usr/local/sbin/control-center-update ]] \
  || fail "updater-v2 is missing"
[[ -x /usr/local/sbin/control-center-staging-update ]] \
  || fail "restricted staging updater is missing"
[[ -s /etc/control-center/staging-update-public.pem ]] \
  || fail "server-pinned staging signing trust is missing"
[[ -s /var/lib/control-center-staging-bootstrap/state.json ]] \
  || fail "staging bootstrap state evidence is missing"

python3 - /var/lib/control-center-staging-bootstrap/state.json <<'PY'
import json, pathlib, sys
p = pathlib.Path(sys.argv[1])
data = json.loads(p.read_text(encoding='utf-8'))
assert data.get('schema') == 3
assert data.get('repository') == 'ControlCenterSoft/srv-deployment'
assert data.get('allow_auto_merge') is True
assert data.get('server_pinned_staging_trust') is True
assert isinstance(data.get('staging_port'), int) and 1 <= data['staging_port'] <= 65535
assert isinstance(data.get('staging_host'), str) and data['staging_host']
assert data.get('staging_user') == 'control-center-staging'
PY

log "RC staging control plane is ready; accepted 1.0.0 runtime remains untouched"
printf 'RC_STAGING_BOOTSTRAP=PASSED\n'
printf 'RUNTIME_VERSION=%s\n' "$EXPECTED_RUNTIME_VERSION"
printf 'RUNTIME_COMMIT=%s\n' "$EXPECTED_RUNTIME_COMMIT"
printf 'UPDATER_V2_INSTALLED=true\n'
printf 'WORKER_ACTIVE=false\n'
printf 'WORKER_ENABLED=false\n'
printf 'OPS_AGENT_VERSION=1.1.6\n'
printf 'PLATFORM_PREPARE_V2=typed-oneshot\n'
printf 'REAL_STAGING_SECRETS=CONFIGURED\n'
printf 'SERVER_PINNED_STAGING_TRUST=true\n'
printf 'PRIVATE_VALUES=NOT_PRINTED\n'
