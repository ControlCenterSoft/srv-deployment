#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

BASE_URL="http://127.0.0.1:8876"
CREDS="/root/control-center-admin-credentials.txt"
WORK="$(mktemp -d /tmp/control-center-http-auth.XXXXXX)"
trap 'rm -rf "$WORK"' EXIT

[[ $EUID -eq 0 ]] || { echo "Run as root" >&2; exit 1; }
[[ -f "$CREDS" ]] || { echo "Missing $CREDS" >&2; exit 1; }

PUBLIC_IP="$(curl -4 -fsS --max-time 5 https://api.ipify.org 2>/dev/null || true)"
[[ -n "$PUBLIC_IP" ]] || PUBLIC_IP="$(hostname -I | awk '{print $1}')"
PUBLIC_ORIGIN="http://${PUBLIC_IP}:8876"

# Clear only in-memory sessions/login limiter. Persistent users/state are untouched.
systemctl restart control-center.service
for _ in {1..40}; do
  curl -fsS --max-time 2 "$BASE_URL/api/v1/readiness" >/dev/null 2>&1 && break
  sleep 0.25
done
curl -fsS "$BASE_URL/api/v1/readiness" >/dev/null

python3 - "$CREDS" > "$WORK/login.json" <<'PY'
import json,sys
vals={}
for line in open(sys.argv[1],encoding='utf-8'):
    if '=' in line:
        k,v=line.rstrip('\n').split('=',1); vals[k]=v
if not vals.get('username') or not vals.get('password'):
    raise SystemExit('credentials file is incomplete')
print(json.dumps({'username':vals['username'],'password':vals['password']}))
PY

code="$(curl -sS -D "$WORK/headers" -o "$WORK/body" -w '%{http_code}' \
  -H "Host: ${PUBLIC_IP}:8876" \
  -H "Origin: $PUBLIC_ORIGIN" \
  -H 'Content-Type: application/json' \
  --data-binary "@$WORK/login.json" \
  "$BASE_URL/api/v1/auth/login")"

echo "PUBLIC_IP=$PUBLIC_IP"
echo "PANEL_URL=$PUBLIC_ORIGIN"
echo "LOGIN_HTTP=$code"

if [[ "$code" != 200 ]]; then
  python3 - "$WORK/body" <<'PY'
import json,sys
try:
    d=json.load(open(sys.argv[1],encoding='utf-8'))
    e=d.get('error',{})
    print('ERROR_CODE='+str(e.get('code','unknown')))
    print('ERROR_MESSAGE='+str(e.get('message','unknown')))
except Exception:
    print('ERROR_CODE=non_json_response')
PY
  echo "SERVER_AUTH=FAILED"
  exit 1
fi

cookie="$(sed -n 's/^Set-Cookie: cc_session=\([^;]*\).*/\1/p' "$WORK/headers" | tr -d '\r' | head -1)"
[[ -n "$cookie" ]] || { echo "COOKIE=missing"; exit 1; }
if grep -qi '^Set-Cookie: cc_session=.*Secure' "$WORK/headers"; then
  echo "COOKIE_SECURE=true"
  echo "SERVER_AUTH=FAILED"
  echo "ERROR_CODE=secure_cookie_still_enabled"
  exit 1
else
  echo "COOKIE_SECURE=false"
fi

echo "COOKIE_HTTPONLY=$(grep -qi '^Set-Cookie: cc_session=.*HttpOnly' "$WORK/headers" && echo true || echo false)"
echo "COOKIE_SAMESITE_STRICT=$(grep -qi '^Set-Cookie: cc_session=.*SameSite=Strict' "$WORK/headers" && echo true || echo false)"

session_code="$(curl -sS -o "$WORK/session" -w '%{http_code}' \
  -H "Host: ${PUBLIC_IP}:8876" \
  -H "Cookie: cc_session=$cookie" \
  "$BASE_URL/api/v1/auth/session")"
echo "SESSION_HTTP=$session_code"
[[ "$session_code" == 200 ]] || { echo "SERVER_AUTH=FAILED"; exit 1; }

env_listen="$(grep '^CONTROL_CENTER_LISTEN=' /etc/control-center/control-center.env 2>/dev/null | tail -1 | cut -d= -f2- || true)"
env_insecure="$(grep '^CONTROL_CENTER_INSECURE_HTTP=' /etc/control-center/control-center.env 2>/dev/null | tail -1 | cut -d= -f2- || true)"
echo "LISTEN=$env_listen"
echo "INSECURE_HTTP=$env_insecure"
echo "PASSWORD_LENGTH=$(python3 - "$CREDS" <<'PY'
import sys
for line in open(sys.argv[1],encoding='utf-8'):
    if line.startswith('password='):
        print(len(line.rstrip('\n').split('=',1)[1])); break
PY
)"
echo "SERVER_AUTH=OK"
echo "BROWSER_ACTION=Open $PUBLIC_ORIGIN in a private/incognito window and enter username admin plus only the value after password=."
echo "PASSWORD_COMMAND=sed -n 's/^password=//p' $CREDS"
