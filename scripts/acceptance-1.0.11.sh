#!/usr/bin/env bash
set -Eeuo pipefail
ROOT=/opt/control-center
[[ "$(tr -d '[:space:]' <"$ROOT/VERSION")" == '1.0.11' ]]
[[ "$(tr -d '[:space:]' <"$ROOT/BUILD")" == '20260819.5' ]]
PORT=$(sed -n 's/^CONTROL_CENTER_PORT=//p' /etc/control-center/web.env | head -1); PORT=${PORT:-8080}
SSL=$(sed -n 's/^CONTROL_CENTER_SSL=//p' /etc/control-center/web.env | head -1); SSL=${SSL:-0}
SCHEME=http; CURL=(-fsS --max-time 8)
if [[ "$SSL" == 1 || "$SSL" == true ]]; then SCHEME=https; CURL=(-kfsS --max-time 8); fi
BASE="$SCHEME://127.0.0.1:$PORT"

H=$(curl "${CURL[@]}" "$BASE/api/health")
python3 - "$H" <<'PY'
import json,sys
j=json.loads(sys.argv[1]);assert j['version']=='1.0.11' and j['build']=='20260819.5'
PY
systemctl is-active --quiet control-center
systemctl is-active --quiet control-center-authd.service
systemctl is-active --quiet control-center-samba-apply.path
systemctl is-active --quiet control-center-domain-destroy.path
systemctl is-active --quiet control-center-dns-apply.path
systemctl is-active --quiet control-center-storage-apply.path
systemctl is-active --quiet control-center-dhcp-reservations-apply.path
test -S /run/control-center-auth/auth.sock
test "$(stat -c '%U:%G %a' /run/control-center-auth/auth.sock)" = 'root:control-center 660'
test "$(stat -c '%U:%G %a' /run/control-center)" = 'control-center:control-center 700'
test "$(stat -c '%U:%G %a' /run/control-center-root)" = 'root:root 700'

LATEST=$(sudo -u control-center psql -d control_center -Atqc "select version from control_center.schema_migrations order by version desc limit 1" 2>/dev/null || true)
[[ -z "$LATEST" || "$LATEST" == 005 ]]
if [[ -n "$LATEST" ]];then
  sudo -u control-center psql -d control_center -Atqc "select count(*) from control_center.service_dependencies where service_id='domain' and required"|grep -qx 2
  sudo -u control-center psql -d control_center -Atqc "select count(*) from control_center.rbac_roles where role_id in ('admin','viewer')"|grep -qx 2
fi

# Portal is intentionally protected: unauthenticated health is public while
# administrative APIs require a login session.
[[ "$(curl -sS -o /dev/null -w '%{http_code}' "$BASE/api/market")" == 401 ]]
[[ "$(curl -sS -o /dev/null -w '%{http_code}' "$BASE/login")" == 200 ]]

SAMBA=/var/lib/control-center-system/modules/samba.json
if [[ -s "$SAMBA" ]] && python3 - "$SAMBA" <<'PY'
import json,sys
j=json.load(open(sys.argv[1]));raise SystemExit(0 if j.get('managed') and j.get('state')=='active' else 1)
PY
then
  systemctl is-active --quiet samba-ad-dc.service
  samba-tool testparm >/dev/null
  samba-tool ntacl sysvolcheck >/dev/null
  python3 - <<'PY'
import json
s=json.load(open('/var/lib/control-center-system/modules/samba.json'));d=json.load(open('/var/lib/control-center-system/modules/dns.json'));f=json.load(open('/var/lib/control-center-system/modules/storage.json'))
assert d['provider']=='samba_internal' and 'domain' in d.get('dependency_by',[])
assert f['provider']=='samba_ad_dc' and 'domain' in f.get('dependency_by',[])
assert s.get('portal_auth',{}).get('domain') is True
PY
fi

for f in \
 /usr/local/sbin/control-center-samba-apply /usr/local/sbin/control-center-samba-apply-core \
 /usr/local/sbin/control-center-domain-pre /usr/local/sbin/control-center-domain-post \
 /usr/local/sbin/control-center-domain-restore-prestate /usr/local/sbin/control-center-domain-destroy \
 /usr/local/sbin/control-center-samba-approve /usr/local/sbin/control-center-dns-apply \
 /usr/local/sbin/control-center-storage-apply /usr/local/sbin/control-center-dhcp-reservations-apply;do bash -n "$f";done
python3 -m py_compile /usr/local/sbin/control-center-authd
if command -v node >/dev/null 2>&1;then
 node --check "$ROOT/app/static/release-111.js" >/dev/null
 node --check "$ROOT/app/static/release-111-services.js" >/dev/null
 node --check "$ROOT/app/static/release-111-ui-fix.js" >/dev/null
 node --check "$ROOT/app/static/release-111-login.js" >/dev/null
fi

test -z "$(dpkg --audit 2>&1||true)"
echo 'ACCEPTANCE 1.0.11: PASSED'
