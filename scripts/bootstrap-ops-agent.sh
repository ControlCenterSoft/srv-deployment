#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

DIAG_REPO="ControlCenterSoft/control-center-server-diagnostics"
DIAG_COMMIT="37835def4f8943c8c3d0c58b4214095296eec9d3"
TOKEN_FILE="/etc/control-center-diagnostics-agent/github-token"
CONFIG_FILE="/etc/control-center-diagnostics-agent/agent.conf"
AGENT_STATE_BRANCH="agent-state"
WORK=""

fail() {
  printf 'OPS_BOOTSTRAP_FAILED: %s\n' "$*" >&2
  exit 1
}

cleanup() {
  [[ -n "$WORK" ]] && rm -rf -- "$WORK"
}
trap cleanup EXIT

[[ ${EUID:-$(id -u)} -eq 0 ]] || fail "run as root"
[[ -s "$TOKEN_FILE" ]] || fail "existing diagnostics token is missing: $TOKEN_FILE"
[[ -f "$CONFIG_FILE" ]] || fail "existing diagnostics config is missing: $CONFIG_FILE"
command -v python3 >/dev/null 2>&1 || fail "python3 is required"
command -v bash >/dev/null 2>&1 || fail "bash is required"
command -v systemctl >/dev/null 2>&1 || fail "systemctl is required"

server_id="$(sed -n 's/^SERVER_ID=//p' "$CONFIG_FILE" | head -n1)"
[[ "$server_id" =~ ^[A-Za-z0-9._-]{1,64}$ ]] || fail "invalid SERVER_ID in diagnostics config"

WORK="$(mktemp -d /tmp/control-center-ops-bootstrap.XXXXXX)"
install -d -m 0700 "$WORK/agent" "$WORK/install"

python3 - "$TOKEN_FILE" "$DIAG_REPO" "$DIAG_COMMIT" "$WORK" <<'PY'
import base64
import json
import pathlib
import sys
import urllib.error
import urllib.parse
import urllib.request

token_file, repo, commit, work_raw = sys.argv[1:]
work = pathlib.Path(work_raw)
token = pathlib.Path(token_file).read_text(encoding="utf-8").strip()
if not token:
    raise SystemExit("diagnostics token is empty")

files = {
    "agent/ccops_agent_v2.py": ("agent/ccops_agent_v2.py", "8ee6a3001016e1f127cb6050b77a80eee186823c"),
    "agent/ccops_agent_v3.py": ("agent/ccops_agent_v3.py", "0f167133ecb581c1de19b6336263239af6e4765d"),
    "agent/ccops_broker.py": ("agent/ccops_broker.py", "dcbeb90b5e78e2c77545a2a56468cd86e8a7327e"),
    "agent/ccops_socket_broker.py": ("agent/ccops_socket_broker.py", "59ff293d449f09ffbd29dde552da847f1c967b20"),
    "install/install-ops-v3.sh": ("install/install-ops-v3.sh", "4ea9a38fb51e7e4422f0649aa33da82b35f08394"),
}

owner, name = repo.split("/", 1)
headers = {
    "Accept": "application/vnd.github+json",
    "Authorization": f"Bearer {token}",
    "User-Agent": "control-center-ops-bootstrap/1.1.2",
    "X-GitHub-Api-Version": "2022-11-28",
}

for source, (destination, expected_blob) in files.items():
    encoded = "/".join(urllib.parse.quote(part, safe="") for part in source.split("/"))
    url = (
        f"https://api.github.com/repos/{urllib.parse.quote(owner, safe='')}/"
        f"{urllib.parse.quote(name, safe='')}/contents/{encoded}?ref={urllib.parse.quote(commit, safe='')}"
    )
    request = urllib.request.Request(url, method="GET", headers=headers)
    try:
        with urllib.request.urlopen(request, timeout=20) as response:
            data = json.load(response)
    except urllib.error.HTTPError as exc:
        raise SystemExit(f"cannot fetch {source}: HTTP {exc.code}") from None
    if not isinstance(data, dict) or data.get("sha") != expected_blob:
        raise SystemExit(f"pinned blob mismatch for {source}")
    encoded_content = data.get("content")
    if not isinstance(encoded_content, str):
        raise SystemExit(f"missing content for {source}")
    target = work / destination
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_bytes(base64.b64decode(encoded_content, validate=False))

del token
PY

chmod 0755 "$WORK/agent/ccops_agent_v3.py" "$WORK/agent/ccops_socket_broker.py" "$WORK/install/install-ops-v3.sh"
chmod 0644 "$WORK/agent/ccops_agent_v2.py" "$WORK/agent/ccops_broker.py"
python3 -m py_compile \
  "$WORK/agent/ccops_agent_v2.py" \
  "$WORK/agent/ccops_agent_v3.py" \
  "$WORK/agent/ccops_broker.py" \
  "$WORK/agent/ccops_socket_broker.py"
bash -n "$WORK/install/install-ops-v3.sh"
bash "$WORK/install/install-ops-v3.sh"

systemctl is-enabled --quiet control-center-ops-agent.timer \
  || fail "ops timer is not enabled after installation"
systemctl is-active --quiet control-center-ops-agent.timer \
  || fail "ops timer is not active after installation"
systemctl is-active --quiet control-center-ops-broker.service \
  || fail "Unix root broker is not active after installation"
[[ -S /run/control-center-ops/broker.sock ]] \
  || fail "Unix root broker socket is missing"
[[ "$(systemctl show control-center-ops-agent.service -p NoNewPrivileges --value)" == yes ]] \
  || fail "ops agent NoNewPrivileges hardening is not active"
systemctl start control-center-ops-agent.service \
  || fail "ops agent first post-install run failed"

registration_path="state/${server_id}/ops-registration.json"
registration_url="https://api.github.com/repos/${DIAG_REPO}/contents/${registration_path}?ref=${AGENT_STATE_BRANCH}"
python3 - "$TOKEN_FILE" "$registration_url" "$server_id" <<'PY'
import base64,json,pathlib,sys,urllib.request

token_file,url,server_id=sys.argv[1:]
token=pathlib.Path(token_file).read_text(encoding='utf-8').strip()
req=urllib.request.Request(url, headers={
    'Accept':'application/vnd.github+json',
    'Authorization':f'Bearer {token}',
    'User-Agent':'control-center-ops-bootstrap/1.1.2',
    'X-GitHub-Api-Version':'2022-11-28',
})
with urllib.request.urlopen(req, timeout=20) as response:
    wrapper=json.load(response)
payload=json.loads(base64.b64decode(wrapper['content']).decode('utf-8'))
assert payload.get('schema') == 1
assert payload.get('server_id') == server_id
assert payload.get('agent_version') == '1.1.2'
assert payload.get('arbitrary_shell') is False
assert payload.get('privilege_boundary') == 'unix-so-peercred-root-broker'
assert payload.get('sudo_required') is False
PY

printf 'CONTROL_CENTER_OPS_BOOTSTRAP=PASSED\n'
printf 'DIAGNOSTICS_SOURCE_COMMIT=%s\n' "$DIAG_COMMIT"
printf 'OPS_AGENT_VERSION=1.1.2\n'
printf 'TOKEN_REUSED=existing-diagnostics-token\n'
printf 'ROOT_BOUNDARY=unix-so-peercred-root-broker\n'
printf 'SUDO_REQUIRED=false\n'
printf 'AUDIT_CORRELATION=request_id\n'
printf 'ARBITRARY_SHELL=disabled\n'
