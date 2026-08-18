#!/usr/bin/env bash
set -Eeuo pipefail

fail(){ echo "ACCEPTANCE FAIL: $*" >&2; exit 1; }
pass(){ echo "PASS: $*"; }

[[ -s /opt/control-center/app/control_center.py ]] || fail "application missing"
[[ -s /opt/control-center/app/static/style.css ]] || fail "stylesheet missing"
[[ -s /etc/control-center/session.key ]] || fail "session key missing"
[[ -L /etc/nginx/sites-enabled/control-center ]] || fail "nginx site not enabled"
systemctl is-active --quiet control-center-web.service || fail "web service inactive"
systemctl is-active --quiet nginx.service || fail "nginx inactive"
nginx -t >/dev/null 2>&1 || fail "nginx config invalid"

backend="$(curl -fsS http://127.0.0.1:8876/api/v1/health)" || fail "backend health unavailable"
proxy="$(curl -fsS http://127.0.0.1/api/v1/health)" || fail "proxy health unavailable"

python3 - "$backend" "$proxy" <<'PY'
import json,sys
for raw in sys.argv[1:]:
    p=json.loads(raw)
    assert p.get('status') == 'ok', p
    assert p.get('product') == 'Control Center', p
    assert p.get('version') == '2.2.0', p
PY
pass "health contract"

login="$(curl -fsS http://127.0.0.1/login)" || fail "login page unavailable"
grep -Fq 'CONTROL CENTER' <<<"$login" || fail "branding missing"
grep -Fq 'Вход в систему' <<<"$login" || fail "login form missing"
pass "login shell"

code="$(curl -sS -o /dev/null -w '%{http_code}' http://127.0.0.1/overview)"
[[ "$code" == "302" ]] || fail "protected route did not redirect to login (HTTP $code)"
pass "protected overview route"

grep -Fq '("overview", "Обзор")' /opt/control-center/app/control_center.py || fail "Overview menu contract missing"
grep -Fq '("market", "Маркет")' /opt/control-center/app/control_center.py || fail "Market menu contract missing"
grep -Fq '("rbac", "RBAC")' /opt/control-center/app/control_center.py || fail "RBAC menu contract missing"
grep -Fq '("system", "Система")' /opt/control-center/app/control_center.py || fail "System menu contract missing"
pass "2.2 navigation contract"

echo "CONTROL CENTER 2.2.0 ACCEPTANCE PASS"
