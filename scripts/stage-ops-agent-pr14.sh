#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

DIAG_REPO="ControlCenterSoft/control-center-server-diagnostics"
DIAG_COMMIT="d4337bdd5f3111431ee06858fcd0d3338655751c"
EXPECTED_BLOB="412ec9e08432e34d82c64813af079a4177a6ac1e"
EXPECTED_AGENT_VERSION="1.1.10"
EXPECTED_CONTROL_CENTER_VERSION="1.1.0-rc.6"
EXPECTED_CONTROL_CENTER_COMMIT="302eb6da97324d719849e7ae752fc10bdc557d9a"
TOKEN_FILE="/etc/control-center-diagnostics-agent/github-token"
CONFIG_FILE="/etc/control-center-diagnostics-agent/agent.conf"
AGENT_USER="ccdiag"
AGENT_FILE="/opt/control-center-diagnostics-agent/ccops_agent_v3.py"
STATE_DIR="/var/lib/control-center-ops-agent/state"
BACKUP_ROOT="/var/lib/control-center-ops-agent/backups"
TMP=""
BACKUP_DIR=""
INSTALLED_NEW=0

cleanup() { [[ -n "$TMP" ]] && rm -f -- "$TMP"; }
restore_backup() {
  if (( INSTALLED_NEW )) && [[ -n "$BACKUP_DIR" && -f "$BACKUP_DIR/ccops_agent_v3.py" ]]; then
    install -o root -g root -m 0755 "$BACKUP_DIR/ccops_agent_v3.py" "$AGENT_FILE" || true
    python3 -m py_compile "$AGENT_FILE" >/dev/null 2>&1 || true
    runuser -u "$AGENT_USER" -- /usr/bin/python3 "$AGENT_FILE" --register --state-dir "$STATE_DIR" >/dev/null 2>&1 || true
    systemctl start control-center-ops-agent.service >/dev/null 2>&1 || true
    printf 'OPS_AGENT_STAGE_ROLLBACK=RESTORED\n' >&2
    INSTALLED_NEW=0
  fi
}
fail() {
  printf 'OPS_AGENT_STAGE_FAILED: %s\n' "$*" >&2
  restore_backup
  exit 1
}
rollback() {
  local rc=$?
  restore_backup
  cleanup
  exit "$rc"
}
trap rollback ERR
trap cleanup EXIT

[[ ${EUID:-$(id -u)} -eq 0 ]] || fail "run as root"
for bin in python3 systemctl install runuser sha256sum mktemp stat grep sed head date; do command -v "$bin" >/dev/null || fail "missing $bin"; done
[[ -s "$TOKEN_FILE" ]] || fail "diagnostics token missing"
[[ -f "$CONFIG_FILE" ]] || fail "diagnostics config missing"
[[ -f "$AGENT_FILE" ]] || fail "installed ops agent missing"
[[ -d "$STATE_DIR" ]] || fail "ops state directory missing"
id "$AGENT_USER" >/dev/null 2>&1 || fail "ccdiag user missing"
systemctl is-active --quiet control-center-ops-broker.service || fail "ops broker is not active"
systemctl is-active --quiet control-center-ops-agent.timer || fail "ops agent timer is not active"
[[ "$(systemctl show control-center-ops-agent.service -p NoNewPrivileges --value)" == yes ]] || fail "NoNewPrivileges regression"
[[ -S /run/control-center-ops/broker.sock ]] || fail "broker socket missing"

server_id="$(sed -n 's/^SERVER_ID=//p' "$CONFIG_FILE" | head -n1)"
[[ "$server_id" =~ ^[A-Za-z0-9._-]{1,64}$ ]] || fail "invalid SERVER_ID"

# Preflight the current root broker with a read-only typed request before touching code.
runuser -u "$AGENT_USER" -- /usr/bin/python3 - "$EXPECTED_CONTROL_CENTER_VERSION" "$EXPECTED_CONTROL_CENTER_COMMIT" <<'PY'
import json, socket, sys
expected_version, expected_commit = sys.argv[1:]
request = {"schema": 1, "id": "stage-agent-pr14-preflight", "action": "version.get", "args": {}}
with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as conn:
    conn.settimeout(15)
    conn.connect("/run/control-center-ops/broker.sock")
    conn.sendall((json.dumps(request, separators=(",", ":")) + "\n").encode())
    conn.shutdown(socket.SHUT_WR)
    raw = bytearray()
    while len(raw) <= 131072:
        chunk = conn.recv(4096)
        if not chunk:
            break
        raw.extend(chunk)
        if b"\n" in chunk:
            break
if not raw.endswith(b"\n"):
    raise SystemExit("broker framing failed")
payload = json.loads(raw[:-1].decode("utf-8"))
if payload.get("ok") is not True:
    raise SystemExit("version preflight failed")
stdout = payload.get("result", {}).get("stdout", "")
version = json.loads(stdout)
if version.get("version") != expected_version or version.get("commit") != expected_commit:
    raise SystemExit("unexpected Control Center test-server identity")
PY

install -d -o root -g root -m 0700 "$BACKUP_ROOT"
BACKUP_DIR="$BACKUP_ROOT/stage-pr14-$(date -u +%Y%m%dT%H%M%SZ)"
install -d -o root -g root -m 0700 "$BACKUP_DIR"
install -o root -g root -m 0755 "$AGENT_FILE" "$BACKUP_DIR/ccops_agent_v3.py"
sha256sum "$BACKUP_DIR/ccops_agent_v3.py" > "$BACKUP_DIR/ccops_agent_v3.py.sha256"

TMP="$(mktemp /tmp/ccops-agent-pr14.XXXXXX.py)"
python3 - "$TOKEN_FILE" "$DIAG_REPO" "$DIAG_COMMIT" "$EXPECTED_BLOB" "$TMP" <<'PY'
import base64, json, pathlib, sys, urllib.parse, urllib.request

token_file, repo, commit, expected_blob, target_raw = sys.argv[1:]
token = pathlib.Path(token_file).read_text(encoding="utf-8").strip()
if not token:
    raise SystemExit("empty diagnostics token")
owner, name = repo.split("/", 1)
path = "agent/ccops_agent_v3.py"
encoded = "/".join(urllib.parse.quote(part, safe="") for part in path.split("/"))
url = (
    f"https://api.github.com/repos/{urllib.parse.quote(owner, safe='')}/"
    f"{urllib.parse.quote(name, safe='')}/contents/{encoded}?ref={urllib.parse.quote(commit, safe='')}"
)
req = urllib.request.Request(url, headers={
    "Accept": "application/vnd.github+json",
    "Authorization": f"Bearer {token}",
    "User-Agent": "control-center-ops-agent-stage/1.0",
    "X-GitHub-Api-Version": "2022-11-28",
})
with urllib.request.urlopen(req, timeout=20) as response:
    wrapper = json.load(response)
if wrapper.get("sha") != expected_blob:
    raise SystemExit("pinned agent blob mismatch")
content = wrapper.get("content")
if not isinstance(content, str):
    raise SystemExit("agent content missing")
pathlib.Path(target_raw).write_bytes(base64.b64decode(content, validate=False))
PY

python3 -m py_compile "$TMP"
grep -Fq 'AGENT_VERSION = "1.1.10"' "$TMP" || fail "staged agent identity mismatch"
install -o root -g root -m 0755 "$TMP" "$AGENT_FILE"
INSTALLED_NEW=1
python3 -m py_compile "$AGENT_FILE"

# Registration is a bounded write to the existing private agent-state control plane.
runuser -u "$AGENT_USER" -- /usr/bin/python3 "$AGENT_FILE" --register --state-dir "$STATE_DIR"
systemctl start control-center-ops-agent.service
systemctl is-active --quiet control-center-ops-broker.service || fail "broker inactive after agent stage"
systemctl is-active --quiet control-center-ops-agent.timer || fail "timer inactive after agent stage"
[[ "$(systemctl show control-center-ops-agent.service -p NoNewPrivileges --value)" == yes ]] || fail "NoNewPrivileges lost after stage"

# Verify the published registration from GitHub without printing credentials or raw reports.
python3 - "$TOKEN_FILE" "$DIAG_REPO" "$server_id" "$EXPECTED_AGENT_VERSION" <<'PY'
import base64, json, pathlib, sys, urllib.parse, urllib.request

token_file, repo, server_id, expected_version = sys.argv[1:]
token = pathlib.Path(token_file).read_text(encoding="utf-8").strip()
path = f"state/{server_id}/ops-registration.json"
owner, name = repo.split("/", 1)
encoded = "/".join(urllib.parse.quote(part, safe="") for part in path.split("/"))
url = f"https://api.github.com/repos/{owner}/{name}/contents/{encoded}?ref=agent-state"
req = urllib.request.Request(url, headers={
    "Accept": "application/vnd.github+json",
    "Authorization": f"Bearer {token}",
    "User-Agent": "control-center-ops-agent-stage/1.0",
    "X-GitHub-Api-Version": "2022-11-28",
})
with urllib.request.urlopen(req, timeout=20) as response:
    wrapper = json.load(response)
payload = json.loads(base64.b64decode(wrapper["content"]).decode("utf-8"))
assert payload.get("agent_version") == expected_version
assert payload.get("arbitrary_shell") is False
assert payload.get("privilege_boundary") == "unix-so-peercred-root-broker"
assert payload.get("broker_transport") == "unix"
assert payload.get("sudo_required") is False
PY

# Final read-only broker check proves product runtime identity was not changed by the agent stage.
runuser -u "$AGENT_USER" -- /usr/bin/python3 - "$EXPECTED_CONTROL_CENTER_VERSION" "$EXPECTED_CONTROL_CENTER_COMMIT" <<'PY'
import json, socket, sys
expected_version, expected_commit = sys.argv[1:]
request = {"schema": 1, "id": "stage-agent-pr14-postcheck", "action": "version.get", "args": {}}
with socket.socket(socket.AF_UNIX, socket.SOCK_STREAM) as conn:
    conn.settimeout(15)
    conn.connect("/run/control-center-ops/broker.sock")
    conn.sendall((json.dumps(request, separators=(",", ":")) + "\n").encode())
    conn.shutdown(socket.SHUT_WR)
    raw = bytearray()
    while len(raw) <= 131072:
        chunk = conn.recv(4096)
        if not chunk:
            break
        raw.extend(chunk)
        if b"\n" in chunk:
            break
if not raw.endswith(b"\n"):
    raise SystemExit("post-stage broker framing failed")
payload = json.loads(raw[:-1].decode("utf-8"))
if payload.get("ok") is not True:
    raise SystemExit("post-stage version check failed")
version = json.loads(payload.get("result", {}).get("stdout", ""))
if version.get("version") != expected_version or version.get("commit") != expected_commit:
    raise SystemExit("product runtime identity changed unexpectedly")
PY

INSTALLED_NEW=0
printf 'OPS_AGENT_STAGE=PASSED\n'
printf 'OPS_AGENT_VERSION=%s\n' "$EXPECTED_AGENT_VERSION"
printf 'DIAGNOSTICS_SOURCE_COMMIT=%s\n' "$DIAG_COMMIT"
printf 'CONTROL_CENTER_VERSION=%s\n' "$EXPECTED_CONTROL_CENTER_VERSION"
printf 'CONTROL_CENTER_COMMIT=%s\n' "$EXPECTED_CONTROL_CENTER_COMMIT"
printf 'ARBITRARY_SHELL=disabled\n'
printf 'ROOT_BOUNDARY=unix-so-peercred-root-broker\n'
