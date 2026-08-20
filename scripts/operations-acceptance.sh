#!/usr/bin/env bash
set -Eeuo pipefail

BASE_URL="${CONTROL_CENTER_ACCEPTANCE_URL:-http://127.0.0.1:8876}"
ADMIN_USER="${CONTROL_CENTER_ACCEPTANCE_ADMIN:-admin}"
ADMIN_PASSWORD="${CONTROL_CENTER_ACCEPTANCE_PASSWORD:-alpha2-acceptance-password-123}"
work="$(mktemp -d /tmp/control-center-operations-acceptance.XXXXXX)"
trap 'rm -rf -- "$work"' EXIT
chmod 0700 "$work"

fail() { printf 'OPERATIONS ACCEPTANCE FAILED: %s\n' "$*" >&2; exit 1; }
python3 - "$ADMIN_USER" "$ADMIN_PASSWORD" > "$work/login.json" <<'PY'
import json,sys
print(json.dumps({'username':sys.argv[1],'password':sys.argv[2]}))
PY
code="$(curl -sS -D "$work/headers" -o "$work/login-body" -w '%{http_code}' -H 'Content-Type: application/json' -H "Origin: $BASE_URL" --data-binary "@$work/login.json" "$BASE_URL/api/v1/auth/login")"
[[ "$code" == 200 ]] || fail "admin login failed"
token="$(sed -n 's/^Set-Cookie: cc_session=\([^;]*\).*/\1/p' "$work/headers" | tr -d '\r' | head -1)"
[[ -n "$token" ]] || fail "session cookie missing"

for endpoint in operations audit diagnostics/summary; do
  code="$(curl -sS -o "$work/${endpoint//\//-}.json" -w '%{http_code}' -H "Cookie: cc_session=$token" "$BASE_URL/api/v1/$endpoint")"
  [[ "$code" == 200 ]] || fail "$endpoint returned $code"
done

grep -q 'rbac.user.create' "$work/operations.json" || fail "expected traced operation missing"
grep -q 'auth.login' "$work/audit.json" || fail "expected audit login event missing"
grep -q '"audit_readable":true' "$work/diagnostics-summary.json" || fail "diagnostic summary does not report audit readable"

code="$(curl -sS -o "$work/diagnostics.tar.gz" -w '%{http_code}' -H "Cookie: cc_session=$token" "$BASE_URL/api/v1/diagnostics/export")"
[[ "$code" == 200 ]] || fail "diagnostic export returned $code"
for name in manifest.json version.json runtime.json users.json audit.json operations.json; do
  tar -tzf "$work/diagnostics.tar.gz" | grep -qx "$name" || fail "diagnostic archive missing $name"
done
expanded="$work/expanded.txt"
: > "$expanded"
for name in manifest.json version.json runtime.json users.json audit.json operations.json; do
  tar -xOzf "$work/diagnostics.tar.gz" "$name" >> "$expanded"
done
! grep -q 'pbkdf2-sha256' "$expanded" || fail "password hash material leaked into diagnostics"
! grep -q 'bootstrap-admin.secret' "$expanded" || fail "bootstrap secret path leaked into diagnostics"
! grep -q 'cc_session' "$expanded" || fail "session token material leaked into diagnostics"

printf 'Operations/diagnostics acceptance passed.\n'
