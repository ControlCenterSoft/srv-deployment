#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

DIAG_REPO="ControlCenterSoft/control-center-server-diagnostics"
DIAG_COMMIT="94aad6b079ec9a7dff52e6187bed5f551f59672e"
TOKEN_FILE="/etc/control-center-diagnostics-agent/github-token"
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
command -v python3 >/dev/null 2>&1 || fail "python3 is required"
command -v bash >/dev/null 2>&1 || fail "bash is required"

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
    "agent/ccops_agent.py": ("agent/ccops_agent.py", "c89d93c95f42bc2de3fc07060061ede1e6aec4cd"),
    "agent/ccops_broker.py": ("agent/ccops_broker.py", "dcbeb90b5e78e2c77545a2a56468cd86e8a7327e"),
    "install/install-ops.sh": ("install/install-ops.sh", "dba4843538747e2523990903a36ce011eea93335"),
}

owner, name = repo.split("/", 1)
headers = {
    "Accept": "application/vnd.github+json",
    "Authorization": f"Bearer {token}",
    "User-Agent": "control-center-ops-bootstrap/1.1",
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
    content = base64.b64decode(encoded_content, validate=False)
    target = work / destination
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_bytes(content)

# Do not persist or print the token. The child installer reuses the original
# root-protected token file already present on the server.
del token
PY

chmod 0755 "$WORK/agent/ccops_agent.py" "$WORK/agent/ccops_broker.py" "$WORK/install/install-ops.sh"
python3 -m py_compile "$WORK/agent/ccops_agent.py" "$WORK/agent/ccops_broker.py"
bash -n "$WORK/install/install-ops.sh"

bash "$WORK/install/install-ops.sh"

systemctl is-enabled --quiet control-center-ops-agent.timer \
  || fail "ops timer is not enabled after installation"
systemctl start control-center-ops-agent.service \
  || fail "ops agent first post-install run failed"

printf 'CONTROL_CENTER_OPS_BOOTSTRAP=PASSED\n'
printf 'DIAGNOSTICS_SOURCE_COMMIT=%s\n' "$DIAG_COMMIT"
printf 'TOKEN_REUSED=existing-diagnostics-token\n'
printf 'ROOT_BOUNDARY=typed-broker\n'
printf 'ARBITRARY_SHELL=disabled\n'
