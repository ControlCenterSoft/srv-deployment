#!/usr/bin/env bash
set -Eeuo pipefail

PROJECT="${1:-/opt/srv-control}"
REMOTE_SHA="${2:-unknown}"
RELEASE_ID="1.2.0"
RELEASE_VERSION="1.2.0"
BACKUP_DIR="/var/lib/srv-deployment/backups/${REMOTE_SHA}-${RELEASE_ID}"
STATE_DIR="/var/lib/srv-control"

fail() {
    printf 'ACCEPTANCE FAIL: %s\n' "$*" >&2
    exit 1
}

systemctl is-active --quiet srv-control.service || fail "srv-control.service is not active"
systemctl is-active --quiet srv-control-system-agent.path || fail "system action path is not active"
systemctl is-active --quiet srv-control-adguard-monitor.timer || fail "AdGuard monitor timer is not active"
[[ -x /usr/local/libexec/srv-control-backup ]] || fail "backup worker missing"
[[ -x /usr/local/sbin/srvcc-github-agent ]] || fail "GitHub updater missing"
[[ -x /usr/local/sbin/srvcc-configure-auto-updates ]] || fail "GitHub updater configurator missing"
[[ -s /etc/pam.d/srv-control ]] || fail "PAM service is missing"

before_pid="$(cat "$BACKUP_DIR/state/main-pid.before" 2>/dev/null || true)"
after_pid="$(systemctl show srv-control.service -p MainPID --value)"
[[ -n "$before_pid" && "$before_pid" == "$after_pid" ]] \
    || fail "Uvicorn manager PID changed; graceful reload invariant failed"

migration="$(runuser -u srv-control -- psql -d srv_control -Atc 'SELECT version_num FROM alembic_version LIMIT 1;')"
[[ "$migration" == "12f0a1200001" ]] || fail "unexpected database migration head: $migration"

runuser -u srv-control -- psql -d srv_control -Atc \
    "SELECT count(*) FROM rbac_group_permissions;" >/dev/null \
    || fail "RBAC table unavailable"

nginx -t >/dev/null 2>&1 || fail "nginx configuration is invalid"

runuser -u srv-control -- env \
    PYTHONPATH="$PROJECT" \
    PYTHONDONTWRITEBYTECODE=1 \
    "$PROJECT/venv/bin/python" - "$REMOTE_SHA" <<'PY'
from __future__ import annotations

import http.client
import json
import sys

from app.core.minecraft import snapshot as minecraft_snapshot
from app.core.rbac import (
    FULL_ADMIN_PERMISSION_KEY,
    MODULES,
    delete_grant,
    has_permission,
    is_full_admin,
    permissions_for,
    upsert_grant,
)
from app.core.system_auth import (
    COOKIE_NAME,
    Identity,
    _elevate_rbac_admin,
    create_session,
    resolve_identity,
)

expected_sha = sys.argv[1]
host = "127.0.0.1"
port = 8876


def request(path: str, *, cookie: str | None = None):
    connection = http.client.HTTPConnection(host, port, timeout=10)
    headers = {}
    if cookie:
        headers["Cookie"] = cookie
    connection.request("GET", path, headers=headers)
    response = connection.getresponse()
    body = response.read()
    result = (response.status, dict(response.getheaders()), body)
    connection.close()
    return result


status, _, body = request("/api/v1/health")
assert status == 200, status
health = json.loads(body)
assert health.get("ok") is True, health
release = health.get("data", {}).get("release", {})
assert release.get("version") == "1.2.0", release
assert release.get("release_id") == "1.2.0", release
assert release.get("git_sha") == expected_sha, release

status, headers, _ = request("/")
assert status == 303 and headers.get("location") == "/login", (status, headers)
status, _, body = request("/api/v1/dashboard/metrics")
assert status == 401, (status, body)

root = resolve_identity("root", "local")
assert root is not None and root.is_admin and root.uid == 0, root
token, _ = create_session(root)
cookie = f"{COOKIE_NAME}={token}"

for path in (
    "/",
    "/ui/dashboard",
    "/ui/module/system",
    "/ui/module/access",
    "/ui/module/services",
    "/ui/module/adguard",
    "/ui/module/minecraft",
    "/ui/module/torrents",
    "/api/v1/dashboard/metrics",
    "/api/v1/system/configuration",
    "/api/v1/access/grants",
    "/api/v1/access/directory",
    "/api/v1/services",
    "/api/v1/adguard",
    "/api/v1/minecraft",
):
    status, _, body = request(path, cookie=cookie)
    assert status == 200, (path, status, body[:500])

status, _, body = request("/api/v1/dashboard/metrics", cookie=cookie)
metrics = json.loads(body).get("data", {})
processes = metrics.get("processes", {})
assert isinstance(processes.get("cpu_top"), list), processes
assert isinstance(processes.get("memory_top"), list), processes
assert len(processes["cpu_top"]) <= 3
assert len(processes["memory_top"]) <= 3

root_permissions = permissions_for(root)
assert root_permissions.get(FULL_ADMIN_PERMISSION_KEY) == "admin", root_permissions
for module in MODULES:
    assert root_permissions.get(module) == "write", (module, root_permissions)

identity = Identity(
    username="srvcc-acceptance-user",
    uid=65000,
    gid=65000,
    groups=("srvcc-acceptance-group",),
    auth_source="local",
    is_admin=False,
)
group_grant_id = None
user_grant_id = None
admin_grant_id = None
try:
    group_grant = upsert_grant(
        subject_type="group",
        subject_name="srvcc-acceptance-group",
        source="local",
        module="network",
        access="read",
        actor="acceptance",
    )
    group_grant_id = int(group_grant["id"])
    assert has_permission(identity, "network", "read") is True
    assert has_permission(identity, "network", "write") is False

    user_grant = upsert_grant(
        subject_type="user",
        subject_name=identity.username,
        source="local",
        module="network",
        access="write",
        actor="acceptance",
    )
    user_grant_id = int(user_grant["id"])
    assert has_permission(identity, "network", "read") is True
    assert has_permission(identity, "network", "write") is True
    assert has_permission(identity, "minecraft", "write") is False
    assert is_full_admin(identity) is False

    admin_grant = upsert_grant(
        subject_type="user",
        subject_name=identity.username,
        source="local",
        module="network",
        access="admin",
        actor="acceptance",
    )
    admin_grant_id = int(admin_grant["id"])
    assert admin_grant.get("module") == "*", admin_grant
    assert admin_grant.get("access") == "admin", admin_grant
    assert is_full_admin(identity) is True
    elevated = _elevate_rbac_admin(identity)
    assert elevated.is_admin is True, elevated
    elevated_permissions = permissions_for(elevated)
    assert elevated_permissions.get(FULL_ADMIN_PERMISSION_KEY) == "admin"
    for module in MODULES:
        assert has_permission(elevated, module, "write") is True
finally:
    for grant_id in (admin_grant_id, user_grant_id, group_grant_id):
        if grant_id is not None:
            delete_grant(grant_id)

minecraft = minecraft_snapshot()
assert isinstance(minecraft, dict), minecraft
assert "installed" in minecraft and "properties" in minecraft, minecraft

print(json.dumps({
    "release": release,
    "dashboard_processes": True,
    "direct_user_write": True,
    "full_admin": True,
    "minecraft": True,
}, ensure_ascii=False))
PY

smoke_backup_id=""
cleanup_smoke() {
    if [[ -n "$smoke_backup_id" ]]; then
        /usr/local/libexec/srv-control-backup delete "$smoke_backup_id" >/dev/null 2>&1 || true
    fi
}
trap cleanup_smoke EXIT

backup_json="$(/usr/local/libexec/srv-control-backup create --actor acceptance --reason acceptance-1.2.0-smoke)"
smoke_backup_id="$(python3 -c 'import json,sys; print(json.loads(sys.stdin.read())["id"])' <<< "$backup_json")"
[[ -n "$smoke_backup_id" ]] || fail "backup smoke did not return an id"
archive="$STATE_DIR/backups/${smoke_backup_id}.tar.gz"
[[ -s "$archive" ]] || fail "backup smoke archive missing"
tar -tzf "$archive" >/dev/null || fail "backup archive is not readable"
/usr/local/libexec/srv-control-backup delete "$smoke_backup_id" >/dev/null
smoke_backup_id=""

if grep -R -n -E 'пока не работает|будет реализовано|недоступно потому' \
    "$PROJECT/templates" "$PROJECT/static" >/dev/null 2>&1
then
    fail "temporary placeholder text found in installed UI"
fi

printf 'ACCEPTANCE PASS: release=%s sha=%s\n' "$RELEASE_VERSION" "$REMOTE_SHA"
