#!/usr/bin/env bash
set -Eeuo pipefail
[[ ${EUID:-$(id -u)} -eq 0 ]] || { echo 'Запустите: sudo bash scripts/acceptance-1.0.5.sh' >&2; exit 2; }
EXPECTED=1.0.5
FAIL=0
pass(){ printf 'PASS  %s\n' "$*"; }
fail(){ printf 'FAIL  %s\n' "$*" >&2; FAIL=1; }
warn(){ printf 'WARN  %s\n' "$*"; }
check_file(){ [[ -e "$1" ]] && pass "$1 exists" || fail "$1 missing"; }
printf 'Control Center %s acceptance\n\n' "$EXPECTED"

if [[ -r /opt/control-center/VERSION ]]; then
  V=$(tr -d '[:space:]' </opt/control-center/VERSION)
  [[ "$V" == "$EXPECTED" ]] && pass "version $V" || fail "version is $V, expected $EXPECTED"
else fail '/opt/control-center/VERSION is not readable'; fi

if HEALTH=$(curl -fsS --max-time 5 http://127.0.0.1:8080/api/health 2>/dev/null); then
  if python3 - "$HEALTH" "$EXPECTED" <<'PY'
import json,sys
j=json.loads(sys.argv[1]); exp=sys.argv[2]
assert j.get('status')=='ok'
assert j.get('product')=='Control Center'
assert j.get('version')==exp
assert j.get('edition') in ('Home','Professional')
PY
  then pass 'health API'; else fail 'health API payload'; fi
else fail 'health API unreachable'; fi

HEADERS=$(curl -fsSI --max-time 5 http://127.0.0.1:8080/api/health 2>/dev/null || true)
grep -qi '^Content-Security-Policy:' <<<"$HEADERS" && pass 'HTTP Content-Security-Policy' || fail 'HTTP CSP missing'
grep -qi '^X-Content-Type-Options: nosniff' <<<"$HEADERS" && pass 'HTTP nosniff' || fail 'HTTP nosniff missing'
grep -qi '^Cache-Control: no-store' <<<"$HEADERS" && pass 'API no-store cache policy' || fail 'API no-store missing'

id control-center >/dev/null 2>&1 && pass 'service user control-center' || fail 'service user missing'
systemctl is-active --quiet control-center && pass 'control-center.service active' || fail 'control-center.service inactive'
[[ "$(systemctl show -p User --value control-center)" == control-center ]] && pass 'Web service runs as control-center' || fail 'Web service user mismatch'

for unit in control-center-update.timer control-center-os-update.timer; do systemctl is-enabled --quiet "$unit" && pass "$unit enabled" || fail "$unit not enabled"; done
for unit in control-center-network-apply.path control-center-market-apply.path control-center-dhcp-apply.path control-center-license-apply.path; do systemctl is-enabled --quiet "$unit" && pass "$unit enabled" || fail "$unit not enabled"; done

check_file /etc/control-center/license-public.pem
openssl pkey -pubin -in /etc/control-center/license-public.pem -noout >/dev/null 2>&1 && pass 'Professional public key valid' || fail 'Professional public key invalid'

for d in /var/lib/control-center-root /var/lib/control-center-license; do
  if [[ -d "$d" ]]; then
    OWNER=$(stat -c '%U:%G' "$d"); MODE=$(stat -c '%a' "$d")
    [[ "$OWNER" == root:root ]] && pass "$d owner root:root" || fail "$d owner $OWNER"
    if [[ "$d" == /var/lib/control-center-root ]]; then [[ "$MODE" == 700 ]] && pass "$d mode 700" || fail "$d mode $MODE (expected 700)"; fi
  else fail "$d missing"; fi
done

if [[ -f /var/lib/control-center-license/license.json ]]; then
  OWNER=$(stat -c '%U:%G' /var/lib/control-center-license/license.json); MODE=$(stat -c '%a' /var/lib/control-center-license/license.json)
  [[ "$OWNER" == root:root ]] && pass 'Professional license owner root:root' || fail "Professional license owner $OWNER"
  (( (8#$MODE & 0022) == 0 )) && pass 'Professional license not group/world writable' || fail "Professional license unsafe mode $MODE"
fi

UNIT=$(systemctl cat control-center 2>/dev/null || true)
grep -Fq 'NoNewPrivileges=true' <<<"$UNIT" && pass 'NoNewPrivileges enabled' || fail 'NoNewPrivileges missing'
grep -Fq 'InaccessiblePaths=/var/lib/control-center-root' <<<"$UNIT" && pass 'root state hidden from Web service' || fail 'root state isolation missing'
grep -Fq '/gunicorn ' <<<"$UNIT" && grep -Fq 'wsgi:app' <<<"$UNIT" && pass 'Gunicorn WSGI configured' || fail 'Gunicorn WSGI missing'

if command -v netplan >/dev/null 2>&1; then netplan generate >/dev/null 2>&1 && pass 'netplan generate' || fail 'netplan generate failed'; fi

if [[ -f /var/lib/control-center/modules/dhcp.json ]]; then
  INSTALLED=$(python3 - /var/lib/control-center/modules/dhcp.json <<'PY'
import json,sys
try:j=json.load(open(sys.argv[1]))
except:j={}
print('true' if j.get('installed') else 'false')
PY
)
  if [[ "$INSTALLED" == true ]]; then
    check_file /etc/dnsmasq.d/control-center-dhcp.conf
    if grep -q '^dhcp-range=' /etc/dnsmasq.d/control-center-dhcp.conf 2>/dev/null; then
      dnsmasq --test --conf-file=/etc/dnsmasq.d/control-center-dhcp.conf >/dev/null 2>&1 && pass 'Control Center DHCP config valid' || fail 'Control Center DHCP config invalid'
      systemctl is-active --quiet control-center-dhcp-server.service && pass 'dedicated DHCP runtime active' || fail 'dedicated DHCP runtime inactive'
      systemctl is-active --quiet dnsmasq.service && fail 'distribution dnsmasq.service must not run for managed DHCP' || pass 'distribution dnsmasq.service isolated'
    else warn 'DHCP module installed but not configured yet'; fi
  fi
elif dpkg-query -W -f='${Status}' dnsmasq 2>/dev/null | grep -q 'install ok installed'; then
  warn 'dnsmasq exists outside Control Center; Market will not adopt it automatically'
fi

printf '\n'
if (( FAIL )); then printf 'ACCEPTANCE: FAILED\n' >&2; exit 1; fi
printf 'ACCEPTANCE: PASSED\n'
