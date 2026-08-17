#!/usr/bin/env bash
set -Eeuo pipefail

PROJECT="${1:-/opt/srv-control}"
REMOTE_SHA="${2:-unknown}"
RELEASE_ID="1.0.0"
RELEASE_VERSION="1.0.0"
BACKUP_DIR="/var/lib/srv-deployment/backups/${REMOTE_SHA}-${RELEASE_ID}"

fail() {
    printf 'ACCEPTANCE FAIL: %s\n' "$*" >&2
    exit 1
}

systemctl is-active --quiet srv-control.service \
    || fail "srv-control.service is not active"
systemctl is-active --quiet srv-control-system-agent.path \
    || fail "system action path is not active"
systemctl is-active --quiet srv-control-adguard-monitor.timer \
    || fail "AdGuard monitor timer is not active"
systemctl is-active --quiet srvcc-github-agent.timer \
    || fail "GitHub updater timer is not active"

[[ -x /usr/local/sbin/srvcc-github-agent ]] \
    || fail "GitHub updater binary missing"
[[ -x /usr/local/sbin/srvcc-configure-auto-updates ]] \
    || fail "GitHub updater configurator missing"
[[ -s /var/lib/srv-control/github-update-config.json ]] \
    || fail "GitHub update configuration missing"

before_pid="$(cat "$BACKUP_DIR/main-pid.before" 2>/dev/null || true)"
after_pid="$(systemctl show srv-control.service -p MainPID --value)"
[[ -n "$before_pid" && "$before_pid" == "$after_pid" ]] \
    || fail "Uvicorn manager PID changed; graceful reload invariant failed"

python3 - "$RELEASE_VERSION" "$REMOTE_SHA" <<'PY'
import json
import sys
import urllib.request

version, sha = sys.argv[1], sys.argv[2]
base = "http://127.0.0.1:8876"

def get(path):
    with urllib.request.urlopen(base + path, timeout=8) as response:
        return json.load(response)

health = get("/api/v1/health")
release = health.get("data", {}).get("release", {})
assert health.get("ok") is True, health
assert release.get("version") == version, release
assert release.get("release_id") == "1.0.0", release
assert release.get("git_sha") == sha, release
assert release.get("synced_at"), release

metrics = get("/api/v1/dashboard/metrics")
assert metrics.get("ok") is True, metrics

overview = get("/api/v1/network/overview")
assert overview.get("ok") is True, overview

diagnostics = get("/api/v1/network/diagnostics")
assert diagnostics.get("ok") is True, diagnostics

capabilities = get("/api/v1/network/capabilities")
assert capabilities.get("ok") is True, capabilities

admin = get("/api/v1/system/admin")
assert admin.get("ok") is True, admin

auth = get("/api/v1/auth/status")
assert auth.get("ok") is True, auth

page = urllib.request.urlopen(
    base + "/ui/module/system",
    timeout=8,
).read().decode("utf-8", "replace")
for marker in (
    'id="rebootButton"',
    'id="managedServices"',
    'id="systemActionPanel"',
):
    assert marker in page, marker

with open("/var/lib/srv-control/github-update-config.json", encoding="utf-8") as handle:
    config = json.load(handle)
assert config.get("mode") == "automatic", config
assert int(config.get("interval_minutes", 0)) == 5, config
assert config.get("source") == "https://github.com/filosoff31/srv-deployment.git", config

print(json.dumps(
    {
        "release": release,
        "dashboard": True,
        "network_overview": True,
        "network_diagnostics": True,
        "network_planner_capabilities": True,
        "system_admin": True,
        "auth_status": True,
        "automatic_updates": config,
        "graceful_manager_pid": True,
    },
    ensure_ascii=False,
))
PY

bash -n /usr/local/sbin/srvcc-github-agent
bash -n /usr/local/sbin/srvcc-configure-auto-updates

printf 'ACCEPTANCE PASS: release=%s sha=%s\n' "$RELEASE_VERSION" "$REMOTE_SHA"
