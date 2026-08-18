#!/usr/bin/env bash
set -Eeuo pipefail
umask 027

PROJECT="${1:-/opt/srv-control}"
REMOTE_SHA="${2:-unknown}"
STATE_DIR="/var/lib/srv-control"
RELEASE_META="${STATE_DIR}/release.json"
UNIT="srv-control-minecraft-bedrock.service"
STATUS_JS="$PROJECT/static/js/minecraft-status-2.1.2.js"
TEMPLATE="$PROJECT/templates/minecraft.html"

fail(){ printf 'ACCEPTANCE 2.1.2 FAIL: %s\n' "$*" >&2; exit 1; }

[[ -s "$RELEASE_META" ]] || fail "release metadata is missing"
python3 - "$RELEASE_META" "$REMOTE_SHA" <<'PY'
import json,pathlib,sys
p=json.loads(pathlib.Path(sys.argv[1]).read_text(encoding='utf-8'))
assert p.get('version') == p.get('release_id') == '2.1.2',p
if sys.argv[2] != 'unknown': assert p.get('git_sha') == sys.argv[2],(p,sys.argv[2])
print('RELEASE MARKER PASS:',p.get('version'),p.get('git_sha'))
PY

curl -fsS --max-time 15 http://127.0.0.1:8876/api/v1/health >/tmp/srvcc-2.1.2-health.json \
    || fail "Control Center health endpoint is unavailable"
python3 - /tmp/srvcc-2.1.2-health.json <<'PY'
import json,sys
p=json.load(open(sys.argv[1],encoding='utf-8'))
assert p.get('ok') is True,p
release=(p.get('data') or {}).get('release') or {}
assert release.get('version') == '2.1.2',release
print('CONTROL CENTER HEALTH PASS:',release.get('version'))
PY
rm -f /tmp/srvcc-2.1.2-health.json

[[ "$(systemctl show srv-control.service -p NoNewPrivileges --value)" == "yes" ]] \
    || fail "NoNewPrivileges must remain enabled on Control Center"
! grep -Fq '["/usr/bin/sudo", "-n", str(helper), *args]' "$PROJECT/app/routers/minecraft_legacy.py" \
    || fail "legacy sudo path is still present in Minecraft router"

[[ -s "$STATUS_JS" ]] || fail "2.1.2 live status JavaScript is missing"
grep -Fq 'const POLL_MS = 5000' "$STATUS_JS" || fail "5 second live status polling contract is missing"
grep -Fq '/api/v1/minecraft/legacy' "$STATUS_JS" || fail "Minecraft status API binding is missing"
grep -Fq 'Последняя команда:' "$STATUS_JS" || fail "explicit command result UI is missing"
grep -Fq 'minecraft-status-2.1.2.js?v=2.1.2' "$TEMPLATE" || fail "Minecraft template does not load 2.1.2 status UI"
curl -fsS --max-time 10 http://127.0.0.1:8876/static/js/minecraft-status-2.1.2.js \
    | grep -Fq 'mc212RuntimeStatus' || fail "2.1.2 status asset is not served by Control Center"

systemctl cat "$UNIT" >/dev/null 2>&1 || fail "$UNIT is missing"
WAS_ACTIVE=0
systemctl is-active --quiet "$UNIT" && WAS_ACTIVE=1 || true

/usr/local/sbin/srv-control-minecraft status > /tmp/srvcc-2.1.2-before.json \
    || { cat /tmp/srvcc-2.1.2-before.json >&2 || true; fail "initial status query failed"; }
python3 - /tmp/srvcc-2.1.2-before.json <<'PY'
import json,sys
p=json.load(open(sys.argv[1],encoding='utf-8'))
assert p.get('ok') is True,p
assert p.get('service') == 'srv-control-minecraft-bedrock.service',p
assert isinstance(p.get('active'),bool),p
assert p.get('runtime'),p
assert p.get('level_name'),p
assert p.get('state') in {'running','degraded','stopped','error'},p
print('VISIBLE STATUS CONTRACT PASS:',p.get('state'),p.get('runtime'),p.get('level_name'))
PY

if [[ "$WAS_ACTIVE" == "1" ]]; then
    /usr/local/sbin/srv-control-minecraft service stop > /tmp/srvcc-2.1.2-stop.json \
        || { cat /tmp/srvcc-2.1.2-stop.json >&2 || true; fail "controlled stop failed"; }
    python3 - /tmp/srvcc-2.1.2-stop.json <<'PY'
import json,sys
p=json.load(open(sys.argv[1],encoding='utf-8'))
assert p.get('ok') is True,p
assert p.get('active') is False,p
assert p.get('state') == 'stopped',p
assert 'OFFLINE' in str(p.get('message') or ''),p
print('STOP RESULT PASS:',p.get('message'))
PY
fi

# This is the exact production regression gate: status must remain readable after
# Bedrock is stopped even though the real runtime is /opt/minicraft and there is no
# running PID from which the legacy helper can discover cwd.
/usr/local/sbin/srv-control-minecraft status > /tmp/srvcc-2.1.2-stopped.json \
    || { cat /tmp/srvcc-2.1.2-stopped.json >&2 || true; fail "status disappeared while server was stopped"; }
python3 - /tmp/srvcc-2.1.2-stopped.json <<'PY'
import json,pathlib,sys
p=json.load(open(sys.argv[1],encoding='utf-8'))
if p.get('active') is False:
    assert p.get('ok') is True,p
    assert p.get('state') == 'stopped',p
    assert p.get('runtime'),p
    assert pathlib.Path(p['runtime']).is_dir(),p
    assert p.get('level_name'),p
    assert p.get('world_exists') is True,p
    print('STOPPED-STATE STATUS PASS:',p.get('runtime'),p.get('level_name'))
else:
    print('STOPPED-STATE STATUS GATE SKIPPED: server was intentionally active before test')
PY

if [[ "$WAS_ACTIVE" == "1" ]]; then
    /usr/local/sbin/srv-control-minecraft service start > /tmp/srvcc-2.1.2-start.json \
        || { cat /tmp/srvcc-2.1.2-start.json >&2 || true; fail "controlled start failed"; }
    python3 - /tmp/srvcc-2.1.2-start.json <<'PY'
import json,sys
p=json.load(open(sys.argv[1],encoding='utf-8'))
assert p.get('ok') is True,p
assert p.get('active') is True,p
assert p.get('healthy') is True,p
assert p.get('port_listening') is True,p
assert p.get('world_exists') is True,p
assert 'ONLINE' in str(p.get('message') or ''),p
print('START RESULT PASS:',p.get('message'))
PY
fi

rm -f \
    /tmp/srvcc-2.1.2-before.json \
    /tmp/srvcc-2.1.2-stop.json \
    /tmp/srvcc-2.1.2-stopped.json \
    /tmp/srvcc-2.1.2-start.json

printf 'ACCEPTANCE 2.1.2 PASS: Minecraft status remains visible while stopped; start/stop results are explicit; live UI polls every 5 seconds; original service state restored\n'
