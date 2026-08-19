#!/usr/bin/env bash
set -Eeuo pipefail

BASE=${CONTROL_CENTER_TEST_URL:-http://127.0.0.1:8080}
ADMIN_USER=${CC_TEST_ADMIN_USER:-ccciadmin}
ADMIN_PASS=${CC_TEST_ADMIN_PASSWORD:-CcLocal!Passw0rd-2026}
VIEWER_USER=${CC_TEST_VIEWER_USER:-ccviewer}
VIEWER_PASS=${CC_TEST_VIEWER_PASSWORD:-CcViewer!Passw0rd-2026}
DOMAIN_PASS=${CC_TEST_DOMAIN_PASSWORD:-DomTest!Passw0rd-2026}
ADMIN_COOKIE=/tmp/cc-admin.cookies
VIEWER_COOKIE=/tmp/cc-viewer.cookies
DOMAIN_ADMIN_COOKIE=/tmp/cc-domain-admin.cookies
DOMAIN_VIEWER_COOKIE=/tmp/cc-domain-viewer.cookies
DOMAIN_PACKAGE_SNAPSHOT=/tmp/cc-domain-packages-before.tsv
DOMAIN_TIME_SNAPSHOT=/tmp/cc-domain-time-services-before.tsv
rm -f "$ADMIN_COOKIE" "$VIEWER_COOKIE" "$DOMAIN_ADMIN_COOKIE" "$DOMAIN_VIEWER_COOKIE" "$DOMAIN_PACKAGE_SNAPSHOT" "$DOMAIN_TIME_SNAPSHOT"

log(){ printf '\n=== %s ===\n' "$*"; }
json_field(){ python3 -c "import json,sys;d=json.load(sys.stdin);print($1)"; }
login(){
  local mode="$1" user="$2" pass="$3" cookie="$4"
  python3 - "$mode" "$user" "$pass" >/tmp/cc-login.json <<'PY'
import json,sys
print(json.dumps({'mode':sys.argv[1],'username':sys.argv[2],'password':sys.argv[3]}))
PY
  curl -fsS -c "$cookie" -b "$cookie" -X POST -H 'Content-Type: application/json' --data-binary @/tmp/cc-login.json "$BASE/api/auth/login" >/tmp/cc-login-result.json
  python3 - /tmp/cc-login-result.json <<'PY'
import json,sys
j=json.load(open(sys.argv[1]));assert j.get('ok') is True,j
PY
  rm -f /tmp/cc-login.json /tmp/cc-login-result.json
}
api(){ local cookie="$1" method="$2" path="$3" data="${4:-}"; if [[ -n "$data" ]];then curl -fsS -b "$cookie" -c "$cookie" -X "$method" -H 'Content-Type: application/json' -d "$data" "$BASE$path";else curl -fsS -b "$cookie" -c "$cookie" -X "$method" "$BASE$path";fi; }
wait_json_state(){
  local file="$1" good="$2" bad_re="$3" timeout="${4:-180}"; local state=''
  for _ in $(seq 1 "$timeout");do
    state="$(sudo python3 - "$file" <<'PY' 2>/dev/null || true
import json,sys
try:print(json.load(open(sys.argv[1])).get('state',''))
except Exception:print('')
PY
)"
    [[ "$state" == "$good" ]]&&return 0
    if [[ "$state" =~ $bad_re ]];then sudo cat "$file"||true;return 1;fi
    sleep 1
  done
  echo "Timeout waiting $file => $good (last=$state)" >&2;return 1
}
wait_market(){
  local id="$1" good="$2";local code=''
  for _ in $(seq 1 180);do
    code="$(api "$ADMIN_COOKIE" GET /api/market | python3 -c "import json,sys;j=json.load(sys.stdin);print(next(x for x in j['items'] if x['id']=='$id')['status']['code'])")"
    [[ "$code" == "$good" ]]&&return 0
    [[ "$code" == error ]]&&{ api "$ADMIN_COOKIE" GET /api/market|python3 -m json.tool;return 1; }
    sleep 1
  done
  return 1
}
apt_mark_of(){
  local pkg="$1" base="${1%%:*}"
  if apt-mark showmanual 2>/dev/null | grep -Fxq "$pkg" || apt-mark showmanual 2>/dev/null | grep -Fxq "$base";then printf 'manual\n';else printf 'auto\n';fi
}
verify_package_snapshot(){
  local snapshot="$1" pkg was version mark current
  while IFS=$'\t' read -r pkg was version mark;do
    [[ -n "$pkg" ]]||continue
    if [[ "$was" == 1 ]];then
      current="$(dpkg-query -W -f='${Version}' "$pkg" 2>/dev/null||true)"
      [[ "$current" == "$version" ]]||{ echo "Package pre-state mismatch: $pkg current=$current expected=$version" >&2;return 1; }
      [[ "$(apt_mark_of "$pkg")" == "$mark" ]]||{ echo "APT mark pre-state mismatch: $pkg" >&2;return 1; }
    else
      ! dpkg-query -W -f='${Status}' "$pkg" 2>/dev/null|grep -qx 'install ok installed'||{ echo "Unexpected package after Domain removal: $pkg" >&2;return 1; }
    fi
  done <"$snapshot"
}
verify_service_snapshot(){
  local snapshot="$1" svc active enabled now_active now_enabled
  [[ -s "$snapshot" ]]||return 0
  while IFS=$'\t' read -r svc active enabled;do
    [[ -n "$svc" ]]||continue
    now_active="$(systemctl is-active "$svc" 2>/dev/null||true)";now_enabled="$(systemctl is-enabled "$svc" 2>/dev/null||true)"
    [[ "${now_active:-unknown}" == "$active" ]]||{ echo "Service active-state mismatch: $svc current=$now_active expected=$active" >&2;return 1; }
    [[ "${now_enabled:-unknown}" == "$enabled" ]]||{ echo "Service enable-state mismatch: $svc current=$now_enabled expected=$enabled" >&2;return 1; }
  done <"$snapshot"
}

log 'Version, DB and isolated auth daemon'
test "$(tr -d '[:space:]' </opt/control-center/VERSION)" = 1.0.11
test "$(tr -d '[:space:]' </opt/control-center/BUILD)" = 20260819.5
sudo -u control-center psql -d control_center -Atqc "select version from control_center.schema_migrations order by version desc limit 1"|grep -qx 005
systemctl is-active --quiet control-center-authd.service
test -S /run/control-center-auth/auth.sock
test "$(stat -c '%U:%G %a' /run/control-center-auth/auth.sock)" = 'root:control-center 660'
curl -fsS "$BASE/api/health" >/dev/null
[[ "$(curl -sS -o /dev/null -w '%{http_code}' "$BASE/api/market")" == 401 ]]

log 'Local portal authentication and bootstrap authorization'
login local "$ADMIN_USER" "$ADMIN_PASS" "$ADMIN_COOKIE"
api "$ADMIN_COOKIE" GET /api/auth/session | python3 -c "import json,sys;j=json.load(sys.stdin);assert j['authenticated'] and j['source']=='local' and j['role']=='admin'"
login local "$VIEWER_USER" "$VIEWER_PASS" "$VIEWER_COOKIE"
api "$VIEWER_COOKIE" GET /api/market >/dev/null
CODE=$(curl -sS -o /tmp/viewer-denied.json -w '%{http_code}' -b "$VIEWER_COOKIE" -X POST -H 'Content-Type: application/json' -d '{}' "$BASE/api/settings/update/check")
[[ "$CODE" == 403 ]];cat /tmp/viewer-denied.json

log 'Prepare isolated Static LAN'
ip link show ccad0 >/dev/null 2>&1||sudo ip link add ccad0 type dummy
sudo ip addr flush dev ccad0
sudo ip addr add 10.77.11.1/24 dev ccad0
sudo ip link set ccad0 up
sudo tee /var/lib/control-center-system/network-config.json >/dev/null <<'JSON'
{"wan":{"enabled":false,"interface":"","method":"disabled"},"lan":{"enabled":true,"interface":"ccad0","method":"static","ip":"10.77.11.1","mask":24,"gateway":"","dns":["1.1.1.1"]}}
JSON
sudo chown root:control-center /var/lib/control-center-system/network-config.json;sudo chmod 0640 /var/lib/control-center-system/network-config.json
api "$ADMIN_COOKIE" GET /api/network/config|python3 -c "import json,sys;j=json.load(sys.stdin);assert j['config']['lan']['interface']=='ccad0' and j['config']['lan']['ip']=='10.77.11.1'"

log 'Standalone DNS install and configuration'
api "$ADMIN_COOKIE" POST /api/market/dns '{"action":"install"}' >/dev/null
wait_json_state /var/lib/control-center-system/dns-status.json applied 'error|rollback|rejected' 240
systemctl is-active --quiet unbound.service
sudo python3 - <<'PY'
import json
j=json.load(open('/var/lib/control-center-system/modules/dns.json'));assert j['installed'] and j['provider']=='unbound' and j['explicit']
PY
api "$ADMIN_COOKIE" POST /api/dns/config '{"forwarders":["1.1.1.1","9.9.9.9"]}' >/dev/null
wait_json_state /var/lib/control-center-system/dns-status.json applied 'error|rollback|rejected' 120

log 'Standalone Network Storage install'
api "$ADMIN_COOKIE" POST /api/market/storage '{"action":"install"}' >/dev/null
wait_json_state /var/lib/control-center-system/storage-status.json applied 'error|rollback|rejected' 300
systemctl is-active --quiet smbd.service
sudo sh -c "echo preserve-me > /srv/control-center/storage/public/runtime-preserve.txt"
sudo python3 - <<'PY'
import json
j=json.load(open('/var/lib/control-center-system/modules/storage.json'));assert j['installed'] and j['provider']=='samba_standalone' and j['explicit']
PY

log 'DHCP install, client list, documented pagination and IP reservation'
api "$ADMIN_COOKIE" POST /api/market/dhcp '{"action":"install"}' >/dev/null
wait_market dhcp running
api "$ADMIN_COOKIE" POST /api/dhcp/config '{"interface":"ccad0","range_start":"10.77.11.100","range_end":"10.77.11.150","mask":24,"gateway":"10.77.11.1","dns":["1.1.1.1"],"lease_minutes":720,"extra_options":[]}' >/dev/null
wait_json_state /var/lib/control-center-system/dhcp-status.json applied 'error|rollback|rejected' 120
api "$ADMIN_COOKIE" GET /api/dhcp/clients >/dev/null
curl -fsS "$BASE/static/app.js" | grep -Fq 'DHCP_CLIENTS_PAGE_SIZE_COMPLIANCE111 = 10'
curl -fsS "$BASE/static/app.js" | grep -Fq 'dhcpClientsPager111'
api "$ADMIN_COOKIE" POST /api/dhcp/reservations '{"action":"reserve","mac":"02:11:22:33:44:55","ip":"10.77.11.120","hostname":"ci-client"}' >/dev/null
wait_json_state /var/lib/control-center-system/dhcp-reservations-status.json applied 'error|rollback|rejected' 120
grep -Fq 'dhcp-host=02:11:22:33:44:55,10.77.11.120,ci-client' /etc/dnsmasq.d/control-center-dhcp-reservations.conf
sudo -u control-center psql -d control_center -Atqc "select count(*) from control_center.dhcp_reservations where mac='02:11:22:33:44:55' and ipv4='10.77.11.120'"|grep -qx 1

log 'Time synchronization readiness'
sudo timedatectl set-ntp true >/dev/null 2>&1||true
for _ in $(seq 1 60);do [[ "$(timedatectl show -p NTPSynchronized --value 2>/dev/null||true)" == yes ]]&&break;sleep 1;done
if [[ "$(timedatectl show -p NTPSynchronized --value 2>/dev/null||true)" != yes ]];then
  sudo apt-get update;sudo DEBIAN_FRONTEND=noninteractive apt-get install -y chrony;sudo systemctl enable --now chrony.service;sudo chronyc -a makestep >/dev/null 2>&1||true
  for _ in $(seq 1 60);do [[ "$(timedatectl show -p NTPSynchronized --value 2>/dev/null||true)" == yes ]]&&break;sleep 1;done
fi
timedatectl show -p NTPSynchronized --value|grep -qx yes

log 'Initial Domain wizard readiness and dependency transition plan'
BODY='{"realm":"ci.example.test","netbios_domain":"CITEST","network_role":"lan","dns_forwarder":"1.1.1.1"}'
R=$(api "$ADMIN_COOKIE" POST /api/samba/readiness "$BODY")
python3 - "$R" <<'PY'
import json,sys
j=json.loads(sys.argv[1]);assert j['ready'],(j['blockers'],j['checks']);d=j['details']['dependencies'];assert d['domain_requires_dns'] and d['domain_requires_storage'];assert d['dns']=='managed-standalone-transition' and d['storage']=='managed-standalone-transition'
PY

log 'Provision real disposable Samba AD-DC through Domain wizard backend'
APPROVAL=$(sudo control-center-samba-approve);CODE=$(printf '%s\n' "$APPROVAL"|sed -n 's/^Control Center Samba AD-DC approval code: //p');[[ "$CODE" =~ ^[0-9a-f]{8}$ ]]
REQ=$(python3 - "$CODE" "$DOMAIN_PASS" <<'PY'
import json,sys
code,password=sys.argv[1:]
print(json.dumps({'realm':'ci.example.test','netbios_domain':'CITEST','network_role':'lan','dns_forwarder':'1.1.1.1','administrator_password':password,'confirm_password':password,'approval_code':code,'confirmation':True}))
PY
)
api "$ADMIN_COOKIE" POST /api/samba/provision "$REQ" >/tmp/domain-request-result.json
STATE=''
for _ in $(seq 1 420);do
  STATE=$(sudo python3 - <<'PY' 2>/dev/null||true
import json
try:print(json.load(open('/var/lib/control-center-system/samba-status.json')).get('state',''))
except Exception:print('')
PY
)
  [[ "$STATE" == active ]]&&break
  if [[ "$STATE" =~ ^(error|rollback|failed|rejected)$ ]];then sudo cat /var/lib/control-center-system/samba-status.json;sudo cat /var/lib/control-center-system/samba-last.log||true;sudo journalctl -u control-center-samba-apply.service -n 300 --no-pager||true;exit 1;fi
  sleep 2
done
[[ "$STATE" == active ]]
systemctl is-active --quiet samba-ad-dc.service
sudo python3 - <<'PY'
import json
s=json.load(open('/var/lib/control-center-system/modules/samba.json'));d=json.load(open('/var/lib/control-center-system/modules/dns.json'));f=json.load(open('/var/lib/control-center-system/modules/storage.json'))
assert s['managed'] and s['state']=='active';assert d['provider']=='samba_internal' and 'domain' in d['dependency_by'];assert f['provider']=='samba_ad_dc' and 'domain' in f['dependency_by']
assert s['portal_auth']['admin_group']=='Control Center Admins'
PY

# ExecStartPost commits the exact package/time-service pre-state only after the
# orchestrator completes successfully. Keep an external CI copy for the removal
# verification below.
for _ in $(seq 1 60);do sudo test -s /var/lib/control-center-root/domain-package-prestate/packages-before.tsv&&break;sleep 1;done
sudo test -s /var/lib/control-center-root/domain-package-prestate/packages-before.tsv
sudo cp /var/lib/control-center-root/domain-package-prestate/packages-before.tsv "$DOMAIN_PACKAGE_SNAPSHOT"
sudo test -s /var/lib/control-center-root/domain-package-prestate/time-services-before.tsv && sudo cp /var/lib/control-center-root/domain-package-prestate/time-services-before.tsv "$DOMAIN_TIME_SNAPSHOT" || true
sudo chown "$USER:$USER" "$DOMAIN_PACKAGE_SNAPSHOT" "$DOMAIN_TIME_SNAPSHOT" 2>/dev/null||true

log 'AD health, SID mapping, DNS, Kerberos, SYSVOL, Storage and DHCP-DNS integration'
sudo samba-tool testparm >/dev/null
sudo samba-tool ntacl sysvolcheck
sudo samba-tool domain info 10.77.11.1
sudo samba-tool drs showrepl --summary
host -W 3 -t SRV _ldap._tcp.ci.example.test 10.77.11.1
host -W 3 -t SRV _kerberos._udp.ci.example.test 10.77.11.1
sudo samba-tool group listmembers 'Control Center Admins' | grep -Fxiq Administrator
ADMINISTRATOR_SID="$(sudo wbinfo --name-to-sid 'CITEST\Administrator' | awk '{print $1}')"
[[ "$ADMINISTRATOR_SID" =~ ^S-1-5-21-.*-500$ ]]
[[ "$(sudo wbinfo --sid-to-uid "$ADMINISTRATOR_SID")" == 0 ]]
H=$(api "$ADMIN_COOKIE" POST /api/samba/health '{}');python3 - "$H" <<'PY'
import json,sys
j=json.loads(sys.argv[1]);assert j['healthy'],j['checks'];assert j['checks']['dns_dependency']['ok'];assert j['checks']['storage_dependency']['ok'];assert j['checks']['portal_auth_daemon']['ok']
PY
sudo python3 - <<'PY'
import json
j=json.load(open('/var/lib/control-center-system/dhcp-config.json'));assert j['dns']==['10.77.11.1']
PY
test -f /srv/control-center/storage/public/runtime-preserve.txt
grep -q '^# BEGIN CONTROL CENTER STORAGE' /etc/samba/smb.conf

log 'Domain authentication and RBAC bootstrap roles'
sudo samba-tool user create ccdomainadmin "$DOMAIN_PASS"
sudo samba-tool user create ccdomainviewer "$DOMAIN_PASS"
sudo samba-tool group addmembers 'Control Center Admins' ccdomainadmin
sudo samba-tool group listmembers 'Control Center Admins' | grep -Fxiq ccdomainadmin
for _ in $(seq 1 30);do sudo wbinfo --name-to-sid 'CITEST\ccdomainadmin' >/dev/null 2>&1&&break;sleep 1;done
login domain ccdomainadmin "$DOMAIN_PASS" "$DOMAIN_ADMIN_COOKIE"
api "$DOMAIN_ADMIN_COOKIE" GET /api/auth/session|python3 -c "import json,sys;j=json.load(sys.stdin);assert j['source']=='domain' and j['role']=='admin' and j['domain']=='CITEST'"
login domain ccdomainviewer "$DOMAIN_PASS" "$DOMAIN_VIEWER_COOKIE"
api "$DOMAIN_VIEWER_COOKIE" GET /api/auth/session|python3 -c "import json,sys;j=json.load(sys.stdin);assert j['source']=='domain' and j['role']=='viewer'"
CODE2=$(curl -sS -o /tmp/domain-viewer-denied.json -w '%{http_code}' -b "$DOMAIN_VIEWER_COOKIE" -X POST -H 'Content-Type: application/json' -d '{}' "$BASE/api/settings/update/check");[[ "$CODE2" == 403 ]]

log 'Active Domain safety restrictions'
for spec in \
  '/api/market/dns|{"action":"remove"}' \
  '/api/market/storage|{"action":"remove"}' \
  '/api/settings/hostname|{"hostname":"renamed-dc"}';do
  path=${spec%%|*};data=${spec#*|};code=$(curl -sS -o /tmp/guard.json -w '%{http_code}' -b "$ADMIN_COOKIE" -X POST -H 'Content-Type: application/json' -d "$data" "$BASE$path");[[ "$code" == 409 ]];cat /tmp/guard.json
done
PRIMARY_IF=$(ip route show default|awk '{print $5;exit}')
code=$(curl -sS -o /tmp/net-guard.json -w '%{http_code}' -b "$ADMIN_COOKIE" -X POST -H 'Content-Type: application/json' --data "{\"lan\":{\"enabled\":false,\"method\":\"disabled\"},\"wan\":{\"enabled\":true,\"interface\":\"$PRIMARY_IF\",\"method\":\"dhcp\"}}" "$BASE/api/network/config");[[ "$code" == 409 ]]

log 'Domain secret boundary'
test ! -e /run/control-center/samba-provision.json
test ! -e /run/control-center-root/samba-approval.json
! sudo grep -R -F --binary-files=without-match "$DOMAIN_PASS" /var/lib/control-center /var/lib/control-center-system /var/lib/control-center-root /etc/control-center /etc/samba 2>/dev/null
! sudo -u control-center psql -d control_center -Atqc "select request::text||result::text||coalesce(error,'') from control_center.ad_dc_lifecycle_jobs"|grep -F "$DOMAIN_PASS"

log 'Guarded Domain removal and exact package/configuration pre-state cleanup audit'
REMOVE_APPROVAL=$(sudo control-center-samba-approve --remove);REMOVE_CODE=$(printf '%s\n' "$REMOVE_APPROVAL"|sed -n 's/^Control Center Domain removal approval code: //p');[[ "$REMOVE_CODE" =~ ^[0-9a-f]{8}$ ]]
REMOVE_REQ=$(python3 - "$REMOVE_CODE" <<'PY'
import json,sys
print(json.dumps({'approval_code':sys.argv[1],'confirmation':'УДАЛИТЬ ДОМЕН'}))
PY
)
api "$ADMIN_COOKIE" POST /api/domain/remove "$REMOVE_REQ" >/dev/null
wait_json_state /var/lib/control-center-system/samba-status.json removed 'error|rollback|rejected' 420
LATEST_DOMAIN_AUDIT=$(ls -1t /var/lib/control-center-system/cleanup-audits/domain-*.json|head -1)
sudo python3 - "$LATEST_DOMAIN_AUDIT" <<'PY'
import json,sys
j=json.load(open(sys.argv[1]));assert j['clean'],j;assert j['checks']['prestate_fingerprints_match'];assert j['checks']['generated_sam_ldb_removed'];assert j['checks']['generated_sysvol_removed']
PY
sudo python3 - <<'PY'
import json
assert json.load(open('/var/lib/control-center-system/modules/dns.json'))['provider']=='unbound'
assert json.load(open('/var/lib/control-center-system/modules/storage.json'))['provider']=='samba_standalone'
PY
sudo test ! -e /var/lib/control-center-root/domain-package-prestate
verify_package_snapshot "$DOMAIN_PACKAGE_SNAPSHOT"
verify_service_snapshot "$DOMAIN_TIME_SNAPSHOT"
systemctl is-active --quiet unbound.service
systemctl is-active --quiet smbd.service
test -f /srv/control-center/storage/public/runtime-preserve.txt
[[ "$(curl -sS -o /dev/null -w '%{http_code}' -b "$DOMAIN_ADMIN_COOKIE" "$BASE/api/auth/session")" == 401 ]]
[[ "$(curl -sS -o /dev/null -w '%{http_code}' -b "$ADMIN_COOKIE" "$BASE/api/auth/session")" == 401 ]]
login local "$ADMIN_USER" "$ADMIN_PASS" "$ADMIN_COOKIE"

log 'Remove standalone Storage and verify artifacts/user data'
api "$ADMIN_COOKIE" POST /api/market/storage '{"action":"remove"}' >/dev/null
wait_json_state /var/lib/control-center-system/storage-status.json removed 'error|rollback|rejected' 300
test -f /srv/control-center/storage/public/runtime-preserve.txt
test ! -e /var/lib/control-center-system/modules/storage.json
LATEST_STORAGE_AUDIT=$(ls -1t /var/lib/control-center-system/cleanup-audits/storage-*.json|head -1)
sudo python3 - "$LATEST_STORAGE_AUDIT" <<'PY'
import json,sys
j=json.load(open(sys.argv[1]));assert j['clean'],j
PY

log 'Remove standalone DNS and verify artifacts'
api "$ADMIN_COOKIE" POST /api/market/dns '{"action":"remove"}' >/dev/null
wait_json_state /var/lib/control-center-system/dns-status.json removed 'error|rollback|rejected' 300
test ! -e /var/lib/control-center-system/modules/dns.json
test ! -e /etc/unbound/unbound.conf.d/control-center.conf
LATEST_DNS_AUDIT=$(ls -1t /var/lib/control-center-system/cleanup-audits/dns-*.json|head -1)
sudo python3 - "$LATEST_DNS_AUDIT" <<'PY'
import json,sys
j=json.load(open(sys.argv[1]));assert j['clean'],j
PY

log 'Bell, cleanup history, package integrity'
N=$(api "$ADMIN_COOKIE" GET /api/notifications);python3 - "$N" <<'PY'
import json,sys
j=json.loads(sys.argv[1]);sources={x.get('source') for x in j['items']};assert 'dns' in sources and 'storage' in sources and any(str(x).startswith('cleanup-') for x in sources)
PY
A=$(api "$ADMIN_COOKIE" GET /api/services/cleanup/audits);python3 - "$A" <<'PY'
import json,sys
j=json.loads(sys.argv[1]);services={x.get('service') for x in j['items']};assert {'domain','dns','storage'}.issubset(services);assert all(x.get('clean') for x in j['items'] if x.get('service') in {'domain','dns','storage'})
PY
sudo -u control-center psql -d control_center -Atqc "select count(*) from control_center.service_cleanup_audits where clean"|grep -Eq '^[1-9][0-9]*$' || true
test -z "$(dpkg --audit 2>&1||true)"
systemctl is-active --quiet control-center
systemctl is-active --quiet control-center-authd.service

echo 'RUNTIME ACCEPTANCE 1.0.11: PASSED'
