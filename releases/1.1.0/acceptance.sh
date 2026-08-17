#!/usr/bin/env bash
set -Eeuo pipefail

PROJECT="${1:-/opt/srv-control}"
REMOTE_SHA="${2:-unknown}"
RELEASE_ID="1.1.0"
RELEASE_VERSION="1.1.0"
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
command -v pamtester >/dev/null 2>&1 || fail "pamtester is missing"
[[ ! -e "$STATE_DIR/auth.json" ]] || fail "private Control Center auth.json still exists"
[[ ! -e "$STATE_DIR/admin-bootstrap.txt" ]] || fail "private bootstrap credential still exists"

before_pid="$(cat "$BACKUP_DIR/state/main-pid.before" 2>/dev/null || true)"
after_pid="$(systemctl show srv-control.service -p MainPID --value)"
[[ -n "$before_pid" && "$before_pid" == "$after_pid" ]] \
    || fail "Uvicorn manager PID changed; graceful reload invariant failed"

migration="$(
    runuser -u srv-control -- psql -d srv_control -Atc \
        "SELECT version_num FROM alembic_version LIMIT 1;"
)"
[[ "$migration" == "11f0a1100002" ]] \
    || fail "unexpected database migration head: $migration"

runuser -u srv-control -- psql -d srv_control -Atc \
    "SELECT count(*) FROM rbac_group_permissions;" >/dev/null \
    || fail "RBAC table unavailable"

subject_type_column="$(
    runuser -u srv-control -- psql -d srv_control -Atc \
        "SELECT count(*) FROM information_schema.columns WHERE table_name='rbac_group_permissions' AND column_name='subject_type';"
)"
[[ "$subject_type_column" == "1" ]] || fail "RBAC subject_type column unavailable"

nginx -t >/dev/null 2>&1 || fail "nginx configuration is invalid"

if command -v testparm >/dev/null 2>&1; then
    role="$(testparm -s --parameter-name='server role' 2>/dev/null | tr '[:upper:]' '[:lower:]' | xargs || true)"
    if [[ "$role" == *"active directory domain controller"* ]]; then
        [[ -s "$STATE_DIR/http.keytab" ]] || fail "AD DC detected but HTTP SSO keytab is missing"
        command -v klist >/dev/null 2>&1 || fail "klist is missing"
        klist -k "$STATE_DIR/http.keytab" 2>/dev/null | grep -Fq 'HTTP/' \
            || fail "HTTP principal missing from SSO keytab"
        nginx -T 2>/dev/null | grep -Fq 'auth_gss on;' \
            || fail "nginx SPNEGO location is not active"
    fi
fi

# The application database uses PostgreSQL peer authentication for role
# srv-control. Run application-level acceptance checks as the same Unix user;
# running this block as root causes a valid peer-auth rejection.
runuser -u srv-control -- env \
    PYTHONPATH="$PROJECT" \
    PYTHONDONTWRITEBYTECODE=1 \
    "$PROJECT/venv/bin/python" - "$REMOTE_SHA" <<'PY'
from __future__ import annotations

import http.client
import json
import sys

from app.core.rbac import (
    MODULES,
    delete_grant,
    has_permission,
    upsert_grant,
)
from app.core.system_auth import COOKIE_NAME, Identity, create_session, resolve_identity

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
assert release.get("version") == "1.1.0", release
assert release.get("release_id") == "1.1.0", release
assert release.get("git_sha") == expected_sha, release

status, headers, _ = request("/")
assert status == 303, status
assert headers.get("location") == "/login", headers

status, _, _ = request("/ui/module/system")
assert status == 303, status

status, _, body = request("/api/v1/dashboard/metrics")
assert status == 401, (status, body)

root = resolve_identity("root", "local")
assert root is not None and root.is_admin and root.uid == 0, root
token, csrf = create_session(root)
cookie = f"{COOKIE_NAME}={token}"

for path in (
    "/",
    "/ui/dashboard",
    "/ui/module/system",
    "/ui/module/access",
    "/ui/module/services",
    "/ui/module/adguard",
    "/ui/module/torrents",
    "/api/v1/dashboard/metrics",
    "/api/v1/system/configuration",
    "/api/v1/access/grants",
    "/api/v1/access/directory",
    "/api/v1/services",
):
    status, _, body = request(path, cookie=cookie)
    assert status == 200, (path, status, body[:400])

admin_permissions = {module: "write" for module in MODULES}
from app.core.rbac import permissions_for
assert permissions_for(root) == admin_permissions

group = "srvcc-acceptance-temporary"
group_grant_id = None
user_grant_id = None
try:
    grant = upsert_grant(
        group_name=group,
        source="local",
        module="network",
        access="read",
        actor="acceptance",
    )
    group_grant_id = int(grant["id"])
    identity = Identity(
        username="acceptance",
        uid=65000,
        gid=65000,
        groups=(group,),
        auth_source="local",
        is_admin=False,
    )
    assert has_permission(identity, "network", "read") is True
    assert has_permission(identity, "network", "write") is False
    grant = upsert_grant(
        group_name=group,
        source="local",
        module="network",
        access="write",
        actor="acceptance",
    )
    group_grant_id = int(grant["id"])
    assert has_permission(identity, "network", "read") is True
    assert has_permission(identity, "network", "write") is True

    user_grant = upsert_grant(
        subject_type="user",
        subject_name="acceptance",
        source="local",
        module="downloads",
        access="read",
        actor="acceptance",
    )
    user_grant_id = int(user_grant["id"])
    assert user_grant.get("subject_type") == "user", user_grant
    assert has_permission(identity, "downloads", "read") is True
    assert has_permission(identity, "downloads", "write") is False
    user_grant = upsert_grant(
        subject_type="user",
        subject_name="acceptance",
        source="local",
        module="downloads",
        access="write",
        actor="acceptance",
    )
    user_grant_id = int(user_grant["id"])
    assert has_permission(identity, "downloads", "write") is True
finally:
    if user_grant_id is not None:
        delete_grant(user_grant_id)
    if group_grant_id is not None:
        delete_grant(group_grant_id)

print(json.dumps({"release": release, "auth_gate": True, "rbac_group": True, "rbac_user": True}, ensure_ascii=False))
PY

smoke_backup_id=""
smoke_database=""
smoke_tmp=""

cleanup_smoke() {
    if [[ -n "$smoke_database" ]]; then
        runuser -u postgres -- dropdb --if-exists "$smoke_database" >/dev/null 2>&1 || true
    fi
    if [[ -n "$smoke_backup_id" ]]; then
        /usr/local/libexec/srv-control-backup delete "$smoke_backup_id" >/dev/null 2>&1 || true
    fi
    if [[ -n "$smoke_tmp" ]]; then
        rm -rf "$smoke_tmp"
    fi
}
trap cleanup_smoke EXIT

backup_json="$(
    /usr/local/libexec/srv-control-backup \
        create \
        --actor acceptance \
        --reason acceptance-smoke
)"
smoke_backup_id="$(
    python3 -c 'import json,sys; print(json.loads(sys.stdin.read())["id"])' \
        <<< "$backup_json"
)"
[[ -n "$smoke_backup_id" ]] || fail "backup smoke did not return an id"
archive="$STATE_DIR/backups/${smoke_backup_id}.tar.gz"
[[ -s "$archive" ]] || fail "backup smoke archive missing"
tar -tzf "$archive" >/dev/null || fail "backup archive is not readable"

smoke_tmp="$(mktemp -d /var/tmp/srvcc-acceptance-restore.XXXXXX)"
chgrp srv-control "$smoke_tmp"
chmod 0750 "$smoke_tmp"
tar -xzf "$archive" -C "$smoke_tmp"
dump="$smoke_tmp/content/srv_control.dump"
[[ -s "$dump" ]] || fail "database dump missing from backup archive"
chown srv-control:srv-control "$dump"
chmod 0640 "$dump"
runuser -u srv-control -- pg_restore --list "$dump" >/dev/null \
    || fail "database dump catalog validation failed"

smoke_database="srvcc_accept_${$}_${RANDOM}"
runuser -u postgres -- createdb --owner=srv-control "$smoke_database"
runuser -u srv-control -- pg_restore \
    --no-owner \
    -d "$smoke_database" \
    "$dump" >/dev/null \
    || fail "database restore smoke failed"
table_count="$(
    runuser -u srv-control -- psql -d "$smoke_database" -Atc \
        "SELECT count(*) FROM information_schema.tables WHERE table_schema='public';"
)"
[[ "$table_count" =~ ^[0-9]+$ && "$table_count" -gt 0 ]] \
    || fail "restored smoke database contains no public tables"
runuser -u postgres -- dropdb "$smoke_database"
smoke_database=""
/usr/local/libexec/srv-control-backup delete "$smoke_backup_id" >/dev/null
smoke_backup_id=""
rm -rf "$smoke_tmp"
smoke_tmp=""

# Do not invoke srvcc-github-agent from inside acceptance. The outer updater
# owns update.lock for the whole deployment transaction and records the final
# fingerprint/status only after acceptance and healthcheck succeed.

if grep -R -n -E 'пока не работает|будет реализовано|недоступно потому' \
    "$PROJECT/templates" "$PROJECT/static" >/dev/null 2>&1
then
    fail "temporary placeholder text found in installed UI"
fi

printf 'ACCEPTANCE PASS: release=%s sha=%s\n' "$RELEASE_VERSION" "$REMOTE_SHA"
