#!/usr/bin/env bash
set -Eeuo pipefail
VERSION_EXPECTED=1.0.10
BUILD_EXPECTED=20260819.4
ROOT=/opt/control-center
[[ "$(tr -d '[:space:]' <"$ROOT/VERSION")" == "$VERSION_EXPECTED" ]]
[[ "$(tr -d '[:space:]' <"$ROOT/BUILD")" == "$BUILD_EXPECTED" ]]

PORT=$(sudo sed -n 's/^CONTROL_CENTER_PORT=//p' /etc/control-center/web.env | head -1); PORT=${PORT:-8080}
SSL=$(sudo sed -n 's/^CONTROL_CENTER_SSL=//p' /etc/control-center/web.env | head -1); SSL=${SSL:-0}
SCHEME=http; CURL=(-fsS --max-time 5)
if [[ "$SSL" == 1 || "$SSL" == true ]]; then SCHEME=https; CURL=(-kfsS --max-time 5); fi
BASE="$SCHEME://127.0.0.1:$PORT"

H=$(curl "${CURL[@]}" "$BASE/api/health")
python3 - "$H" <<'PY'
import json,sys
j=json.loads(sys.argv[1]);assert j['version']=='1.0.10' and j['build']=='20260819.4'
PY

SYS=$(curl "${CURL[@]}" "$BASE/api/system")
python3 - "$SYS" <<'PY'
import json,sys
j=json.loads(sys.argv[1]);assert j['version']=='1.0.10';assert 'wan' in j and 'lan' in j
assert isinstance(j['wan'].get('enabled'),bool) and isinstance(j['lan'].get('enabled'),bool)
PY

NET=$(curl "${CURL[@]}" "$BASE/api/network/config")
python3 - "$NET" <<'PY'
import json,sys
j=json.loads(sys.argv[1]);assert set(j['config'])>={'wan','lan'}
for role in ('wan','lan'):
    assert 'enabled' in j['config'][role]
PY

WEB=$(curl "${CURL[@]}" "$BASE/api/settings/web")
python3 - "$WEB" <<'PY'
import json,sys
j=json.loads(sys.argv[1]);assert j['standard_http_port']==80 and j['standard_https_port']==443
assert 'database_synced' in j and 'persistence' in j
PY

HOST=$(curl "${CURL[@]}" "$BASE/api/settings/hostname")
python3 - "$HOST" <<'PY'
import json,sys,re
j=json.loads(sys.argv[1]);assert re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9-]{0,62}',j['hostname'])
PY

SAMBA=$(curl "${CURL[@]}" "$BASE/api/samba/readiness")
python3 - "$SAMBA" <<'PY'
import json,sys
j=json.loads(sys.argv[1]);assert j['details']['installation_enabled'] is False
assert j['details']['provisioning_enabled'] is False
assert j['details']['next_release_target']=='1.0.11'
for k in ('hostname','fqdn','static_network','time_sync','packages','disk_space','dns_53','kerberos_88','ldap_389','smb_445'):
    assert k in j['checks'],k
PY

PLAN=$(curl "${CURL[@]}" -X POST "$BASE/api/samba/plan")
python3 - "$PLAN" <<'PY'
import json,sys
j=json.loads(sys.argv[1]);assert j['plan']['phase']=='dry-run-only';assert j['plan']['provisioning_enabled'] is False
assert j['plan']['target_release']=='1.0.11';assert len(j['sha256'])==64
assert j['plan']['pre_provision_backups'] and j['plan']['rollback_order'] and j['plan']['acceptance']
PY

NOTIFY=$(curl "${CURL[@]}" "$BASE/api/notifications")
python3 - "$NOTIFY" <<'PY'
import json,sys
j=json.loads(sys.argv[1]);assert isinstance(j.get('items'),list);assert 'persistence' in j
PY

node --check "$ROOT/app/static/release-110.js" >/dev/null
bash -n /usr/local/sbin/control-center-web-apply
bash -n /usr/local/sbin/control-center-hostname-apply
bash -n /usr/local/sbin/control-center-network-apply
sudo -u control-center psql -d control_center -Atqc "select version from control_center.schema_migrations order by version desc limit 1" 2>/dev/null | grep -qx 003 || true

echo 'ACCEPTANCE 1.0.10: PASSED'
