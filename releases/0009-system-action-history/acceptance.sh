#!/usr/bin/env bash
set -Eeuo pipefail

PROJECT="${1:-/opt/srv-control}"
REMOTE_SHA="${2:-unknown}"
RELEASE_ID="0009-system-action-history"
RELEASE_VERSION="0.9.0"
BACKUP_DIR="/var/lib/srv-deployment/backups/${REMOTE_SHA}-${RELEASE_ID}"

fail() {
    printf 'ACCEPTANCE FAIL: %s\n' "$*" >&2
    exit 1
}

systemctl is-active --quiet srv-control.service \
    || fail "srv-control.service is not active"
systemctl is-active --quiet srv-control-system-agent.path \
    || fail "privileged system action path unit is not active"

before_pid="$(cat "$BACKUP_DIR/main-pid.before" 2>/dev/null || true)"
after_pid="$(systemctl show srv-control.service -p MainPID --value)"
[[ -n "$before_pid" && "$before_pid" == "$after_pid" ]] \
    || fail "Uvicorn manager PID changed; graceful reload invariant failed"

python3 - "$RELEASE_VERSION" "$REMOTE_SHA" <<'PY'
import json
import sys
import urllib.request

version = sys.argv[1]
sha = sys.argv[2]
base = "http://127.0.0.1:8876"

def get(path):
    with urllib.request.urlopen(base + path, timeout=8) as response:
        return json.load(response)

health = get("/api/v1/health")
release = health.get("data", {}).get("release", {})
assert health.get("ok") is True, health
assert release.get("version") == version, release
assert release.get("git_sha") == sha, release

admin = get("/api/v1/system/admin")
assert admin.get("ok") is True, admin
data = admin.get("data", {})
actions = data.get("actions")
assert isinstance(actions, dict), data
assert isinstance(actions.get("queued_count"), int), actions
assert isinstance(actions.get("queued"), list), actions
assert isinstance(actions.get("history"), list), actions
assert len(actions["history"]) <= 12, actions

for item in actions["history"]:
    assert "request_id" in item, item
    assert "result" in item, item
    assert "detail" in item, item

page = urllib.request.urlopen(base + "/ui/module/system", timeout=8).read().decode(
    "utf-8", "replace"
)
for marker in (
    'id="systemActionHistory"',
    'id="systemActionQueueCount"',
    'id="rebootButton"',
    'id="managedServices"',
):
    assert marker in page, marker

print(json.dumps(
    {
        "release": release,
        "action_history": True,
        "graceful_manager_pid": True,
        "history_count": len(actions["history"]),
        "queued_count": actions["queued_count"],
    },
    ensure_ascii=False,
))
PY

printf 'ACCEPTANCE PASS: release=%s sha=%s\n' "$RELEASE_VERSION" "$REMOTE_SHA"
