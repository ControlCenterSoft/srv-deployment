#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

REPO="ControlCenterSoft/srv-deployment"
SOURCE_COMMIT="c951511c164707e57b9ac9cd670893e62a254e4d"
SOURCE_PATH="scripts/bootstrap-real-staging.sh"
SOURCE_BLOB="a4fbb16a3acc00213dfebc0a64a936c28b4e7350"
EXPECTED_RUNTIME_VERSION="1.0.0"
EXPECTED_RUNTIME_COMMIT="1b364ae88789696bf98537d21544de8a259d086d"
CURRENT_BIN="/usr/local/lib/control-center/current/control-center"
WORK=""

fail() { printf 'REAL_STAGING_RESUME_FAILED: %s\n' "$*" >&2; exit 1; }
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
assert_worker_dormant
systemctl is-active --quiet control-center-ops-broker.service \
  || fail "Ops Agent 1.1.6 broker is not active"
systemctl is-active --quiet control-center-ops-agent.timer \
  || fail "Ops Agent timer is not active"
systemctl cat control-center-platform-v2-prepare.service >/dev/null 2>&1 \
  || fail "typed platform-v2 preparation service is missing"

WORK="$(mktemp -d /tmp/control-center-staging-resume.XXXXXX)"

python3 - "$REPO" "$SOURCE_COMMIT" "$SOURCE_PATH" "$SOURCE_BLOB" "$WORK/bootstrap-real-staging.safe.sh" <<'PY'
import base64
import json
import pathlib
import sys
import urllib.error
import urllib.parse
import urllib.request

repo, commit, source_path, expected_blob, destination_raw = sys.argv[1:]
destination = pathlib.Path(destination_raw)
owner, name = repo.split('/', 1)
encoded = '/'.join(urllib.parse.quote(part, safe='') for part in source_path.split('/'))
url = (
    f'https://api.github.com/repos/{urllib.parse.quote(owner, safe="")}/'
    f'{urllib.parse.quote(name, safe="")}/contents/{encoded}?ref={urllib.parse.quote(commit, safe="")}'
)
request = urllib.request.Request(url, method='GET', headers={
    'Accept': 'application/vnd.github+json',
    'User-Agent': 'control-center-real-staging-resume/1',
    'X-GitHub-Api-Version': '2022-11-28',
})
try:
    with urllib.request.urlopen(request, timeout=20) as response:
        payload = json.load(response)
except urllib.error.HTTPError as exc:
    raise SystemExit(f'cannot fetch pinned staging bootstrap: HTTP {exc.code}') from None
if not isinstance(payload, dict) or payload.get('sha') != expected_blob:
    raise SystemExit('pinned staging bootstrap blob mismatch')
encoded_content = payload.get('content')
if not isinstance(encoded_content, str):
    raise SystemExit('pinned staging bootstrap content missing')
text = base64.b64decode(encoded_content, validate=False).decode('utf-8')
old = '  SSH_PORT="$(sshd -T 2>/dev/null | awk \'$1=="port" {print $2; exit}\')"'
new = '''  sshd_effective="$(sshd -T 2>/dev/null)"
  SSH_PORT="$(awk '$1=="port" {port=$2} END {if (port == "") exit 1; print port}' <<<"$sshd_effective")"'''
if text.count(old) != 1:
    raise SystemExit('expected sshd port pipeline was not found exactly once')
text = text.replace(old, new, 1)
if 'sshd -T 2>/dev/null | awk' in text:
    raise SystemExit('unsafe sshd early-exit pipeline remains after patch')
destination.write_text(text, encoding='utf-8')
destination.chmod(0o700)
print('STAGING_RESUME_PATCH=SIGPIPE_SAFE')
PY

bash -n "$WORK/bootstrap-real-staging.safe.sh"
bash "$WORK/bootstrap-real-staging.safe.sh"

assert_frozen_runtime
assert_worker_dormant
[[ -x /usr/local/sbin/control-center-staging-update ]] \
  || fail "restricted staging updater is missing"
[[ -s /etc/control-center/staging-update-public.pem ]] \
  || fail "server-pinned staging signing trust is missing"
[[ -s /var/lib/control-center-staging-bootstrap/state.json ]] \
  || fail "staging state evidence is missing"

python3 - /var/lib/control-center-staging-bootstrap/state.json <<'PY'
import json
import pathlib
import sys

payload = json.loads(pathlib.Path(sys.argv[1]).read_text(encoding='utf-8'))
assert payload.get('schema') == 3
assert payload.get('repository') == 'ControlCenterSoft/srv-deployment'
assert payload.get('allow_auto_merge') is True
assert payload.get('server_pinned_staging_trust') is True
assert payload.get('staging_user') == 'control-center-staging'
assert isinstance(payload.get('staging_host'), str) and payload['staging_host']
assert isinstance(payload.get('staging_port'), int) and 1 <= payload['staging_port'] <= 65535
PY

printf 'REAL_STAGING_RESUME=PASSED\n'
printf 'RUNTIME_VERSION=%s\n' "$EXPECTED_RUNTIME_VERSION"
printf 'RUNTIME_COMMIT=%s\n' "$EXPECTED_RUNTIME_COMMIT"
printf 'OPS_AGENT_VERSION=1.1.6\n'
printf 'WORKER_ACTIVE=false\n'
printf 'WORKER_ENABLED=false\n'
printf 'REAL_STAGING_SECRETS=CONFIGURED\n'
printf 'SERVER_PINNED_STAGING_TRUST=true\n'
printf 'PRIVATE_VALUES=NOT_PRINTED\n'
