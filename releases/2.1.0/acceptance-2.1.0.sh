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
[[ -x /usr/local/sbin/srv-control-minecraft ]] || fail "Minecraft Control Center dispatcher is missing"

python3 - "$RELEASE_META" "$REMOTE_SHA" <<'PY'
import json,pathlib,sys
p=json.loads(pathlib.Path(sys.argv[1]).read_text(encoding='utf-8'))
assert p.get('version') == '2.1.0',p
assert p.get('release_id') == '2.1.0',p
# remote sha is allowed to be unknown only for explicit local acceptance runs.
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

"$NORMALIZER" audit > /tmp/srvcc-minecraft-2.1-audit.json || fail "Minecraft canonical audit failed"
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

printf 'ACCEPTANCE 2.1.0 PASS: Control Center healthy; one canonical Bedrock process; UDP/world/control contract accepted\n'
