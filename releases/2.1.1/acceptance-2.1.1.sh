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
for file in "$RELEASE_META" "$NORMALIZER" "$PERMISSIONS" "$UPDATER" "$PROJECT/app/core/minecraft_privileged.py"; do [[ -s "$file" ]] || fail "required 2.1.1 runtime file is missing: $file"; done
for helper in /usr/local/sbin/srv-control-minecraft /usr/local/sbin/srv-control-minecraft-worlds /usr/local/sbin/srv-control-minecraft-restore; do
    [[ -x "$helper" ]] || fail "Minecraft helper is missing: $helper"
done

python3 - "$RELEASE_META" "$REMOTE_SHA" <<'PY'
import json,pathlib,sys
p=json.loads(pathlib.Path(sys.argv[1]).read_text(encoding='utf-8'))
assert p.get('version') == '2.1.1',p
assert p.get('release_id') == '2.1.1',p
if sys.argv[2] != 'unknown': assert p.get('git_sha') == sys.argv[2],(p,sys.argv[2])
print('RELEASE MARKER PASS:',p.get('version'),p.get('git_sha'))
PY

curl -fsS --max-time 15 http://127.0.0.1:8876/api/v1/health >/tmp/srvcc-2.1.1-health.json || fail "Control Center health endpoint is unavailable"
python3 - /tmp/srvcc-2.1.1-health.json <<'PY'
import json,sys
p=json.load(open(sys.argv[1],encoding='utf-8'))
assert p.get('ok') is True,p
release=(p.get('data') or {}).get('release') or {}
assert release.get('version') == '2.1.1',release
print('CONTROL CENTER HEALTH PASS:',release.get('version'))
PY
rm -f /tmp/srvcc-2.1.1-health.json

# Security regression gate: keep the web service sandboxed and prove that the
# Minecraft route no longer attempts sudo from inside NoNewPrivileges.
[[ "$(systemctl show srv-control.service -p NoNewPrivileges --value)" == "yes" ]] || fail "srv-control.service NoNewPrivileges is not enabled"
! grep -Fq '["/usr/bin/sudo", "-n", str(helper), *args]' "$PROJECT/app/routers/minecraft_legacy.py" || fail "Minecraft web router still invokes sudo"
grep -Fq 'run_privileged_minecraft_helper(kind, list(args)' "$PROJECT/app/routers/minecraft_legacy.py" || fail "Minecraft web router is not using privileged agent bridge"
systemctl is-enabled --quiet srv-control-minecraft-agent.path || fail "Minecraft privileged agent path is not enabled"
systemctl is-active --quiet srv-control-minecraft-agent.path || fail "Minecraft privileged agent path is not active"

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

"$PERMISSIONS" audit > /tmp/srvcc-minecraft-2.1.1-permissions.json || { cat /tmp/srvcc-minecraft-2.1.1-permissions.json >&2 || true; fail "runtime ownership audit failed"; }
python3 - /tmp/srvcc-minecraft-2.1.1-permissions.json <<'PY'
import json,sys
p=json.load(open(sys.argv[1],encoding='utf-8'))
assert p.get('ok') is True,p
assert p.get('unit_user') == 'minecraft',p
assert p.get('unit_group') == 'minecraft',p
assert p.get('policy') == 'root-owned-program-minecraft-owned-data',p
assert not p.get('mismatches'),p
print('RUNTIME OWNERSHIP PASS:',p.get('checked_paths'),p.get('policy'))
PY
rm -f /tmp/srvcc-minecraft-2.1.1-permissions.json

# Exercise the same bridge used by the web router as the unprivileged service
# account. This specifically proves the reported sudo/NoNewPrivileges failure is gone.
runuser -u srv-control -- env PYTHONPATH="$PROJECT" "$PROJECT/venv/bin/python" - <<'PY' >/tmp/srvcc-minecraft-2.1.1-bridge-status.json
import json
from app.core.minecraft_privileged import run_helper
print(json.dumps(run_helper('control',['status'],timeout=30),ensure_ascii=False))
PY
python3 - /tmp/srvcc-minecraft-2.1.1-bridge-status.json <<'PY'
import json,sys
p=json.load(open(sys.argv[1],encoding='utf-8'))
assert p.get('ok') is True,p
assert p.get('service') == 'srv-control-minecraft-bedrock.service',p
assert p.get('active') is True,p
assert p.get('healthy') is True,p
print('WEB PRIVILEGED BRIDGE STATUS PASS')
PY
rm -f /tmp/srvcc-minecraft-2.1.1-bridge-status.json

# Prove the ownership guard repairs privileged artifacts in mutable data before
# Bedrock starts. Program binaries remain root-owned by policy.
PROBE="$RUNTIME/worlds/.control-center-2.1.1-permission-probe"
printf 'ownership-probe\n' > "$PROBE"
chown root:root "$PROBE"
chmod 0600 "$PROBE"
runuser -u srv-control -- env PYTHONPATH="$PROJECT" "$PROJECT/venv/bin/python" - <<'PY' >/tmp/srvcc-minecraft-2.1.1-bridge-restart.json
import json
from app.core.minecraft_privileged import run_helper
print(json.dumps(run_helper('control',['service','restart'],timeout=240),ensure_ascii=False))
PY
healthy=0
for _ in $(seq 1 35); do
    if canonical_audit >/tmp/srvcc-minecraft-2.1.1-restart-audit.log 2>&1; then healthy=1; break; fi
    sleep 2
done
[[ "$healthy" == "1" ]] || { cat /tmp/srvcc-minecraft-2.1.1-restart-audit.log >&2 || true; rm -f "$PROBE"; fail "Minecraft did not recover after web-bridge restart"; }
python3 - "$PROBE" <<'PY'
import os,pwd,sys
info=os.stat(sys.argv[1]); user=pwd.getpwnam('minecraft')
assert info.st_uid == user.pw_uid,(info.st_uid,user.pw_uid)
print('PRE-START MUTABLE OWNERSHIP REPAIR PASS')
PY
rm -f "$PROBE" /tmp/srvcc-minecraft-2.1.1-bridge-restart.json /tmp/srvcc-minecraft-2.1.1-restart-audit.log /tmp/srvcc-minecraft-2.1.1-audit.json

/usr/local/sbin/srv-control-minecraft backup > /tmp/srvcc-minecraft-2.1.1-backup.json || fail "Minecraft backup operation failed"
BACKUP_NAME="$(python3 - /tmp/srvcc-minecraft-2.1.1-backup.json <<'PY'
import json,pathlib,sys
p=json.load(open(sys.argv[1],encoding='utf-8'))
assert p.get('ok') is True,p
path=pathlib.Path(str(p.get('path') or ''))
assert path.is_file() and path.stat().st_size > 0,p
print(path.name)
PY
)"
/usr/local/sbin/srv-control-minecraft-restore inspect "$BACKUP_NAME" > /tmp/srvcc-minecraft-2.1.1-inspect.json || fail "Minecraft backup inspection failed"
python3 - "$BACKUP_NAME" /tmp/srvcc-minecraft-2.1.1-inspect.json <<'PY'
import json,sys
p=json.load(open(sys.argv[2],encoding='utf-8'))
assert p.get('ok') is True,p
assert p.get('name') == sys.argv[1],p
assert p.get('members'),p
print('BACKUP/RESTORE CATALOG PASS:',sys.argv[1])
PY
rm -f /tmp/srvcc-minecraft-2.1.1-backup.json /tmp/srvcc-minecraft-2.1.1-inspect.json

systemctl is-enabled --quiet "$UPDATE_TIMER" || fail "canonical Minecraft update timer is not enabled"
systemctl is-active --quiet "$UPDATE_TIMER" || fail "canonical Minecraft update timer is not active"
! systemctl is-enabled --quiet minecraft-update.timer 2>/dev/null || fail "legacy minecraft-update.timer remains enabled"
! systemctl is-active --quiet minecraft-update.timer 2>/dev/null || fail "legacy minecraft-update.timer remains active"
! systemctl is-enabled --quiet srv-control-minecraft-auto-update.timer 2>/dev/null || fail "conflicting multi-instance Minecraft timer remains enabled"
! systemctl is-active --quiet srv-control-minecraft-auto-update.timer 2>/dev/null || fail "conflicting multi-instance Minecraft timer remains active"

"$UPDATER" check > /tmp/srvcc-minecraft-2.1.1-update-check.json || { cat /tmp/srvcc-minecraft-2.1.1-update-check.json >&2 || true; fail "canonical updater check failed"; }
/usr/local/sbin/srv-control-minecraft updater > /tmp/srvcc-minecraft-2.1.1-ui-updater.json || fail "Control Center updater status failed"
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

printf 'ACCEPTANCE 2.1.1 PASS: NoNewPrivileges remains enabled; Minecraft UI uses root agent instead of sudo; Bedrock runs as minecraft; one canonical PID/UDP/world; ownership, backup and updater contracts accepted\n'
