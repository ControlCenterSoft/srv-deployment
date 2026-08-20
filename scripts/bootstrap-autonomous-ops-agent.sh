#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

DIAGNOSTICS_REPO="ControlCenterSoft/control-center-server-diagnostics"
DIAGNOSTICS_COMMIT="006e3e21d2176b0d2ab8f97a4eae6f398061b292"
TOKEN_FILE="/etc/control-center-diagnostics-agent/github-token"
CONFIG_FILE="/etc/control-center-diagnostics-agent/agent.conf"
AGENT_STATE_BRANCH="agent-state"

fail() {
  printf 'AUTONOMOUS_OPS_BOOTSTRAP_FAILED: %s\n' "$*" >&2
  exit 1
}

[[ ${EUID:-$(id -u)} -eq 0 ]] || fail "run as root"
[[ -s "$TOKEN_FILE" ]] || fail "existing diagnostics token is missing: $TOKEN_FILE"
[[ -f "$CONFIG_FILE" ]] || fail "existing diagnostics config is missing: $CONFIG_FILE"
for bin in curl python3 systemctl runuser sudo install mktemp; do
  command -v "$bin" >/dev/null 2>&1 || fail "missing required command: $bin"
done

server_id="$(sed -n 's/^SERVER_ID=//p' "$CONFIG_FILE" | head -n1)"
[[ "$server_id" =~ ^[A-Za-z0-9._-]{1,64}$ ]] || fail "invalid SERVER_ID in diagnostics config"

token="$(cat "$TOKEN_FILE")"
[[ -n "$token" ]] || fail "diagnostics GitHub token is empty"

work="$(mktemp -d /tmp/control-center-ops-bootstrap.XXXXXX)"
cleanup() {
  rm -rf -- "$work"
  unset token
}
trap cleanup EXIT
install -d -m 0700 "$work/agent" "$work/install"

curl_cfg="$work/curl.conf"
{
  printf 'silent\n'
  printf 'show-error\n'
  printf 'fail\n'
  printf 'location\n'
  printf 'connect-timeout = 10\n'
  printf 'max-time = 60\n'
  printf 'header = "Accept: application/vnd.github.raw+json"\n'
  printf 'header = "X-GitHub-Api-Version: 2022-11-28"\n'
  printf 'header = "Authorization: Bearer %s"\n' "$token"
} > "$curl_cfg"
chmod 0600 "$curl_cfg"
unset token

fetch_private_file() {
  local source_path="$1" destination="$2"
  local url="https://api.github.com/repos/${DIAGNOSTICS_REPO}/contents/${source_path}?ref=${DIAGNOSTICS_COMMIT}"
  curl --config "$curl_cfg" --output "$destination" "$url" \
    || fail "cannot fetch $source_path at immutable diagnostics commit"
  [[ -s "$destination" ]] || fail "downloaded file is empty: $source_path"
}

# Prove that the pinned source commit exists and is readable by the already-installed token.
curl --config "$curl_cfg" \
  --header 'Accept: application/vnd.github+json' \
  --output "$work/commit.json" \
  "https://api.github.com/repos/${DIAGNOSTICS_REPO}/commits/${DIAGNOSTICS_COMMIT}" \
  || fail "cannot verify pinned diagnostics commit"
python3 - "$work/commit.json" "$DIAGNOSTICS_COMMIT" <<'PY'
import json,sys
payload=json.load(open(sys.argv[1], encoding='utf-8'))
assert payload.get('sha') == sys.argv[2]
PY

fetch_private_file agent/ccops_agent.py "$work/agent/ccops_agent.py"
fetch_private_file agent/ccops_broker.py "$work/agent/ccops_broker.py"
fetch_private_file install/install-ops.sh "$work/install/install-ops.sh"
chmod 0755 "$work/install/install-ops.sh"

python3 -m py_compile "$work/agent/ccops_agent.py" "$work/agent/ccops_broker.py" \
  || fail "downloaded ops agent Python syntax validation failed"
bash -n "$work/install/install-ops.sh" \
  || fail "downloaded ops installer syntax validation failed"

bash "$work/install/install-ops.sh" \
  || fail "ops agent installer failed"

systemctl is-enabled --quiet control-center-ops-agent.timer \
  || fail "ops agent timer is not enabled"
systemctl is-active --quiet control-center-ops-agent.timer \
  || fail "ops agent timer is not active"

self_test="$(runuser -u ccdiag -- sudo -n /usr/local/libexec/control-center-ops-broker --self-test)" \
  || fail "installed root broker self-test failed"
python3 - "$self_test" <<'PY'
import json,sys
p=json.loads(sys.argv[1])
assert p.get('ok') is True
assert p.get('broker_version') == '1.1.0'
assert 'health.get' in p.get('actions', [])
assert 'service.restart' in p.get('actions', [])
assert 'postgresql.service' in p.get('observable_services', [])
assert 'postgresql.service' not in p.get('restartable_services', [])
PY

registration_path="state/${server_id}/ops-registration.json"
registration_url="https://api.github.com/repos/${DIAGNOSTICS_REPO}/contents/${registration_path}?ref=${AGENT_STATE_BRANCH}"
curl --config "$curl_cfg" \
  --header 'Accept: application/vnd.github+json' \
  --output "$work/registration.json" \
  "$registration_url" \
  || fail "ops agent registration is not visible in private control plane"
python3 - "$work/registration.json" "$server_id" <<'PY'
import base64,json,sys
wrapper=json.load(open(sys.argv[1], encoding='utf-8'))
raw=base64.b64decode(wrapper['content']).decode('utf-8')
payload=json.loads(raw)
assert payload.get('schema') == 1
assert payload.get('server_id') == sys.argv[2]
assert payload.get('agent_version') == '1.1.0'
assert payload.get('arbitrary_shell') is False
assert payload.get('privilege_boundary') == 'sudo-root-broker'
PY

printf 'AUTONOMOUS_OPS_BOOTSTRAP=PASSED\n'
printf 'SERVER_ID=%s\n' "$server_id"
printf 'OPS_AGENT_VERSION=1.1.0\n'
printf 'PRIVATE_CONTROL_PLANE=READY\n'
printf 'ROOT_BOUNDARY=TYPED_BROKER\n'
printf 'ARBITRARY_SHELL=DISABLED\n'
printf 'USER_ACTION_AFTER_THIS=NONE\n'
