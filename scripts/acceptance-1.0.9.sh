#!/usr/bin/env bash
set -Eeuo pipefail
[[ ${EUID:-$(id -u)} -eq 0 ]] || { echo 'Запустите: sudo bash scripts/acceptance-1.0.9.sh' >&2; exit 2; }
EXPECTED=1.0.9
BUILD=20260819.3
FAIL=0
pass(){ printf 'PASS  %s\n' "$*"; }
fail(){ printf 'FAIL  %s\n' "$*" >&2; FAIL=1; }

source /etc/control-center/web.env 2>/dev/null || true
PORT="${CONTROL_CENTER_PORT:-8080}"
SSL="${CONTROL_CENTER_SSL:-0}"
SCHEME=http; CURL=(-fsS --max-time 10)
if [[ "$SSL" == 1 || "$SSL" == true ]]; then SCHEME=https; CURL=(-kfsS --max-time 10); fi
api(){ curl "${CURL[@]}" "$SCHEME://127.0.0.1:${PORT}$1"; }

printf 'Control Center %s build %s acceptance\n\n' "$EXPECTED" "$BUILD"
[[ "$(tr -d '[:space:]' </opt/control-center/VERSION 2>/dev/null)" == "$EXPECTED" ]] && pass "version $EXPECTED" || fail 'VERSION mismatch'
[[ "$(tr -d '[:space:]' </opt/control-center/BUILD 2>/dev/null)" == "$BUILD" ]] && pass "build $BUILD" || fail 'BUILD mismatch'

H="$(api /api/health 2>/dev/null || true)"
python3 - "$H" "$EXPECTED" "$BUILD" <<'PY' && pass 'health/version/build' || fail 'health payload'
import json,sys
j=json.loads(sys.argv[1]);assert j.get('status')=='ok';assert j.get('version')==sys.argv[2];assert j.get('build')==sys.argv[3]
PY

S="$(api /api/system 2>/dev/null || true)"
python3 - "$S" <<'PY' && pass 'dashboard API: CPU/RAM top + LAN' || fail 'dashboard API shape'
import json,sys
j=json.loads(sys.argv[1]);assert isinstance(j.get('top_cpu'),list);assert isinstance(j.get('top_ram'),list);assert isinstance(j.get('lan'),dict);assert isinstance(j.get('storage'),list)
PY

W="$(api /api/settings/web 2>/dev/null || true)"
python3 - "$W" <<'PY' && pass 'Web settings: standard port + SSL' || fail 'Web settings shape'
import json,sys
j=json.loads(sys.argv[1]);
for k in ('port','runtime_port','ssl_enabled','runtime_ssl','standard_port','standard_http_port','standard_https_port','certificate'): assert k in j,k
assert j['standard_http_port']==80 and j['standard_https_port']==443
PY

P="$(api /api/samba/preflight 2>/dev/null || true)"
python3 - "$P" <<'PY' && pass 'Samba AD-DC preflight API' || fail 'Samba preflight shape'
import json,sys
j=json.loads(sys.argv[1]);assert 'ready' in j and isinstance(j.get('checks'),dict);assert j.get('details',{}).get('installation_enabled') is False
for k in ('fqdn','lan_static','time_sync','dns_port_53','samba_package'): assert k in j['checks'],k
PY

sudo -u control-center psql -d control_center -Atqc "select version from control_center.schema_migrations order by version desc limit 1" | grep -qx 002 && pass 'PostgreSQL migration 002' || fail 'migration 002 missing'
sudo -u control-center psql -d control_center -Atqc "select to_regclass('control_center.ad_dc_profiles') is not null" | grep -qx t && pass 'AD-DC schema tables' || fail 'AD-DC schema missing'

UNIT="$(systemctl cat control-center 2>/dev/null || true)"
grep -Fq 'ExecStart=/usr/local/sbin/control-center-web-run' <<<"$UNIT" && pass 'Web runtime wrapper configured' || fail 'Web runtime wrapper missing'
grep -Fq 'AmbientCapabilities=CAP_NET_BIND_SERVICE' <<<"$UNIT" && pass 'standard-port capability configured' || fail 'CAP_NET_BIND_SERVICE missing'
[[ -x /usr/local/sbin/control-center-web-run ]] && pass 'Web runtime wrapper installed' || fail 'Web runtime wrapper not installed'

JS="$(curl "${CURL[@]}" "$SCHEME://127.0.0.1:${PORT}/static/app.js?v=$EXPECTED" 2>/dev/null || true)"
for token in paginate109 topCpuProcesses topRamProcesses storageDonut109 lanChart webStandardPort webSsl runSambaPreflight; do grep -Fq "$token" <<<"$JS" || fail "UI token missing: $token"; done
(( FAIL == 0 )) && pass 'pagination/dashboard/SSL/Samba UI assets'

if [[ "$SSL" == 1 || "$SSL" == true ]]; then
  [[ -r /etc/control-center/tls/server.crt && -r /etc/control-center/tls/server.key ]] && pass 'SSL certificate/key present' || fail 'SSL certificate/key missing'
fi

printf '\n'
if (( FAIL )); then printf 'ACCEPTANCE: FAILED\n' >&2; exit 1; fi
printf 'ACCEPTANCE: PASSED\n'
