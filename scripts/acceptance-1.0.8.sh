#!/usr/bin/env bash
set -Eeuo pipefail
[[ ${EUID:-$(id -u)} -eq 0 ]] || { echo 'Запустите: sudo bash scripts/acceptance-1.0.8.sh' >&2; exit 2; }
EXPECTED=1.0.8
BUILD=20260819.2
FAIL=0
pass(){ printf 'PASS  %s\n' "$*"; }
fail(){ printf 'FAIL  %s\n' "$*" >&2; FAIL=1; }
warn(){ printf 'WARN  %s\n' "$*"; }
PORT="$(sed -n 's/^CONTROL_CENTER_PORT=\([0-9][0-9]*\)$/\1/p' /etc/control-center/web.env 2>/dev/null | head -n1)"
PORT="${PORT:-8080}"
api(){ curl -fsS --max-time 10 "http://127.0.0.1:${PORT}$1"; }

printf 'Control Center %s build %s acceptance\n\n' "$EXPECTED" "$BUILD"

[[ "$(tr -d '[:space:]' </opt/control-center/VERSION 2>/dev/null)" == "$EXPECTED" ]] && pass "version $EXPECTED" || fail 'VERSION mismatch'
[[ "$(tr -d '[:space:]' </opt/control-center/BUILD 2>/dev/null)" == "$BUILD" ]] && pass "build $BUILD" || fail 'BUILD mismatch'

if H="$(api /api/health 2>/dev/null)"; then
  python3 - "$H" "$EXPECTED" "$BUILD" <<'PY' && pass 'health/version/build' || fail 'health payload'
import json,sys
j=json.loads(sys.argv[1]); assert j.get('status')=='ok'; assert j.get('version')==sys.argv[2]; assert j.get('build')==sys.argv[3]
PY
else fail 'health API unreachable'; fi

if M="$(api /api/market 2>/dev/null)"; then
  python3 - "$M" <<'PY' && pass 'Market persistent service status API' || fail 'Market status API shape'
import json,sys
j=json.loads(sys.argv[1]); items=j.get('items'); assert isinstance(items,list) and len(items)>=4
for x in items:
    s=x.get('status') or {}
    assert s.get('code') in {'available','installing','removing','running','error','planned'},x
    assert s.get('label') and 'detail' in s,x
assert any(x.get('id')=='dhcp' and x.get('installable') for x in items)
PY
else fail 'Market API unreachable'; fi

if U="$(api /api/settings/update/check 2>/dev/null)"; then
  python3 - "$U" <<'PY' && pass 'update availability API' || fail 'update availability payload'
import json,sys
j=json.loads(sys.argv[1]); assert isinstance(j.get('update_available'),bool); assert j.get('current_version'); assert 'remote' in j
PY
else fail 'update check API unreachable'; fi

systemctl is-active --quiet control-center-update-now.path && pass 'manual update path watcher active' || fail 'control-center-update-now.path inactive'
systemctl is-enabled --quiet control-center-update-now.path && pass 'manual update path watcher enabled' || fail 'control-center-update-now.path disabled'
[[ -x /usr/local/sbin/control-center-update ]] && pass 'update wrapper installed' || fail 'update wrapper missing'
[[ -x /usr/local/lib/control-center/control-center-update-base-1.0.7 ]] && pass 'version/build updater base installed' || fail 'updater base missing'
[[ -x /usr/local/lib/control-center/control-center-os-update-base-1.0.8 ]] && pass 'OS updater base installed' || fail 'OS updater base missing'
[[ -x /usr/local/lib/control-center/control-center-market-apply-base-1.0.8 ]] && pass 'Market helper base installed' || fail 'Market helper base missing'

JS="$(curl -fsS --max-time 10 "http://127.0.0.1:${PORT}/static/app.js?v=${EXPECTED}" 2>/dev/null || true)"
grep -Fq 'market108' <<<"$JS" && grep -Fq 'installUpdate' <<<"$JS" && pass '1.0.8 Market/update UI overlay served' || fail '1.0.8 JS overlay missing'
CSS="$(curl -fsS --max-time 10 "http://127.0.0.1:${PORT}/static/app.css?v=${EXPECTED}" 2>/dev/null || true)"
grep -Fq 'service-runtime-status' <<<"$CSS" && pass 'service status badge CSS served' || fail '1.0.8 CSS overlay missing'

if N="$(api /api/notifications 2>/dev/null)"; then
  python3 - "$N" <<'PY' && pass 'PostgreSQL notifications available' || fail 'notifications payload'
import json,sys
j=json.loads(sys.argv[1]); assert isinstance(j.get('items'),list); assert j.get('persistence') in {'postgresql','degraded'}
PY
else fail 'notifications API unreachable'; fi

if [[ -s /var/lib/control-center-system/market-events.jsonl ]]; then
  python3 - <<'PY' && pass 'Market event journal valid JSONL' || fail 'Market event journal invalid'
import json
for line in open('/var/lib/control-center-system/market-events.jsonl',encoding='utf-8'):
    if line.strip():
        j=json.loads(line); assert j.get('service') and j.get('timestamp')
PY
else warn 'Market event journal empty (no install/remove operation yet)'; fi

if [[ -f /var/lib/control-center-system/modules/dhcp.json ]]; then
  if python3 - <<'PY' >/dev/null 2>&1
import json
j=json.load(open('/var/lib/control-center-system/modules/dhcp.json')); raise SystemExit(0 if j.get('installed') else 1)
PY
  then
    dpkg-query -W -f='${Status}' dnsmasq 2>/dev/null | grep -q 'install ok installed' && pass 'DHCP package installed' || fail 'DHCP state exists but dnsmasq package missing'
    dnsmasq --test --conf-file=/etc/dnsmasq.d/control-center-dhcp.conf >/dev/null 2>&1 && pass 'DHCP config passes dnsmasq --test' || fail 'DHCP config invalid'
  fi
fi

if dpkg --audit | grep -q .; then
  fail 'dpkg reports half-configured/unpacked packages'
else
  pass 'dpkg package database clean'
fi

printf '\n'
if (( FAIL )); then printf 'ACCEPTANCE: FAILED\n' >&2; exit 1; fi
printf 'ACCEPTANCE: PASSED\n'
