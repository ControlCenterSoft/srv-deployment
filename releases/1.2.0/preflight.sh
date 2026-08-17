#!/usr/bin/env bash
set -Eeuo pipefail

PROJECT="${1:-/opt/srv-control}"
REMOTE_SHA="${2:-unknown}"
RELEASE_ID="1.2.0"
RELEASE_VERSION="1.2.0"
RELEASE_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_ROOT="$(cd -- "${RELEASE_DIR}/../.." && pwd -P)"
PAYLOAD="${RELEASE_DIR}/payload"
SYSTEM="${RELEASE_DIR}/system"
RELOAD_HELPER="${REPO_ROOT}/deploy/reload-srv-control.sh"

fail() {
    printf 'PREFLIGHT FAIL: %s\n' "$*" >&2
    exit 1
}

[[ "$(id -u)" -eq 0 ]] || fail "must run as root"
[[ -d "$PROJECT" ]] || fail "project directory missing: $PROJECT"
[[ -x "$PROJECT/venv/bin/python" ]] || fail "project virtualenv missing"
[[ -x "$RELOAD_HELPER" ]] || fail "graceful reload helper missing"
systemctl is-active --quiet srv-control.service || fail "srv-control.service is not active"
systemctl is-active --quiet postgresql.service || fail "postgresql.service is not active"

for command in python3 systemctl sha256sum git flock apt-get nginx getent id runuser; do
    command -v "$command" >/dev/null 2>&1 || fail "required command missing: $command"
done

for rel in app migrations static templates alembic.ini requirements.lock; do
    [[ -e "$PAYLOAD/$rel" ]] || fail "release payload missing: $rel"
done

for file in \
    "$PAYLOAD/app/core/system_auth.py" \
    "$PAYLOAD/app/core/rbac.py" \
    "$PAYLOAD/app/core/identity_directory.py" \
    "$PAYLOAD/app/core/system_admin.py" \
    "$PAYLOAD/app/core/metrics.py" \
    "$PAYLOAD/app/core/minecraft.py" \
    "$PAYLOAD/app/routers/admin.py" \
    "$PAYLOAD/app/routers/api.py" \
    "$PAYLOAD/app/routers/ui.py" \
    "$PAYLOAD/migrations/versions/11f0a1100001_system_auth_rbac.py" \
    "$PAYLOAD/migrations/versions/11f0a1100002_user_rbac_subjects.py" \
    "$PAYLOAD/migrations/versions/12f0a1200001_full_admin_role.py" \
    "$PAYLOAD/templates/dashboard.html" \
    "$PAYLOAD/templates/access.html" \
    "$PAYLOAD/templates/system.html" \
    "$PAYLOAD/templates/services.html" \
    "$PAYLOAD/templates/adguard.html" \
    "$PAYLOAD/templates/minecraft.html" \
    "$PAYLOAD/templates/torrents.html" \
    "$PAYLOAD/static/js/dashboard.js" \
    "$PAYLOAD/static/js/access.js" \
    "$PAYLOAD/static/js/adguard.js" \
    "$PAYLOAD/static/js/minecraft.js" \
    "$PAYLOAD/static/css/dashboard-1.2.css" \
    "$PAYLOAD/static/css/service-config-1.2.css" \
    "$SYSTEM/install-auth.sh" \
    "$SYSTEM/srv-control-system-agent" \
    "$SYSTEM/srv-control-backup" \
    "$SYSTEM/srv-control-os-auto-update" \
    "$SYSTEM/srvcc-configure-auto-updates"
do
    [[ -s "$file" ]] || fail "required release file missing: $file"
done

[[ ! -e "$PAYLOAD/templates/placeholder.html" ]] \
    || fail "placeholder template must not be shipped in release 1.2.0"

for unit in \
    srv-control-system-agent.service \
    srv-control-system-agent.path \
    srv-control-os-update.service \
    srv-control-adguard-monitor.service \
    srv-control-adguard-monitor.timer \
    srv-control-backup.service \
    srv-control-backup.timer \
    srv-control-os-auto-update.service \
    srv-control-os-auto-update.timer
do
    [[ -s "$SYSTEM/$unit" ]] || fail "systemd payload missing: $unit"
done

python3 - <<'PY'
import json
import pathlib
import re

path = pathlib.Path("/var/lib/srv-control/release.json")
payload = json.loads(path.read_text(encoding="utf-8"))
version = str(payload.get("version") or "")
match = re.match(r"^(\d+)\.(\d+)\.(\d+)(?:[-+].*)?$", version)
if not match:
    raise SystemExit(f"unsupported installed release version: {version!r}")
current = tuple(map(int, match.groups()))
if current < (1, 1, 0) or current > (1, 2, 0):
    raise SystemExit(
        f"release 1.2.0 supports upgrade from 1.1.0 and revalidation of 1.2.0; installed={version}"
    )
PY

python3 -m compileall -q "$PAYLOAD/app"
python3 -m py_compile \
    "$SYSTEM/srv-control-system-agent" \
    "$SYSTEM/srv-control-backup" \
    "$SYSTEM/srv-control-os-auto-update"
bash -n "$SYSTEM/install-auth.sh"
bash -n "$SYSTEM/srvcc-configure-auto-updates"

if grep -R -n -E 'change_password|password_hash|admin-bootstrap' "$PAYLOAD/app" >/dev/null 2>&1; then
    fail "private Control Center credential implementation remains in application payload"
fi

if grep -R -n -i -E \
    'пока не работает|будет реализовано|недоступно потому|заблокировано в|следующего этапа|future release|future release only|будет включено' \
    "$PAYLOAD/templates" "$PAYLOAD/static" >/dev/null 2>&1
then
    fail "temporary placeholder text found in user interface"
fi

grep -Fq 'Minecraft' "$PAYLOAD/templates/shell.html" || fail "Minecraft menu entry missing"
grep -Fq 'Полный администратор' "$PAYLOAD/templates/access.html" || fail "full administrator role missing"
grep -Fq 'Топ 3 по CPU' "$PAYLOAD/templates/dashboard.html" || fail "CPU process widget missing"
grep -Fq 'Топ 3 по RAM' "$PAYLOAD/templates/dashboard.html" || fail "RAM process widget missing"
grep -Fq 'adguardConfigForm' "$PAYLOAD/templates/adguard.html" || fail "AdGuard config form missing"
grep -Fq 'minecraftConfigForm' "$PAYLOAD/templates/minecraft.html" || fail "Minecraft config form missing"
grep -Fq 'id="rebootButton"' "$PAYLOAD/templates/system.html" || fail "compact reboot control missing"
grep -Fq 'id="backupRows"' "$PAYLOAD/templates/system.html" || fail "backup list missing"

exec_start="$(systemctl show srv-control.service -p ExecStart --value 2>/dev/null || true)"
[[ "$exec_start" == *"--workers 2"* ]] || fail "multi-worker srv-control service is required"

printf 'PREFLIGHT PASS: release=%s sha=%s\n' "$RELEASE_VERSION" "$REMOTE_SHA"
