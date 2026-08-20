#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

BASE_URL="http://127.0.0.1:8876"
CREDS="/root/control-center-admin-credentials.txt"
WORK="$(mktemp -d /tmp/control-center-browser-login-repair.XXXXXX)"
trap 'rm -rf "$WORK"' EXIT

[[ $EUID -eq 0 ]] || { echo "Run as root" >&2; exit 1; }
[[ -f "$CREDS" ]] || { echo "Missing $CREDS" >&2; exit 1; }

PUBLIC_IP="$(curl -4 -fsS --max-time 5 https://api.ipify.org 2>/dev/null || true)"
[[ -n "$PUBLIC_IP" ]] || PUBLIC_IP="$(hostname -I | awk '{print $1}')"
PUBLIC_ORIGIN="http://${PUBLIC_IP}:8876"

# Ensure temporary HTTP mode is still active.
grep -qx 'CONTROL_CENTER_LISTEN=0.0.0.0:8876' /etc/control-center/control-center.env || { echo "HTTP listen mode is not enabled" >&2; exit 1; }
grep -qx 'CONTROL_CENTER_INSECURE_HTTP=1' /etc/control-center/control-center.env || { echo "HTTP insecure-cookie mode is not enabled" >&2; exit 1; }

# Reset only in-memory sessions and login limiter.
systemctl restart control-center.service
for _ in {1..40}; do
  curl -fsS --max-time 2 "$BASE_URL/api/v1/readiness" >/dev/null 2>&1 && break
  sleep 0.25
done
curl -fsS "$BASE_URL/api/v1/readiness" >/dev/null

python3 - "$CREDS" > "$WORK/current-login.json" <<'PY'
import json,sys
vals={}
for line in open(sys.argv[1],encoding='utf-8'):
    if '=' in line:
        k,v=line.rstrip('\n').split('=',1); vals[k]=v
if not vals.get('username') or not vals.get('password'):
    raise SystemExit('credentials file is incomplete')
print(json.dumps({'username':vals['username'],'password':vals['password']}))
PY

code="$(curl -sS -D "$WORK/current-headers" -o "$WORK/current-body" -w '%{http_code}' \
  -H "Host: ${PUBLIC_IP}:8876" -H "Origin: $PUBLIC_ORIGIN" -H 'Content-Type: application/json' \
  --data-binary "@$WORK/current-login.json" "$BASE_URL/api/v1/auth/login")"
if [[ "$code" != 200 ]]; then
  echo "CURRENT_CREDENTIALS_HTTP=$code"
  python3 - "$WORK/current-body" <<'PY'
import json,sys
try:
 d=json.load(open(sys.argv[1])); e=d.get('error',{}); print('ERROR_CODE='+str(e.get('code','unknown'))); print('ERROR_MESSAGE='+str(e.get('message','unknown')))
except Exception:
 print('ERROR_CODE=non_json_response')
PY
  exit 1
fi

TOKEN="$(sed -n 's/^Set-Cookie: cc_session=\([^;]*\).*/\1/p' "$WORK/current-headers" | tr -d '\r' | head -1)"
CSRF="$(python3 - "$WORK/current-body" <<'PY'
import json,sys
print(json.load(open(sys.argv[1],encoding='utf-8'))['csrf_token'])
PY
)"
[[ -n "$TOKEN" && -n "$CSRF" ]] || { echo "Missing session material" >&2; exit 1; }
if grep -qi '^Set-Cookie: cc_session=.*Secure' "$WORK/current-headers"; then
  echo "ERROR_CODE=secure_cookie_still_enabled" >&2
  exit 1
fi

CURRENT_PASSWORD="$(sed -n 's/^password=//p' "$CREDS" | head -1)"
NEW_PASSWORD="$(python3 - <<'PY'
import secrets,string
alphabet=string.ascii_letters+string.digits
print(''.join(secrets.choice(alphabet) for _ in range(20)))
PY
)"
python3 - "$CURRENT_PASSWORD" "$NEW_PASSWORD" > "$WORK/change.json" <<'PY'
import json,sys
print(json.dumps({'current_password':sys.argv[1],'new_password':sys.argv[2]}))
PY
change_code="$(curl -sS -o "$WORK/change-body" -w '%{http_code}' \
  -H "Host: ${PUBLIC_IP}:8876" -H "Origin: $PUBLIC_ORIGIN" -H 'Content-Type: application/json' \
  -H "Cookie: cc_session=$TOKEN" -H "X-CSRF-Token: $CSRF" \
  --data-binary "@$WORK/change.json" "$BASE_URL/api/v1/auth/password")"
[[ "$change_code" == 200 ]] || { echo "PASSWORD_CHANGE_HTTP=$change_code"; cat "$WORK/change-body"; exit 1; }

printf 'username=admin\npassword=%s\n' "$NEW_PASSWORD" > "$CREDS"
chmod 0600 "$CREDS"

# Restart to clear all old sessions/limiter, then verify exactly like the public browser Origin/Host.
systemctl restart control-center.service
for _ in {1..40}; do
  curl -fsS --max-time 2 "$BASE_URL/api/v1/readiness" >/dev/null 2>&1 && break
  sleep 0.25
done
curl -fsS "$BASE_URL/api/v1/readiness" >/dev/null

python3 - "$NEW_PASSWORD" > "$WORK/new-login.json" <<'PY'
import json,sys
print(json.dumps({'username':'admin','password':sys.argv[1]}))
PY
new_code="$(curl -sS -D "$WORK/new-headers" -o "$WORK/new-body" -w '%{http_code}' \
  -H "Host: ${PUBLIC_IP}:8876" -H "Origin: $PUBLIC_ORIGIN" -H 'Content-Type: application/json' \
  --data-binary "@$WORK/new-login.json" "$BASE_URL/api/v1/auth/login")"
[[ "$new_code" == 200 ]] || { echo "NEW_LOGIN_HTTP=$new_code"; cat "$WORK/new-body"; exit 1; }
NEW_TOKEN="$(sed -n 's/^Set-Cookie: cc_session=\([^;]*\).*/\1/p' "$WORK/new-headers" | tr -d '\r' | head -1)"
[[ -n "$NEW_TOKEN" ]] || { echo "New session cookie missing" >&2; exit 1; }
! grep -qi '^Set-Cookie: cc_session=.*Secure' "$WORK/new-headers" || { echo "New cookie still Secure" >&2; exit 1; }
session_code="$(curl -sS -o /dev/null -w '%{http_code}' -H "Host: ${PUBLIC_IP}:8876" -H "Cookie: cc_session=$NEW_TOKEN" "$BASE_URL/api/v1/auth/session")"
[[ "$session_code" == 200 ]] || { echo "SESSION_HTTP=$session_code"; exit 1; }

echo "BROWSER_AUTH_REPAIRED=YES"
echo "PANEL_URL=$PUBLIC_ORIGIN"
echo "LOGIN=admin"
echo "NEW_PASSWORD=$NEW_PASSWORD"
echo "PASSWORD_FILE=$CREDS"
echo "LOGIN_HTTP=$new_code"
echo "SESSION_HTTP=$session_code"
echo "COOKIE_SECURE=false"
echo "ACTION=Close all old Control Center tabs, open a new private/incognito window, then use the URL/login/password printed above."
