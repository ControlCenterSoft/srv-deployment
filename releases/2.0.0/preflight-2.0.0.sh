#!/usr/bin/env bash
set -Eeuo pipefail
umask 027

PROJECT="${1:-/opt/srv-control}"
REMOTE_SHA="${2:-unknown}"
RELEASE_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
PAYLOAD="${RELEASE_DIR}/payload"
SYSTEM="${RELEASE_DIR}/system"
STATE_DIR="/var/lib/srv-control"
RELEASE_META="${STATE_DIR}/release.json"

fail(){ printf 'PREFLIGHT 2.0.0 FAIL: %s\n' "$*" >&2; exit 1; }
warn(){ printf 'PREFLIGHT 2.0.0 WARN: %s\n' "$*" >&2; }

[[ "$(id -u)" -eq 0 ]] || fail "must run as root"
[[ -d "$PROJECT" ]] || fail "Control Center project is missing: $PROJECT"
[[ -s "$RELEASE_META" ]] || fail "installed release metadata is missing"

for command in python3 systemctl curl git sha256sum flock ss runuser install; do
    command -v "$command" >/dev/null 2>&1 || fail "required command is missing: $command"
done

for path in \
    "$PAYLOAD/app/main.py" \
    "$PAYLOAD/app/routers/system_v2.py" \
    "$PAYLOAD/templates/shell.html" \
    "$PAYLOAD/templates/system.html" \
    "$PAYLOAD/static/js/system-2.0.js" \
    "$PAYLOAD/static/js/github-update-timestamps.js" \
    "$SYSTEM/srvcc-update-controller" \
    "$SYSTEM/srvcc-configure-auto-updates" \
    "$SYSTEM/srv-control-backup-policy" \
    "$SYSTEM/srv-control-os-auto-update" \
    "$SYSTEM/srv-control-minecraft-repair"
do
    [[ -s "$path" ]] || fail "required 2.0 payload is missing: $path"
done

python3 - "$RELEASE_META" <<'PY'
import json, pathlib, re, sys
p=json.loads(pathlib.Path(sys.argv[1]).read_text(encoding='utf-8'))
version=str(p.get('version') or '')
m=re.fullmatch(r'(\d+)\.(\d+)\.(\d+)',version)
if not m:
    raise SystemExit(f'unsupported installed version: {version!r}')
current=tuple(map(int,m.groups()))
if not ((1,2,0) <= current < (2,0,0) or current == (2,0,0)):
    raise SystemExit(f'unsupported upgrade source: {version}')
print('UPGRADE SOURCE PASS:',version)
PY

# The 2.0 release intentionally repairs the updater, so an unhealthy legacy
# service/timer is diagnostic information and must never block preflight.
printf 'Legacy updater before 2.0: service=%s timer=%s enabled=%s\n' \
    "$(systemctl is-active srvcc-github-agent.service 2>/dev/null || true)" \
    "$(systemctl is-active srvcc-github-agent.timer 2>/dev/null || true)" \
    "$(systemctl is-enabled srvcc-github-agent.timer 2>/dev/null || true)"

# Validate operator backup policy without forcing it true. False is a supported
# and tested value in 2.0 for both Control Center and OS update transactions.
python3 - "$STATE_DIR/backup-config.json" <<'PY'
import json,pathlib,sys
path=pathlib.Path(sys.argv[1])
try: data=json.loads(path.read_text(encoding='utf-8'))
except FileNotFoundError: data={'scheduled':False,'daily_time':'03:00','backup_before_update':True}
if not isinstance(data,dict): raise SystemExit('backup config is not an object')
for key in ('scheduled','backup_before_update'):
    if key in data and not isinstance(data[key],bool): raise SystemExit(f'{key} must be boolean')
print('BACKUP POLICY PASS: scheduled=%s before_update=%s' % (data.get('scheduled',False),data.get('backup_before_update',True)))
PY

# Require enough space for a rollback snapshot plus package/application staging.
python3 - "$PROJECT" "$STATE_DIR" <<'PY'
import shutil,sys
for path in sys.argv[1:]:
    free=shutil.disk_usage(path).free
    if free < 512*1024*1024:
        raise SystemExit(f'less than 512 MiB free at {path}')
    print('DISK PASS:',path,free)
PY

# Existing web service must be reachable before a transactional upgrade.
curl -fsS --max-time 10 http://127.0.0.1:8876/api/v1/health >/dev/null \
    || fail "current Control Center health endpoint is unavailable"

if [[ -s "$STATE_DIR/session.key" ]]; then
    runuser -u srv-control -- test -r "$STATE_DIR/session.key" \
        || fail "session key exists but is not readable by srv-control"
else
    fail "session key is missing"
fi

# Minecraft health is deliberately non-blocking here: 2.0 has a health-first
# repair stage. This avoids repeating 1.3.x preflight failures caused by the
# very subsystem the release is intended to repair.
if python3 "$SYSTEM/srv-control-minecraft-repair" check >/tmp/srvcc-minecraft-preflight.json 2>&1; then
    printf 'Minecraft preflight health: healthy\n'
else
    warn "Minecraft is unhealthy before 2.0 and will enter the repair flow"
    tail -c 3000 /tmp/srvcc-minecraft-preflight.json >&2 || true
fi
rm -f /tmp/srvcc-minecraft-preflight.json

printf 'PREFLIGHT 2.0.0 PASS: source compatible; updater and Minecraft repairable; backup policy preserved; sha=%s\n' "$REMOTE_SHA"
