#!/usr/bin/env bash
set -Eeuo pipefail
umask 027

PROJECT="${1:-/opt/srv-control}"
REMOTE_SHA="${2:-unknown}"
STATE_DIR="/var/lib/srv-control"
RELEASE_META="${STATE_DIR}/release.json"
CANONICAL_UNIT="srv-control-minecraft-bedrock.service"
PERMISSIONS_UNIT="srv-control-minecraft-permissions.service"
UPDATE_TIMER="srv-control-minecraft-bedrock-update.timer"
NORMALIZER="/usr/local/libexec/srv-control-minecraft-normalize"
PERMISSIONS="/usr/local/libexec/srv-control-minecraft-permissions"
UPDATER="/usr/local/libexec/srv-control-minecraft-bedrock-update"

fail(){ printf 'ACCEPTANCE 2.1.1 FAIL: %s\n' "$*" >&2; exit 1; }

[[ -d "$PROJECT" ]] || fail "Control Center project is missing"
for file in "$RELEASE_META" "$NORMALIZER" "$PERMISSIONS" "$UPDATER"; do [[ -s "$file" ]] || fail "required 2.1.1 runtime file is missing: $file"; done
for helper in \
    /usr/local/sbin/srv-control-minecraft \
    /usr/local/sbin/srv-control-minecraft-worlds \
    /usr/local/sbin/srv-control-minecraft-restore
do [[ -x "$helper" ]] || fail "Minecraft helper is missing: $helper"; done

python3 - "$RELEASE_META" "$REMOTE_SHA" <<'PY'
import json,pathlib,sys
p=json.loads(pathlib.Path(sys.argv[1]).read_text(encoding='utf-8'))
assert p.get('version') == '2.1.1',p
assert p.get('release_id') == '2.1.1',p
if sys.argv[2] != 'unknown': assert p.get('git_sha') == sys.argv[2],(p,sys.argv[2])
print('RELEASE MARKER PASS:',p.get('version'),p.get('git_sha'))
PY

curl -fsS --max-time 15 http://127.0.0.1:8876/api/v1/health >/tmp/srvcc-2.1.1-health.json \
    || fail "Control Center health endpoint is unavailable"
python3 - /tmp/srvcc-2.1.1-health.json <<'PY'
import json,sys
p=json.load(open(sys.argv[1],encoding='utf-8'))
assert p.get('ok') is True,p
release=(p.get('data') or {}).get('release') or {}
assert release.get('version') == '2.1.1',release
print('CONTROL CENTER HEALTH PASS:',release.get('version'))
PY
rm -f /tmp/srvcc-2.1.1-health.json

systemctl is-enabled --quiet "$CANONICAL_UNIT" || fail "$CANONICAL_UNIT is not enabled"
systemctl is-active --quiet "$CANONICAL_UNIT" || fail "$CANONICAL_UNIT is not active"
[[ "$(systemctl show "$CANONICAL_UNIT" -p User --value)" == "minecraft" ]] || fail "canonical Minecraft service is not running with User=minecraft"
[[ "$(systemctl show "$CANONICAL_UNIT" -p Group --value)" == "minecraft" ]] || fail "canonical Minecraft service is not running with Group=minecraft"
systemctl cat "$PERMISSIONS_UNIT" >/dev/null 2>&1 || fail "runtime ownership guard unit is missing"

canonical_audit(){
    "$NORMALIZER" audit > /tmp/srvcc-minecraft-2.1.1-audit.json || return 1
    python3 - /tmp/srvcc-minecraft-2.1.1-audit.json <<'PY'
import json,pwd,os,sys
p=json.load(open(sys.argv[1],encoding='utf-8'))
assert p.get('ok') is True,p
assert p.get('canonical') is True,p
assert p.get('needs_normalization') is False,p
assert p.get('port_listening') is True,p
assert p.get('world_exists') is True,p
assert p.get('level_name'),p
pids=p.get('pids') or []
assert len(pids) == 1,p
uid=pwd.getpwnam('minecraft').pw_uid
assert os.stat(f'/proc/{int(pids[0])}').st_uid == uid,(pids[0],uid)
assert set((p.get('units') or {}).values()) == {'srv-control-minecraft-bedrock.service'},p
print('UNPRIVILEGED CANONICAL BEDROCK PASS:',p.get('runtime'),p.get('level_name'),p.get('port'),pids[0])
PY
}
canonical_audit || fail "canonical Bedrock audit failed"
RUNTIME="$(python3 - /tmp/srvcc-minecraft-2.1.1-audit.json <<'PY'
import json,sys
print(json.load(open(sys.argv[1],encoding='utf-8'))['runtime'])
PY
)"
rm -f /tmp/srvcc-minecraft-2.1.1-audit.json

"$PERMISSIONS" audit > /tmp/srvcc-minecraft-2.1.1-permissions.json \
    || { cat /tmp/srvcc-minecraft-2.1.1-permissions.json >&2 || true; fail "runtime ownership audit failed"; }
python3 - /tmp/srvcc-minecraft-2.1.1-permissions.json <<'PY'
import json,sys
p=json.load(open(sys.argv[1],encoding='utf-8'))
assert p.get('ok') is True,p
assert p.get('unit_user') == 'minecraft',p
assert p.get('unit_group') == 'minecraft',p
assert not p.get('mismatches'),p
print('RUNTIME OWNERSHIP PASS:',p.get('checked_paths'))
PY
rm -f /tmp/srvcc-minecraft-2.1.1-permissions.json

# Prove the pre-start ownership guard actually repairs a root-created runtime
# artifact before Bedrock starts. The hidden probe is removed immediately after.
PROBE="$RUNTIME/.control-center-2.1.1-permission-probe"
printf 'ownership-probe\n' > "$PROBE"
chown root:root "$PROBE"
chmod 0600 "$PROBE"
/usr/local/sbin/srv-control-minecraft service restart > /tmp/srvcc-minecraft-2.1.1-restart.json \
    || { cat /tmp/srvcc-minecraft-2.1.1-restart.json >&2 || true; rm -f "$PROBE"; fail "controlled Minecraft restart failed"; }
healthy=0
for _ in $(seq 1 35); do
    if canonical_audit >/tmp/srvcc-minecraft-2.1.1-restart-audit.log 2>&1; then healthy=1; break; fi
    sleep 2
done
[[ "$healthy" == "1" ]] || { cat /tmp/srvcc-minecraft-2.1.1-restart-audit.log >&2 || true; rm -f "$PROBE"; fail "Minecraft did not recover after controlled restart"; }
python3 - "$PROBE" <<'PY'
import os,pwd,sys
p=sys.argv[1]; info=os.stat(p); user=pwd.getpwnam('minecraft')
assert info.st_uid == user.pw_uid,(info.st_uid,user.pw_uid)
print('PRE-START OWNERSHIP REPAIR PASS')
PY
rm -f "$PROBE" /tmp/srvcc-minecraft-2.1.1-restart.json /tmp/srvcc-minecraft-2.1.1-restart-audit.log /tmp/srvcc-minecraft-2.1.1-audit.json

# Backup/restore catalog remains usable after ownership migration.
/usr/local/sbin/srv-control-minecraft backup > /tmp/srvcc-minecraft-2.1.1-backup.json \
    || fail "Minecraft backup operation failed"
BACKUP_NAME="$(python3 - /tmp/srvcc-minecraft-2.1.1-backup.json <<'PY'
import json,pathlib,sys
p=json.load(open(sys.argv[1],encoding='utf-8'))
assert p.get('ok') is True,p
path=pathlib.Path(str(p.get('path') or ''))
assert path.is_file() and path.stat().st_size > 0,p
print(path.name)
PY
)"
/usr/local/sbin/srv-control-minecraft-restore inspect "$BACKUP_NAME" > /tmp/srvcc-minecraft-2.1.1-inspect.json \
    || fail "Minecraft backup inspection failed"
python3 - "$BACKUP_NAME" /tmp/srvcc-minecraft-2.1.1-inspect.json <<'PY'
import json,sys
p=json.load(open(sys.argv[2],encoding='utf-8'))
assert p.get('ok') is True,p
assert p.get('name') == sys.argv[1],p
assert p.get('members'),p
print('BACKUP/RESTORE CATALOG PASS:',sys.argv[1])
PY
rm -f /tmp/srvcc-minecraft-2.1.1-backup.json /tmp/srvcc-minecraft-2.1.1-inspect.json

# Exactly one managed update scheduler is allowed in 2.1.1.
systemctl is-enabled --quiet "$UPDATE_TIMER" || fail "canonical Minecraft update timer is not enabled"
systemctl is-active --quiet "$UPDATE_TIMER" || fail "canonical Minecraft update timer is not active"
! systemctl is-enabled --quiet minecraft-update.timer 2>/dev/null || fail "legacy minecraft-update.timer remains enabled"
! systemctl is-active --quiet minecraft-update.timer 2>/dev/null || fail "legacy minecraft-update.timer remains active"
! systemctl is-enabled --quiet srv-control-minecraft-auto-update.timer 2>/dev/null || fail "conflicting multi-instance Minecraft timer remains enabled"
! systemctl is-active --quiet srv-control-minecraft-auto-update.timer 2>/dev/null || fail "conflicting multi-instance Minecraft timer remains active"

"$UPDATER" check > /tmp/srvcc-minecraft-2.1.1-update-check.json \
    || { cat /tmp/srvcc-minecraft-2.1.1-update-check.json >&2 || true; fail "canonical updater check failed"; }
/usr/local/sbin/srv-control-minecraft updater > /tmp/srvcc-minecraft-2.1.1-ui-updater.json \
    || fail "Control Center updater status failed"
python3 - /tmp/srvcc-minecraft-2.1.1-update-check.json /tmp/srvcc-minecraft-2.1.1-ui-updater.json <<'PY'
import json,sys
check=json.load(open(sys.argv[1],encoding='utf-8')); ui=json.load(open(sys.argv[2],encoding='utf-8'))
assert check.get('ok') is True,check
assert check.get('decision_ready') is True,check
assert check.get('installed_version'),check
assert check.get('latest_version'),check
assert ui.get('ok') is True,ui
assert ui.get('canonical_update_path') is True,ui
assert ui.get('timer_unit') == 'srv-control-minecraft-bedrock-update.timer',ui
assert ui.get('timer_enabled') is True and ui.get('timer_active') is True,ui
print('CANONICAL UPDATE PATH PASS:',check.get('installed_version'),check.get('latest_version'),check.get('update_available'))
PY
rm -f /tmp/srvcc-minecraft-2.1.1-update-check.json /tmp/srvcc-minecraft-2.1.1-ui-updater.json

/usr/local/sbin/srv-control-minecraft logs 80 > /tmp/srvcc-minecraft-2.1.1-logs.json || fail "Minecraft log operation failed"
python3 - /tmp/srvcc-minecraft-2.1.1-logs.json <<'PY'
import json,sys
p=json.load(open(sys.argv[1],encoding='utf-8'))
assert p.get('ok') is True and isinstance(p.get('logs'),list),p
print('MINECRAFT LOG PATH PASS:',len(p.get('logs')))
PY
rm -f /tmp/srvcc-minecraft-2.1.1-logs.json

printf 'ACCEPTANCE 2.1.1 PASS: Bedrock runs unprivileged as minecraft; ownership guard repairs runtime; one canonical PID/UDP/world; backup and canonical updater decision path accepted\n'
