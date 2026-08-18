#!/usr/bin/env bash
set -Eeuo pipefail
[[ ${EUID:-$(id -u)} -eq 0 ]] || { echo 'Запустите: sudo bash scripts/acceptance-1.0.6.sh' >&2; exit 2; }
EXPECTED=1.0.6
FAIL=0
pass(){ printf 'PASS  %s\n' "$*"; }
fail(){ printf 'FAIL  %s\n' "$*" >&2; FAIL=1; }
warn(){ printf 'WARN  %s\n' "$*"; }
json_get(){ curl -fsS --max-time 8 "http://127.0.0.1:8080$1"; }

printf 'Control Center %s acceptance\n\n' "$EXPECTED"

if [[ -r /opt/control-center/VERSION ]]; then
  V=$(tr -d '[:space:]' </opt/control-center/VERSION)
  [[ "$V" == "$EXPECTED" ]] && pass "version $V" || fail "version is $V, expected $EXPECTED"
else fail '/opt/control-center/VERSION is not readable'; fi

if HEALTH=$(json_get /api/health 2>/dev/null); then
  if python3 - "$HEALTH" "$EXPECTED" <<'PY'
import json,sys
j=json.loads(sys.argv[1]); exp=sys.argv[2]
assert j.get('status')=='ok'
assert j.get('product')=='Control Center'
assert j.get('version')==exp
assert j.get('build')
assert j.get('edition') in ('Home','Professional')
PY
  then pass 'health API / version / build'; else fail 'health API payload'; fi
else fail 'health API unreachable'; fi

HEADERS=$(curl -fsSI --max-time 5 http://127.0.0.1:8080/api/health 2>/dev/null || true)
grep -qi '^Content-Security-Policy:' <<<"$HEADERS" && pass 'HTTP CSP present' || fail 'HTTP CSP missing'
grep -qi "script-src 'self'" <<<"$HEADERS" && pass 'CSP uses external scripts only' || fail 'CSP script-src mismatch'
grep -qi 'unsafe-inline' <<<"$HEADERS" && fail 'CSP still contains unsafe-inline' || pass 'unsafe-inline removed'
grep -qi '^X-Content-Type-Options: nosniff' <<<"$HEADERS" && pass 'HTTP nosniff' || fail 'HTTP nosniff missing'

id control-center >/dev/null 2>&1 && pass 'service user control-center' || fail 'service user missing'
systemctl is-active --quiet control-center && pass 'control-center.service active' || fail 'control-center.service inactive'
UNIT=$(systemctl cat control-center 2>/dev/null || true)
grep -Fq '/gunicorn ' <<<"$UNIT" && grep -Fq 'wsgi:app' <<<"$UNIT" && pass 'Gunicorn WSGI configured' || fail 'Gunicorn WSGI missing'
grep -Fq 'ReadOnlyPaths=/var/lib/control-center-system /var/lib/control-center-license' <<<"$UNIT" && pass 'protected state read-only' || fail 'protected state isolation missing'
grep -Fq 'InaccessiblePaths=/var/lib/control-center-root' <<<"$UNIT" && pass 'rollback state inaccessible' || fail 'rollback state isolation missing'

if NET=$(json_get /api/network/config 2>/dev/null); then
  if python3 - "$NET" <<'PY'
import json,sys
j=json.loads(sys.argv[1])
assert isinstance(j.get('interfaces'),list)
assert isinstance(j.get('config'),dict)
assert 'wan' in j['config'] and 'lan' in j['config']
for x in j['interfaces']:
    for k in ('name','state','mac','mtu','ipv4','gateway','dns','kind'):
        assert k in x,(x,k)
PY
  then pass 'network inventory and hydrated config API'; else fail 'network API shape'; fi
else fail 'network API unreachable'; fi

if [[ -f /etc/netplan/90-control-center.yaml ]]; then
  OWNER=$(stat -c '%U:%G' /etc/netplan/90-control-center.yaml); MODE=$(stat -c '%a' /etc/netplan/90-control-center.yaml)
  [[ "$OWNER" == root:control-center && "$MODE" == 640 ]] && pass 'Control Center Netplan is read-only to Web group' || fail "Netplan permissions $OWNER $MODE"
  netplan generate >/dev/null 2>&1 && pass 'netplan generate' || fail 'netplan generate failed'
fi

if NOTIFY=$(json_get /api/notifications 2>/dev/null); then
  python3 - "$NOTIFY" <<'PY' && pass 'notification aggregation API' || fail 'notification API payload'
import json,sys
j=json.loads(sys.argv[1]); assert isinstance(j.get('items'),list)
for x in j['items']:
    assert x.get('id') and x.get('severity') in ('ok','error') and x.get('title')
PY
else fail 'notification API unreachable'; fi

if [[ -f /var/lib/control-center-system/modules/dhcp.json ]] && python3 - <<'PY' >/dev/null 2>&1
import json
j=json.load(open('/var/lib/control-center-system/modules/dhcp.json'))
raise SystemExit(0 if j.get('installed') else 1)
PY
then
  if D=$(json_get /api/dhcp/config 2>/dev/null); then
    if python3 - "$D" <<'PY'
import json,sys
j=json.loads(sys.argv[1]); c=j.get('config',{})
assert isinstance(c.get('extra_options',[]),list)
assert isinstance(j.get('service'),dict)
assert 'running' in j['service'] and 'configured' in j['service']
PY
    then pass 'DHCP hydration / extra options / service status API'; else fail 'DHCP API shape'; fi
  else fail 'DHCP API unreachable'; fi
  if grep -q '^dhcp-range=' /etc/dnsmasq.d/control-center-dhcp.conf 2>/dev/null; then
    dnsmasq --test --conf-file=/etc/dnsmasq.d/control-center-dhcp.conf >/dev/null 2>&1 && pass 'dnsmasq config valid' || fail 'dnsmasq config invalid'
    CHECK=$(curl -sS --max-time 8 -X POST -w '\n%{http_code}' http://127.0.0.1:8080/api/dhcp/check || true)
    CODE=${CHECK##*$'\n'}
    [[ "$CODE" == 200 ]] && pass 'DHCP configuration check endpoint' || fail "DHCP configuration check HTTP $CODE"
  else warn 'DHCP installed but not configured yet'; fi
else
  warn 'DHCP module not installed (allowed)'
fi

[[ -s /opt/control-center/app/static/app.js ]] && pass 'external application JavaScript installed' || fail 'app.js missing'
grep -Fq 'notificationBell' /opt/control-center/app/templates/index.html && pass 'notification bell UI present' || fail 'notification bell missing'
grep -Fq 'interfacesTable' /opt/control-center/app/templates/index.html && pass 'network interface table UI present' || fail 'network inventory UI missing'
grep -Fq '@media(max-width:900px)' /opt/control-center/app/static/app.css && grep -Fq 'mobile-nav-open' /opt/control-center/app/static/app.css && pass 'mobile off-canvas layout present' || fail 'mobile layout markers missing'

printf '\n'
if (( FAIL )); then printf 'ACCEPTANCE: FAILED\n' >&2; exit 1; fi
printf 'ACCEPTANCE: PASSED\n'
