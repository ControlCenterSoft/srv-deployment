#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

DIAG_REPO="ControlCenterSoft/control-center-server-diagnostics"
DIAG_COMMIT="3ea5c4124d4eda8f048c1a6e8bd40f2f5e2f5d57"
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
    "agent/ccops_agent_v3.py": ("agent/ccops_agent_v3.py", "219622f0750794eda9beea7a94f4c2f153e9dbcf"),
    "agent/ccops_broker.py": ("agent/ccops_broker.py", "de14cd6b0686d7fdd09fc76adbdc40db2cb17085"),
    "agent/ccops_socket_broker.py": ("agent/ccops_socket_broker.py", "15903ccc2c94aa5ba96ec076732ce38c347ab680"),
    "agent/platform_v2_prepare.py": ("agent/platform_v2_prepare.py", "1646959a5d3cf9e0869c38386aee45ec98d739e8"),
    "install/install-ops-v3.sh": ("install/install-ops-v3.sh", "6d7020ddd02793ad64bd1fe8bc459d3668f70d52"),
}

owner, name = repo.split("/", 1)
headers = {
    "Accept": "application/vnd.github+json",
    "Authorization": f"Bearer {token}",
    "User-Agent": "control-center-ops-bootstrap/1.1.6",
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

chmod 0755 \
  "$WORK/agent/ccops_agent_v3.py" \
  "$WORK/agent/ccops_socket_broker.py" \
  "$WORK/agent/platform_v2_prepare.py" \
  "$WORK/install/install-ops-v3.sh"
chmod 0644 "$WORK/agent/ccops_agent_v2.py" "$WORK/agent/ccops_broker.py"
python3 -m py_compile \
  "$WORK/agent/ccops_agent_v2.py" \
  "$WORK/agent/ccops_agent_v3.py" \
  "$WORK/agent/ccops_broker.py" \
  "$WORK/agent/ccops_socket_broker.py" \
  "$WORK/agent/platform_v2_prepare.py"
bash -n "$WORK/install/install-ops-v3.sh"
bash "$WORK/install/install-ops-v3.sh"

systemctl is-enabled --quiet control-center-ops-agent.timer \
  || fail "ops timer is not enabled after installation"
systemctl is-active --quiet control-center-ops-agent.timer \
  || fail "ops timer is not active after installation"
systemctl is-active --quiet control-center-ops-broker.service \
  || fail "Unix root broker is not active after installation"
systemctl cat control-center-platform-v2-prepare.service >/dev/null \
  || fail "platform-v2 preparation oneshot is not registered"
[[ -S /run/control-center-ops/broker.sock ]] \
  || fail "Unix root broker socket is missing"
[[ "$(systemctl show control-center-ops-agent.service -p NoNewPrivileges --value)" == yes ]] \
  || fail "ops agent NoNewPrivileges hardening is not active"
[[ "$(systemctl show control-center-platform-v2-prepare.service -p NoNewPrivileges --value)" == yes ]] \
  || fail "platform prepare NoNewPrivileges hardening is not active"
[[ "$(systemctl show control-center-platform-v2-prepare.service -p CapabilityBoundingSet --value)" == "" ]] \
  || fail "platform prepare capability bounding set is not empty"
systemctl start control-center-ops-agent.service \
  || fail "ops agent first run failed"

registration_path="state/${server_id}/ops-registration.json"
registration_url="https://api.github.com/repos/${DIAG_REPO}/contents/${registration_path}?ref=${AGENT_STATE_BRANCH}"
python3 - "$TOKEN_FILE" "$registration_url" "$server_id" <<'PY'
import base64,json,pathlib,sys,urllib.request

token_file,url,server_id=sys.argv[1:]
token=pathlib.Path(token_file).read_text(encoding='utf-8').strip()
req=urllib.request.Request(url, headers={
    'Accept':'application/vnd.github+json',
    'Authorization':f'Bearer {token}',
    'User-Agent':'control-center-ops-bootstrap/1.1.6',
    'X-GitHub-Api-Version':'2022-11-28',
})
with urllib.request.urlopen(req, timeout=20) as response:
    wrapper=json.load(response)
payload=json.loads(base64.b64decode(wrapper['content']).decode('utf-8'))
assert payload.get('schema') == 1
assert payload.get('server_id') == server_id
assert payload.get('agent_version') == '1.1.6'
assert payload.get('arbitrary_shell') is False
assert payload.get('privilege_boundary') == 'unix-so-peercred-root-broker'
assert payload.get('broker_transport') == 'unix'
assert payload.get('sudo_required') is False
assert 'platform.prepare-v2' in payload.get('capabilities', [])
PY

printf 'CONTROL_CENTER_OPS_BOOTSTRAP=PASSED\n'
printf 'DIAGNOSTICS_SOURCE_COMMIT=%s\n' "$DIAG_COMMIT"
printf 'REMOTE_AGENT_RELEASE=1.1.6\n'
printf 'OPS_AGENT_VERSION=1.1.6\n'
printf 'BROKER_CORE_VERSION=1.1.5\n'
printf 'BROKER_TRANSPORT_VERSION=1.1.6\n'
printf 'PLATFORM_PREPARE_V2=typed-oneshot\n'
printf 'TOKEN_REUSED=existing-diagnostics-token\n'
printf 'ROOT_BOUNDARY=unix-so-peercred-root-broker\n'
printf 'SUDO_REQUIRED=false\n'
printf 'AUDIT_CORRELATION=request_id\n'
printf 'ARBITRARY_SHELL=disabled\n'
