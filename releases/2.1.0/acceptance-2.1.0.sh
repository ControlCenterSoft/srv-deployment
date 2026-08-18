#!/usr/bin/env bash
set -Eeuo pipefail
umask 027

PROJECT="${1:-/opt/srv-control}"
REMOTE_SHA="${2:-unknown}"
STATE_DIR="/var/lib/srv-control"
RELEASE_META="${STATE_DIR}/release.json"
CANONICAL_UNIT="srv-control-minecraft-bedrock.service"
NORMALIZER="/usr/local/libexec/srv-control-minecraft-normalize"

fail(){ printf 'ACCEPTANCE 2.1.0 FAIL: %s\n' "$*" >&2; exit 1; }

[[ -d "$PROJECT" ]] || fail "Control Center project is missing"
[[ -s "$RELEASE_META" ]] || fail "release metadata is missing"
[[ -x "$NORMALIZER" ]] || fail "Minecraft normalizer is not installed"
for helper in \
    /usr/local/sbin/srv-control-minecraft \
    /usr/local/sbin/srv-control-minecraft-worlds \
    /usr/local/sbin/srv-control-minecraft-restore
do [[ -x "$helper" ]] || fail "Minecraft Control Center helper is missing: $helper"; done

python3 - "$RELEASE_META" "$REMOTE_SHA" <<'PY'
import json,pathlib,sys
p=json.loads(pathlib.Path(sys.argv[1]).read_text(encoding='utf-8'))
assert p.get('version') == '2.1.0',p
assert p.get('release_id') == '2.1.0',p
remote=sys.argv[2]
if remote != 'unknown': assert p.get('git_sha') == remote,(p,remote)
print('RELEASE MARKER PASS:',p.get('version'),p.get('git_sha'))
PY

curl -fsS --max-time 15 http://127.0.0.1:8876/api/v1/health >/tmp/srvcc-2.1-health.json \
    || fail "Control Center health endpoint is unavailable"
python3 - /tmp/srvcc-2.1-health.json <<'PY'
import json,sys
p=json.load(open(sys.argv[1],encoding='utf-8'))
assert p.get('ok') is True,p
print('CONTROL CENTER HEALTH PASS')
PY
rm -f /tmp/srvcc-2.1-health.json

systemctl is-enabled --quiet "$CANONICAL_UNIT" || fail "$CANONICAL_UNIT is not enabled"
systemctl is-active --quiet "$CANONICAL_UNIT" || fail "$CANONICAL_UNIT is not active"

canonical_audit(){
    "$NORMALIZER" audit > /tmp/srvcc-minecraft-2.1-audit.json || return 1
    python3 - /tmp/srvcc-minecraft-2.1-audit.json <<'PY'
import json,sys
p=json.load(open(sys.argv[1],encoding='utf-8'))
assert p.get('ok') is True,p
assert p.get('canonical') is True,p
assert p.get('needs_normalization') is False,p
assert p.get('port_listening') is True,p
assert p.get('world_exists') is True,p
assert p.get('level_name'),p
assert len(p.get('pids') or []) == 1,p
units=p.get('units') or {}
assert set(units.values()) == {'srv-control-minecraft-bedrock.service'},p
print('MINECRAFT CANONICAL AUDIT PASS:',p.get('runtime'),p.get('port'),p.get('level_name'))
PY
}
canonical_audit || fail "Minecraft canonical audit failed"
rm -f /tmp/srvcc-minecraft-2.1-audit.json

/usr/local/sbin/srv-control-minecraft status > /tmp/srvcc-minecraft-2.1-control.json \
    || fail "Minecraft Control Center status operation failed"
python3 - /tmp/srvcc-minecraft-2.1-control.json <<'PY'
import json,sys
p=json.load(open(sys.argv[1],encoding='utf-8'))
assert p.get('ok') is True,p
assert p.get('service') == 'srv-control-minecraft-bedrock.service',p
assert p.get('active') is True,p
assert p.get('healthy') is True,p
assert p.get('port_listening') is True,p
assert p.get('world_exists') is True,p
print('MINECRAFT CONTROL API PASS')
PY
rm -f /tmp/srvcc-minecraft-2.1-control.json

# Prove the active world exposed through the web-compatible helper is the same
# world accepted by the canonical runtime audit.
/usr/local/sbin/srv-control-minecraft-worlds list > /tmp/srvcc-minecraft-2.1-worlds.json \
    || fail "Minecraft world list operation failed"
"$NORMALIZER" audit > /tmp/srvcc-minecraft-2.1-audit.json
python3 - /tmp/srvcc-minecraft-2.1-worlds.json /tmp/srvcc-minecraft-2.1-audit.json <<'PY'
import json,sys
worlds=json.load(open(sys.argv[1],encoding='utf-8'))
audit=json.load(open(sys.argv[2],encoding='utf-8'))
assert worlds.get('ok') is True,worlds
active=worlds.get('active_world')
assert active and active == audit.get('level_name'),(worlds,audit)
assert any(isinstance(x,dict) and x.get('name') == active and x.get('active') for x in worlds.get('worlds',[])),worlds
print('MINECRAFT WORLD PASS:',active)
PY
rm -f /tmp/srvcc-minecraft-2.1-worlds.json /tmp/srvcc-minecraft-2.1-audit.json

# Create a real safety backup through the same helper used by Control Center and
# prove that the restore subsystem can list and inspect that exact archive. The
# acceptance test does not perform a restore because overwriting a healthy live
# world during every product update would itself be unnecessary risk.
/usr/local/sbin/srv-control-minecraft backup > /tmp/srvcc-minecraft-2.1-backup.json \
    || fail "Minecraft backup operation failed"
BACKUP_NAME="$(python3 - /tmp/srvcc-minecraft-2.1-backup.json <<'PY'
import json,os,pathlib,sys
p=json.load(open(sys.argv[1],encoding='utf-8'))
assert p.get('ok') is True,p
path=pathlib.Path(str(p.get('path') or ''))
assert path.is_file(),p
assert path.stat().st_size > 0,p
print(path.name)
PY
)"
[[ -n "$BACKUP_NAME" ]] || fail "Minecraft backup name is empty"
/usr/local/sbin/srv-control-minecraft-restore list > /tmp/srvcc-minecraft-2.1-backups.json \
    || fail "Minecraft backup list failed"
/usr/local/sbin/srv-control-minecraft-restore inspect "$BACKUP_NAME" > /tmp/srvcc-minecraft-2.1-inspect.json \
    || fail "Minecraft backup inspection failed"
python3 - "$BACKUP_NAME" /tmp/srvcc-minecraft-2.1-backups.json /tmp/srvcc-minecraft-2.1-inspect.json <<'PY'
import json,sys
name=sys.argv[1]
rows=json.load(open(sys.argv[2],encoding='utf-8'))
inspect=json.load(open(sys.argv[3],encoding='utf-8'))
assert rows.get('ok') is True,rows
assert any(isinstance(x,dict) and x.get('name') == name for x in rows.get('backups',[])),rows
assert inspect.get('ok') is True,inspect
assert inspect.get('name') == name,inspect
assert inspect.get('members'),inspect
print('MINECRAFT BACKUP/RESTORE CATALOG PASS:',name)
PY
rm -f /tmp/srvcc-minecraft-2.1-backup.json /tmp/srvcc-minecraft-2.1-backups.json /tmp/srvcc-minecraft-2.1-inspect.json

# A canonical service is only useful if Control Center can actually restart it.
# Perform one controlled restart and wait for the real UDP/world health contract
# to return before accepting the release.
/usr/local/sbin/srv-control-minecraft service restart > /tmp/srvcc-minecraft-2.1-restart.json \
    || { cat /tmp/srvcc-minecraft-2.1-restart.json >&2 || true; fail "Minecraft controlled restart failed"; }
healthy=0
for _ in $(seq 1 30); do
    if canonical_audit >/tmp/srvcc-minecraft-2.1-restart-audit.log 2>&1; then
        healthy=1
        break
    fi
    sleep 2
done
[[ "$healthy" == "1" ]] || { cat /tmp/srvcc-minecraft-2.1-restart-audit.log >&2 || true; fail "Minecraft did not become healthy after controlled restart"; }
rm -f /tmp/srvcc-minecraft-2.1-restart.json /tmp/srvcc-minecraft-2.1-restart-audit.log /tmp/srvcc-minecraft-2.1-audit.json

/usr/local/sbin/srv-control-minecraft logs 60 > /tmp/srvcc-minecraft-2.1-logs.json \
    || fail "Minecraft log operation failed"
/usr/local/sbin/srv-control-minecraft updater > /tmp/srvcc-minecraft-2.1-updater.json \
    || fail "Minecraft updater status operation failed"
python3 - /tmp/srvcc-minecraft-2.1-logs.json /tmp/srvcc-minecraft-2.1-updater.json <<'PY'
import json,sys
logs=json.load(open(sys.argv[1],encoding='utf-8'))
updater=json.load(open(sys.argv[2],encoding='utf-8'))
assert logs.get('ok') is True and isinstance(logs.get('logs'),list),logs
assert updater.get('ok') is True,updater
assert 'timer_enabled' in updater and 'timer_active' in updater,updater
print('MINECRAFT LOG/UPDATER PASS:',updater.get('installed_version'),updater.get('latest_version'))
PY
rm -f /tmp/srvcc-minecraft-2.1-logs.json /tmp/srvcc-minecraft-2.1-updater.json

# Conflicting multi-instance auto-update remains off on the single-server 2.1.x
# stabilization line. The proven historical update timer may be present or absent
# depending on source installation; if present it must be active after apply.
if systemctl cat srv-control-minecraft-auto-update.timer >/dev/null 2>&1; then
    systemctl is-enabled --quiet srv-control-minecraft-auto-update.timer && fail "conflicting multi-instance Minecraft timer is enabled"
fi
if systemctl cat minecraft-update.timer >/dev/null 2>&1; then
    systemctl is-enabled --quiet minecraft-update.timer || fail "single-server Minecraft update timer exists but is disabled"
    systemctl is-active --quiet minecraft-update.timer || fail "single-server Minecraft update timer exists but is inactive"
fi

printf 'ACCEPTANCE 2.1.0 PASS: Control Center healthy; one canonical Bedrock process; world, backup catalog, controlled restart, UDP and updater contracts accepted\n'
