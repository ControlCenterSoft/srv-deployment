#!/usr/bin/env bash
set -Eeuo pipefail

PROJECT="${1:-/opt/srv-control}"
REMOTE_SHA="${2:-unknown}"
RELEASE_ID="1.3.0"
RELEASE_VERSION="1.3.0"
RELEASE_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_ROOT="$(cd -- "${RELEASE_DIR}/../.." && pwd -P)"
PAYLOAD="${RELEASE_DIR}/payload"
SYSTEM="${RELEASE_DIR}/system"
RELOAD_HELPER="${REPO_ROOT}/deploy/reload-srv-control.sh"

fail() { printf 'PREFLIGHT FAIL: %s\n' "$*" >&2; exit 1; }

[[ "$(id -u)" -eq 0 ]] || fail "must run as root"
[[ -d "$PROJECT" ]] || fail "project directory missing: $PROJECT"
[[ -x "$PROJECT/venv/bin/python" ]] || fail "project virtualenv missing"
[[ -x "$RELOAD_HELPER" ]] || fail "graceful reload helper missing"
systemctl is-active --quiet srv-control.service || fail "srv-control.service is not active"
systemctl is-active --quiet postgresql.service || fail "postgresql.service is not active"

for command in python3 systemctl sha256sum git flock apt-get nginx getent id runuser tar findmnt; do
    command -v "$command" >/dev/null 2>&1 || fail "required command missing: $command"
done

for rel in app migrations static templates alembic.ini requirements.lock; do
    [[ -e "$PAYLOAD/$rel" ]] || fail "release payload missing: $rel"
done

required_payload=(
    app/core/system_auth.py app/core/rbac.py app/core/system_admin.py
    app/core/samba_domain.py app/core/samba_shares.py
    app/core/minecraft.py app/core/minecraft_instances.py
    app/routers/admin.py app/routers/api.py app/routers/ui.py
    app/routers/minecraft_multi.py app/routers/share_directory.py
    migrations/versions/13f0a1300001_shares_rbac.py
    templates/samba.html templates/shares.html templates/minecraft.html templates/shell.html
    static/js/samba.js static/js/shares.js static/js/minecraft.js static/js/shell.js
)
for rel in "${required_payload[@]}"; do
    [[ -s "$PAYLOAD/$rel" ]] || fail "required 1.3.0 payload file missing: $rel"
done

required_helpers=(
    srv-control-system-agent srv-control-backup srv-control-os-auto-update
    srv-control-samba-admin srv-control-samba-agent srv-control-samba-ldif-editor
    srv-control-samba-monitor srv-control-samba-shares-monitor
    srv-control-minecraft-admin srv-control-minecraft-admin-core
    srv-control-minecraft-agent srv-control-minecraft-auto-update
    srv-control-minecraft-firewall srv-control-minecraft-monitor
    srv-control-minecraft-player-admin srv-control-minecraft-runner
    srv-control-minecraft-update srvcc-configure-auto-updates
)
for helper in "${required_helpers[@]}"; do
    [[ -s "$SYSTEM/$helper" ]] || fail "required privileged helper missing: $helper"
done

required_units=(
    srv-control-system-agent.service srv-control-system-agent.path
    srv-control-os-update.service srv-control-adguard-monitor.service srv-control-adguard-monitor.timer
    srv-control-backup.service srv-control-backup.timer
    srv-control-os-auto-update.service srv-control-os-auto-update.timer
    srv-control-samba-agent.service srv-control-samba-agent.path
    srv-control-samba-monitor.service srv-control-samba-monitor.timer
    srv-control-samba-shares-monitor.service srv-control-samba-shares-monitor.timer
    srv-control-minecraft-agent.service srv-control-minecraft-agent.path
    srv-control-minecraft-auto-update.service srv-control-minecraft-auto-update.timer
    srv-control-minecraft-firewall.service
    srv-control-minecraft-monitor.service srv-control-minecraft-monitor.timer
)
for unit in "${required_units[@]}"; do
    [[ -s "$SYSTEM/$unit" ]] || fail "required systemd payload missing: $unit"
done

python3 - <<'PY'
import json, pathlib, re
path=pathlib.Path('/var/lib/srv-control/release.json')
payload=json.loads(path.read_text(encoding='utf-8'))
version=str(payload.get('version') or '')
match=re.match(r'^(\d+)\.(\d+)\.(\d+)(?:[-+].*)?$',version)
if not match:
    raise SystemExit(f'unsupported installed release version: {version!r}')
current=tuple(map(int,match.groups()))
if current < (1,2,0) or current > (1,3,0):
    raise SystemExit(f'release 1.3.0 supports upgrade from 1.2.0 and revalidation of 1.3.0; installed={version}')
PY

python3 -m compileall -q "$PAYLOAD/app"
python3 -m py_compile \
    "$SYSTEM/srv-control-system-agent" \
    "$SYSTEM/srv-control-backup" \
    "$SYSTEM/srv-control-os-auto-update" \
    "$SYSTEM/srv-control-samba-admin" \
    "$SYSTEM/srv-control-samba-agent" \
    "$SYSTEM/srv-control-samba-ldif-editor" \
    "$SYSTEM/srv-control-samba-monitor" \
    "$SYSTEM/srv-control-samba-shares-monitor" \
    "$SYSTEM/srv-control-minecraft-admin" \
    "$SYSTEM/srv-control-minecraft-admin-core" \
    "$SYSTEM/srv-control-minecraft-agent" \
    "$SYSTEM/srv-control-minecraft-auto-update" \
    "$SYSTEM/srv-control-minecraft-firewall" \
    "$SYSTEM/srv-control-minecraft-monitor" \
    "$SYSTEM/srv-control-minecraft-player-admin" \
    "$SYSTEM/srv-control-minecraft-runner" \
    "$SYSTEM/srv-control-minecraft-update"
bash -n "$SYSTEM/install-auth.sh"
bash -n "$SYSTEM/srvcc-configure-auto-updates"

# Release/UI/RBAC contract.
grep -Fq '"shares": "Общий / сетевой доступ"' "$PAYLOAD/app/core/rbac.py" || fail "shares RBAC module missing"
grep -Fq 'Домен Samba' "$PAYLOAD/templates/shell.html" || fail "Samba menu entry missing"
grep -Fq 'Общий' "$PAYLOAD/templates/shell.html" || fail "shares menu entry missing"
grep -Fq '/samba/backups/import' "$PAYLOAD/app/routers/admin.py" || fail "domain restore upload API missing"
grep -Fq 'samba-tool", "domain", "backup", "restore"' "$SYSTEM/srv-control-samba-admin" || fail "supported Samba domain restore implementation missing"
grep -Fq 'testparm' "$SYSTEM/srv-control-samba-admin" || fail "Samba config validation missing"
grep -Fq 'minecraft-update-apply' "$PAYLOAD/app/core/system_admin.py" || fail "Minecraft update action missing"
grep -Fq 'minecraft-player-kick' "$PAYLOAD/app/core/system_admin.py" || fail "Minecraft player administration missing"

if grep -R -n -i -E 'пока не работает|будет реализовано|future release only|будет включено' "$PAYLOAD/templates" "$PAYLOAD/static" >/dev/null 2>&1; then
    fail "temporary placeholder text found in user interface"
fi

exec_start="$(systemctl show srv-control.service -p ExecStart --value 2>/dev/null || true)"
[[ "$exec_start" == *"--workers 2"* ]] || fail "multi-worker srv-control service is required"

printf 'PREFLIGHT PASS: release=%s sha=%s\n' "$RELEASE_VERSION" "$REMOTE_SHA"
