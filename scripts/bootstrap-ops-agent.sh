#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

DIAGNOSTICS_REPO="ControlCenterSoft/control-center-server-diagnostics"
DIAGNOSTICS_REF="94aad6b079ec9a7dff52e6187bed5f551f59672e"
TOKEN_FILE="/etc/control-center-diagnostics-agent/github-token"
CONFIG_FILE="/etc/control-center-diagnostics-agent/agent.conf"

fail() {
  printf 'OPS_AGENT_BOOTSTRAP_FAILED: %s\n' "$*" >&2
  exit 1
}

[[ ${EUID:-$(id -u)} -eq 0 ]] || fail "run as root"
[[ -s "$TOKEN_FILE" ]] || fail "existing diagnostics token is missing: $TOKEN_FILE"
[[ -f "$CONFIG_FILE" ]] || fail "existing diagnostics config is missing: $CONFIG_FILE"
command -v python3 >/dev/null 2>&1 || fail "python3 is required"
command -v systemctl >/dev/null 2>&1 || fail "systemd is required"

work="$(mktemp -d /tmp/control-center-ops-bootstrap.XXXXXX)"
cleanup() {
  rm -rf -- "$work"
}
trap cleanup EXIT

install -d -m 0700 "$work/repo/agent" "$work/repo/install"

python3 - "$DIAGNOSTICS_REPO" "$DIAGNOSTICS_REF" "$TOKEN_FILE" "$work/repo" <<'PY'
import base64
import json
import pathlib
import sys
import urllib.error
import urllib.parse
import urllib.request

repo, ref, token_path, root = sys.argv[1:]
token = pathlib.Path(token_path).read_text(encoding="utf-8").strip()
if not token:
    raise SystemExit("diagnostics token is empty")

files = {
    "agent/ccops_agent.py": 0o700,
    "agent/ccops_broker.py": 0o700,
    "install/install-ops.sh": 0o700,
}

owner, name = repo.split("/", 1)
for rel, mode in files.items():
    encoded = "/".join(urllib.parse.quote(part, safe="") for part in rel.split("/"))
    url = (
        "https://api.github.com/repos/"
        f"{urllib.parse.quote(owner, safe='')}/{urllib.parse.quote(name, safe='')}"
        f"/contents/{encoded}?ref={urllib.parse.quote(ref, safe='')}"
    )
    request = urllib.request.Request(
        url,
        headers={
            "Accept": "application/vnd.github+json",
            "Authorization": f"Bearer {token}",
            "User-Agent": "control-center-ops-bootstrap/1.0",
            "X-GitHub-Api-Version": "2022-11-28",
        },
    )
    try:
        with urllib.request.urlopen(request, timeout=20) as response:
            payload = json.loads(response.read().decode("utf-8"))
    except urllib.error.HTTPError as exc:
        raise SystemExit(f"GitHub fetch failed for {rel}: HTTP {exc.code}") from exc
    if payload.get("type") != "file" or not isinstance(payload.get("content"), str):
        raise SystemExit(f"unexpected GitHub response for {rel}")
    raw = base64.b64decode(payload["content"], validate=False)
    if not raw or len(raw) > 512 * 1024:
        raise SystemExit(f"invalid source size for {rel}")
    target = pathlib.Path(root, rel)
    target.write_bytes(raw)
    target.chmod(mode)
PY

python3 -m py_compile "$work/repo/agent/ccops_agent.py" "$work/repo/agent/ccops_broker.py"
bash -n "$work/repo/install/install-ops.sh"

bash "$work/repo/install/install-ops.sh"

systemctl is-enabled --quiet control-center-ops-agent.timer \
  || fail "ops timer is not enabled after installation"
systemctl is-active --quiet control-center-ops-agent.timer \
  || fail "ops timer is not active after installation"

printf 'OPS_AGENT_BOOTSTRAP=PASSED\n'
printf 'DIAGNOSTICS_REF=%s\n' "$DIAGNOSTICS_REF"
printf 'ROOT_BOUNDARY=TYPED_BROKER\n'
printf 'ARBITRARY_SHELL=DISABLED\n'
