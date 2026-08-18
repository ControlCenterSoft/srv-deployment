#!/usr/bin/env bash
set -Eeuo pipefail
umask 027

PROJECT="${1:-/opt/srv-control}"
REMOTE_SHA="${2:-unknown}"
STATE_DIR="/var/lib/srv-control"
RELEASE_META="${STATE_DIR}/release.json"
UPDATE_CONFIG="${STATE_DIR}/github-update-config.json"
UPDATE_STATUS="${STATE_DIR}/github-update-status.json"
BACKUP_CONFIG="${STATE_DIR}/backup-config.json"
OS_CONFIG="${STATE_DIR}/os-update-config.json"

fail(){ printf 'ACCEPTANCE 2.0.0 FAIL: %s\n' "$*" >&2; exit 1; }

curl -fsS --max-time 15 http://127.0.0.1:8876/api/v1/health >/tmp/srvcc-2.0-health.json \
    || fail "Control Center health endpoint failed"

runuser -u srv-control -- python3 - "$RELEASE_META" "$REMOTE_SHA" <<'PY'
import json,pathlib,sys
p=json.loads(pathlib.Path(sys.argv[1]).read_text(encoding='utf-8'))
assert p.get('version') == '2.0.0',p
assert p.get('release_id') == '2.0.0',p
if sys.argv[2] != 'unknown': assert p.get('git_sha') == sys.argv[2],p
print('RELEASE METADATA PASS:',p.get('version'),p.get('git_sha'))
PY

python3 - /tmp/srvcc-2.0-health.json <<'PY'
import json,sys
p=json.load(open(sys.argv[1],encoding='utf-8'))
assert p.get('ok') is True,p
release=(p.get('data') or {}).get('release') or {}
assert release.get('version') == '2.0.0',release
print('HEALTH RELEASE PASS:',release.get('version'))
PY
rm -f /tmp/srvcc-2.0-health.json

[[ -s "$STATE_DIR/session.key" ]] || fail "session.key missing after deployment"
runuser -u srv-control -- test -r "$STATE_DIR/session.key" || fail "session.key unreadable by srv-control"

for file in \
    "$PROJECT/static/js/system-2.0.js" \
    "$PROJECT/static/js/github-update-timestamps.js" \
    "$PROJECT/templates/system.html" \
    "$PROJECT/app/routers/system_v2.py"
do [[ -s "$file" ]] || fail "2.0 application asset missing: $file"; done

grep -Fq 'Последняя проверка обновления' "$PROJECT/templates/system.html" \
    || fail "new last-check label missing"
grep -Fq 'Последнее успешное обновление' "$PROJECT/templates/system.html" \
    || fail "last-success label missing"
grep -Fq 'backupDeleteSelected' "$PROJECT/templates/system.html" \
    || fail "bulk backup controls missing"
grep -Fq '/api/v1/system/backups/delete-many' "$PROJECT/static/js/system-2.0.js" \
    || fail "bulk backup client endpoint missing"

runuser -u srv-control -- env PYTHONPATH="$PROJECT" PYTHONDONTWRITEBYTECODE=1 \
    "$PROJECT/venv/bin/python" - <<'PY'
from app.main import app
paths={route.path for route in app.routes}
assert '/api/v1/system/backups/delete-many' in paths, sorted(paths)
print('2.0 ROUTE PASS: bulk backup deletion registered')
PY

for helper in \
    /usr/local/sbin/srvcc-update-controller \
    /usr/local/sbin/srvcc-github-agent \
    /usr/local/sbin/srvcc-configure-auto-updates \
    /usr/local/libexec/srv-control-backup-policy \
    /usr/local/libexec/srv-control-minecraft-repair
do [[ -x "$helper" ]] || fail "2.0 helper missing: $helper"; done
python3 -m py_compile /usr/local/sbin/srvcc-update-controller /usr/local/libexec/srv-control-backup-policy /usr/local/libexec/srv-control-minecraft-repair

grep -Fq 'srvcc-update-controller' /usr/local/sbin/srvcc-github-agent \
    || fail "legacy GitHub agent compatibility wrapper does not use 2.0 controller"

python3 - "$UPDATE_CONFIG" "$UPDATE_STATUS" <<'PY'
import json,pathlib,sys
cfg=json.loads(pathlib.Path(sys.argv[1]).read_text(encoding='utf-8'))
assert cfg.get('schema_version') == 4,cfg
assert cfg.get('mode') in {'automatic','manual'},cfg
assert isinstance(cfg.get('interval_minutes'),int) and 1 <= cfg['interval_minutes'] <= 1440,cfg
status=json.loads(pathlib.Path(sys.argv[2]).read_text(encoding='utf-8'))
assert status.get('schema_version') == 4,status
assert status.get('last_check_at') or status.get('checked_at'),status
for key in ('last_update_attempt_at','last_successful_update_at'):
    assert key in status,status
print('UPDATE STATE PASS:',cfg.get('mode'),cfg.get('interval_minutes'),status.get('stage'))
PY

GH_MODE="$(python3 - "$UPDATE_CONFIG" <<'PY'
import json,pathlib,sys
print(json.loads(pathlib.Path(sys.argv[1]).read_text(encoding='utf-8')).get('mode','manual'))
PY
)"
if [[ "$GH_MODE" == "automatic" ]]; then
    systemctl is-enabled --quiet srvcc-github-agent.timer || fail "automatic GitHub timer is not enabled"
    systemctl is-active --quiet srvcc-github-agent.timer || fail "automatic GitHub timer is not active"
else
    ! systemctl is-enabled --quiet srvcc-github-agent.timer 2>/dev/null || fail "manual GitHub mode unexpectedly has enabled timer"
fi

python3 - "$BACKUP_CONFIG" <<'PY'
import json,pathlib,sys
try: p=json.loads(pathlib.Path(sys.argv[1]).read_text(encoding='utf-8'))
except FileNotFoundError: p={'scheduled':False,'backup_before_update':True}
assert isinstance(p.get('scheduled',False),bool),p
assert isinstance(p.get('backup_before_update',True),bool),p
print('BACKUP CONFIG PASS:',p.get('scheduled',False),p.get('backup_before_update',True))
PY

if python3 - "$BACKUP_CONFIG" <<'PY'
import json,pathlib,sys
try: p=json.loads(pathlib.Path(sys.argv[1]).read_text(encoding='utf-8'))
except FileNotFoundError: p={'backup_before_update':True}
raise SystemExit(0 if p.get('backup_before_update') is True else 1)
PY
then
    /usr/local/libexec/srv-control-backup-policy required-for-update \
        || fail "effective backup policy should require a pre-update backup"
else
    if /usr/local/libexec/srv-control-backup-policy required-for-update; then
        fail "effective backup policy ignored backup_before_update=false"
    fi
fi

if /usr/local/libexec/srv-control-backup-policy scheduled; then
    systemctl is-enabled --quiet srv-control-backup.timer || fail "scheduled backup timer is not enabled"
    systemctl is-active --quiet srv-control-backup.timer || fail "scheduled backup timer is not active"
else
    ! systemctl is-enabled --quiet srv-control-backup.timer 2>/dev/null || fail "backup timer enabled while scheduled=false"
fi

OS_MODE="$(python3 - "$OS_CONFIG" <<'PY'
import json,pathlib,sys
try: p=json.loads(pathlib.Path(sys.argv[1]).read_text(encoding='utf-8'))
except FileNotFoundError: p={'mode':'manual'}
print(p.get('mode','manual'))
PY
)"
if [[ "$OS_MODE" == "automatic" ]]; then
    systemctl is-enabled --quiet srv-control-os-auto-update.timer || fail "automatic OS timer is not enabled"
else
    ! systemctl is-enabled --quiet srv-control-os-auto-update.timer 2>/dev/null || fail "OS timer enabled while mode is manual"
fi

systemctl is-enabled --quiet srv-control-system-agent.path || fail "system action watcher is not enabled"
systemctl is-active --quiet srv-control-system-agent.path || fail "system action watcher is not active"

/usr/local/libexec/srv-control-minecraft-repair check >/tmp/srvcc-minecraft-2.0.json \
    || { cat /tmp/srvcc-minecraft-2.0.json >&2 || true; fail "Minecraft Bedrock is not healthy after 2.0 repair"; }
python3 - /tmp/srvcc-minecraft-2.0.json <<'PY'
import json,sys
p=json.load(open(sys.argv[1],encoding='utf-8'))
assert p.get('ok') is True,p
assert p.get('port_listening') is True,p
print('MINECRAFT PASS:',p.get('version'),p.get('level_name'),p.get('port'))
PY
rm -f /tmp/srvcc-minecraft-2.0.json

if systemctl is-enabled --quiet srv-control-minecraft-auto-update.timer 2>/dev/null; then
    fail "conflicting multi-instance Minecraft auto-update timer is enabled"
fi
if systemctl cat minecraft-update.timer >/dev/null 2>&1; then
    systemctl is-enabled --quiet minecraft-update.timer || fail "proven Minecraft update timer is not enabled"
fi

printf 'ACCEPTANCE 2.0.0 PASS: UI/API/update scheduling/backup policy/Minecraft healthy\n'
