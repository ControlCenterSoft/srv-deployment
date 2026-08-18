#!/usr/bin/env bash
set -Eeuo pipefail
[[ ${EUID:-$(id -u)} -eq 0 ]] || { echo 'Запустите: sudo bash scripts/acceptance-1.0.7.sh' >&2; exit 2; }
EXPECTED=1.0.7
EXPECTED_BUILD=20260818.2
FAIL=0
pass(){ printf 'PASS  %s\n' "$*"; }
fail(){ printf 'FAIL  %s\n' "$*" >&2; FAIL=1; }
warn(){ printf 'WARN  %s\n' "$*"; }
PORT="$(sed -n 's/^CONTROL_CENTER_PORT=\([0-9][0-9]*\)$/\1/p' /etc/control-center/web.env 2>/dev/null | head -n1)"
[[ "$PORT" =~ ^[0-9]+$ ]] || PORT=8080
json_get(){ curl -fsS --max-time 8 "http://127.0.0.1:${PORT}$1"; }

printf 'Control Center %s build %s acceptance\n\n' "$EXPECTED" "$EXPECTED_BUILD"

V=$(tr -d '[:space:]' </opt/control-center/VERSION 2>/dev/null || true)
B=$(tr -d '[:space:]' </opt/control-center/BUILD 2>/dev/null || true)
[[ "$V" == "$EXPECTED" ]] && pass "version $V" || fail "version is $V, expected $EXPECTED"
[[ "$B" == "$EXPECTED_BUILD" ]] && pass "build $B" || fail "build is $B, expected $EXPECTED_BUILD"
[[ "$PORT" -ge 1024 && "$PORT" -le 65535 ]] && pass "configured Web port $PORT" || fail "invalid Web port $PORT"

if HEALTH=$(json_get /api/health 2>/dev/null); then
  if python3 - "$HEALTH" "$EXPECTED" "$EXPECTED_BUILD" <<'PY'
import json,sys
j=json.loads(sys.argv[1]); version=sys.argv[2]; build=sys.argv[3]
assert j.get('status')=='ok'
assert j.get('product')=='Control Center'
assert j.get('version')==version
assert j.get('build')==build
assert j.get('edition') in ('Home','Professional')
assert j.get('database')=='ok'
PY
  then pass 'health API / version / build / PostgreSQL'; else fail 'health API payload'; fi
else fail "health API unreachable on port $PORT"; fi

HEADERS=$(curl -fsSI --max-time 5 "http://127.0.0.1:${PORT}/api/health" 2>/dev/null || true)
grep -qi '^Content-Security-Policy:' <<<"$HEADERS" && pass 'HTTP CSP present' || fail 'HTTP CSP missing'
grep -qi "script-src 'self'" <<<"$HEADERS" && pass 'CSP external scripts only' || fail 'CSP script-src mismatch'
grep -qi 'unsafe-inline' <<<"$HEADERS" && fail 'CSP contains unsafe-inline' || pass 'unsafe-inline absent'

systemctl is-active --quiet postgresql && pass 'PostgreSQL service active' || fail 'PostgreSQL service inactive'
if runuser -u control-center -- psql -d control_center -Atqc 'select current_user,current_database()' 2>/dev/null | grep -qx 'control-center|control_center'; then
  pass 'local PostgreSQL peer connection as control-center'
else
  fail 'local PostgreSQL peer connection failed'
fi

if DB=$(json_get /api/database/status 2>/dev/null); then
  if python3 - "$DB" <<'PY'
import json,sys
j=json.loads(sys.argv[1])
assert j.get('ok') is True
assert j.get('database')=='control_center'
assert j.get('role')=='control-center'
assert j.get('schema')=='control_center'
assert j.get('driver')=='psycopg3'
assert j.get('cluster_ready') is True
assert isinstance(j.get('nodes'),list) and len(j['nodes'])>=1
assert j.get('migration',{}).get('version')=='001'
PY
  then pass 'PostgreSQL API/schema/migration/cluster-node registration'; else fail 'database status API payload'; fi
else fail 'database status API unreachable'; fi

TABLES=$(runuser -u control-center -- psql -d control_center -Atqc "select tablename from pg_tables where schemaname='control_center' order by tablename" 2>/dev/null || true)
for t in schema_migrations settings notification_events audit_events jobs module_inventory service_configs cluster_nodes; do
  grep -qx "$t" <<<"$TABLES" && pass "PostgreSQL table $t" || fail "PostgreSQL table $t missing"
done

id control-center >/dev/null 2>&1 && pass 'service user control-center' || fail 'service user missing'
systemctl is-active --quiet control-center && pass 'control-center.service active' || fail 'control-center.service inactive'
systemctl is-enabled --quiet control-center-web-apply.path && pass 'web port apply watcher enabled' || fail 'web port apply watcher disabled'
UNIT=$(systemctl cat control-center 2>/dev/null || true)
grep -Fq 'EnvironmentFile=-/etc/control-center/database.env' <<<"$UNIT" && pass 'database environment wired to Web service' || fail 'database EnvironmentFile missing'
grep -Fq 'EnvironmentFile=-/etc/control-center/web.env' <<<"$UNIT" && pass 'Web-port environment wired to Web service' || fail 'web EnvironmentFile missing'
grep -Fq '0.0.0.0:${CONTROL_CENTER_PORT}' <<<"$UNIT" && pass 'Gunicorn bind uses configured Web port' || fail 'dynamic Gunicorn port missing'

if WEB=$(json_get /api/settings/web 2>/dev/null); then
  if python3 - "$WEB" "$PORT" <<'PY'
import json,sys
j=json.loads(sys.argv[1]); port=int(sys.argv[2])
assert int(j.get('runtime_port'))==port
assert int(j.get('port'))==port
assert j.get('min_port')==1024 and j.get('max_port')==65535
PY
  then pass 'Web-port settings API'; else fail 'Web-port settings API payload'; fi
else fail 'Web-port settings API unreachable'; fi

if NET=$(json_get /api/network/config 2>/dev/null); then
  python3 - "$NET" <<'PY' && pass 'network inventory/hydrated configuration API' || fail 'network API shape'
import json,sys
j=json.loads(sys.argv[1]); assert isinstance(j.get('interfaces'),list); assert isinstance(j.get('config'),dict)
assert 'wan' in j['config'] and 'lan' in j['config']
PY
else fail 'network API unreachable'; fi

if NOTIFY=$(json_get /api/notifications 2>/dev/null); then
  python3 - "$NOTIFY" <<'PY' && pass 'PostgreSQL notification persistence API' || fail 'notification API payload'
import json,sys
j=json.loads(sys.argv[1]); assert isinstance(j.get('items'),list); assert j.get('persistence')=='postgresql'
for x in j['items']:
    assert 'read' in x and x.get('severity') in ('ok','error','info')
PY
else fail 'notification API unreachable'; fi

if [[ -f /etc/netplan/90-control-center.yaml ]]; then
  netplan generate >/dev/null 2>&1 && pass 'netplan generate' || fail 'netplan generate failed'
fi

if [[ -f /var/lib/control-center-system/modules/dhcp.json ]] && python3 - <<'PY' >/dev/null 2>&1
import json
j=json.load(open('/var/lib/control-center-system/modules/dhcp.json'))
raise SystemExit(0 if j.get('installed') else 1)
PY
then
  if D=$(json_get /api/dhcp/config 2>/dev/null); then
    python3 - "$D" <<'PY' && pass 'DHCP hydration/status API' || fail 'DHCP API shape'
import json,sys
j=json.loads(sys.argv[1]); assert isinstance(j.get('config',{}).get('extra_options',[]),list); assert isinstance(j.get('service'),dict)
PY
  else fail 'DHCP API unreachable'; fi
  if grep -q '^dhcp-range=' /etc/dnsmasq.d/control-center-dhcp.conf 2>/dev/null; then
    dnsmasq --test --conf-file=/etc/dnsmasq.d/control-center-dhcp.conf >/dev/null 2>&1 && pass 'dnsmasq config valid' || fail 'dnsmasq config invalid'
  else warn 'DHCP installed but not configured yet'; fi
else warn 'DHCP module not installed (allowed)'; fi

printf '\n'
if (( FAIL )); then printf 'ACCEPTANCE: FAILED\n' >&2; exit 1; fi
printf 'ACCEPTANCE: PASSED\n'
