#!/usr/bin/env bash
set -Eeuo pipefail

BASE_URL="${CONTROL_CENTER_ACCEPTANCE_URL:-http://127.0.0.1:8876}"
SECRET_FILE="${CONTROL_CENTER_BOOTSTRAP_SECRET:-/var/lib/control-center/bootstrap-admin.secret}"
work="$(mktemp -d /tmp/control-center-auth-acceptance.XXXXXX)"
trap 'rm -rf -- "$work"' EXIT
chmod 0700 "$work"

fail() { printf 'AUTH ACCEPTANCE FAILED: %s\n' "$*" >&2; exit 1; }
json_get() {
  python3 - "$1" "$2" <<'PY'
import json,sys
path,key=sys.argv[1],sys.argv[2]
obj=json.load(open(path,encoding='utf-8'))
for part in key.split('.'):
    obj=obj[part]
print(obj)
PY
}
bootstrap_get() {
  python3 - "$SECRET_FILE" "$1" <<'PY'
import sys
path,key=sys.argv[1],sys.argv[2]
vals={}
for line in open(path,encoding='utf-8'):
    if '=' in line:
        k,v=line.rstrip('\n').split('=',1); vals[k]=v
print(vals[key])
PY
}
login() {
  local username="$1" password="$2" prefix="$3"
  python3 - "$username" "$password" > "$work/$prefix-login.json" <<'PY'
import json,sys
print(json.dumps({'username':sys.argv[1],'password':sys.argv[2]}))
PY
  curl -sS -D "$work/$prefix-headers" -o "$work/$prefix-body" \
    -H 'Content-Type: application/json' -H "Origin: $BASE_URL" \
    --data-binary "@$work/$prefix-login.json" "$BASE_URL/api/v1/auth/login"
  grep -q '^HTTP/.* 200' "$work/$prefix-headers" || fail "$username login failed"
  grep -qi '^Set-Cookie: cc_session=.*HttpOnly' "$work/$prefix-headers" || fail "HttpOnly session cookie missing"
  grep -qi '^Set-Cookie: cc_session=.*Secure' "$work/$prefix-headers" || fail "Secure session cookie missing"
  grep -qi '^Set-Cookie: cc_session=.*SameSite=Strict' "$work/$prefix-headers" || fail "SameSite=Strict session cookie missing"
  sed -n 's/^Set-Cookie: cc_session=\([^;]*\).*/\1/p' "$work/$prefix-headers" | tr -d '\r' | head -1 > "$work/$prefix-token"
  json_get "$work/$prefix-body" csrf_token > "$work/$prefix-csrf"
  [[ -s "$work/$prefix-token" && -s "$work/$prefix-csrf" ]] || fail "session material missing"
}

[[ -f "$SECRET_FILE" ]] || fail "bootstrap secret is missing"
username="$(bootstrap_get username)"
password="$(bootstrap_get password)"
login "$username" "$password" admin
admin_token="$(cat "$work/admin-token")"
admin_csrf="$(cat "$work/admin-csrf")"

code="$(curl -sS -o "$work/session" -w '%{http_code}' -H "Cookie: cc_session=$admin_token" "$BASE_URL/api/v1/auth/session")"
[[ "$code" == 200 ]] || fail "authenticated session lookup failed"

new_password='alpha2-acceptance-password-123'
python3 - "$password" "$new_password" > "$work/password.json" <<'PY'
import json,sys
print(json.dumps({'current_password':sys.argv[1],'new_password':sys.argv[2]}))
PY
code="$(curl -sS -o "$work/password-body" -w '%{http_code}' -H 'Content-Type: application/json' -H "Origin: $BASE_URL" -H "Cookie: cc_session=$admin_token" -H "X-CSRF-Token: $admin_csrf" --data-binary "@$work/password.json" "$BASE_URL/api/v1/auth/password")"
[[ "$code" == 200 ]] || fail "password rotation failed"
[[ ! -e "$SECRET_FILE" ]] || fail "bootstrap secret survived password rotation"
code="$(curl -sS -o /dev/null -w '%{http_code}' -H "Cookie: cc_session=$admin_token" "$BASE_URL/api/v1/auth/session")"
[[ "$code" == 401 ]] || fail "old session was not revoked"

login "$username" "$new_password" admin2
admin_token="$(cat "$work/admin2-token")"; admin_csrf="$(cat "$work/admin2-csrf")"
cat > "$work/viewer.json" <<'JSON'
{"username":"viewer","password":"viewer-acceptance-password-123","role":"viewer"}
JSON
code="$(curl -sS -o "$work/create-viewer" -w '%{http_code}' -H 'Content-Type: application/json' -H "Origin: $BASE_URL" -H "Cookie: cc_session=$admin_token" -H "X-CSRF-Token: $admin_csrf" --data-binary "@$work/viewer.json" "$BASE_URL/api/v1/rbac/users")"
[[ "$code" == 201 ]] || fail "admin could not create viewer"

login viewer 'viewer-acceptance-password-123' viewer
viewer_token="$(cat "$work/viewer-token")"; viewer_csrf="$(cat "$work/viewer-csrf")"
code="$(curl -sS -o /dev/null -w '%{http_code}' -H "Cookie: cc_session=$viewer_token" "$BASE_URL/api/v1/system/status")"
[[ "$code" == 200 ]] || fail "viewer read permission failed"
cat > "$work/forbidden-user.json" <<'JSON'
{"username":"forbidden","password":"forbidden-password-123","role":"viewer"}
JSON
code="$(curl -sS -o /dev/null -w '%{http_code}' -H 'Content-Type: application/json' -H "Origin: $BASE_URL" -H "Cookie: cc_session=$viewer_token" -H "X-CSRF-Token: $viewer_csrf" --data-binary "@$work/forbidden-user.json" "$BASE_URL/api/v1/rbac/users")"
[[ "$code" == 403 ]] || fail "viewer privileged write was not denied"

printf 'Auth/RBAC acceptance passed.\n'
