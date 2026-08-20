#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

PRODUCT_COMMIT="5af3a76fcbb52053d5002dea4b40f6e1783ab949"
REPO="https://github.com/ControlCenterSoft/srv-deployment.git"
WORK="/opt/control-center-web-login-ui-fix"
SRC="$WORK/source"
BIN="/usr/local/lib/control-center/control-center"
ENV_FILE="/etc/control-center/control-center.env"
CREDS="/root/control-center-admin-credentials.txt"
BASE_URL="http://127.0.0.1:8876"
BACKUP="$WORK/control-center.before-ui-fix"

[[ $EUID -eq 0 ]] || { echo "Run as root" >&2; exit 1; }
mkdir -p "$WORK"; chmod 0700 "$WORK"
for c in git go python3 curl systemctl sha256sum; do command -v "$c" >/dev/null || { echo "Missing command: $c" >&2; exit 1; }; done
[[ -f "$BIN" && -f "$ENV_FILE" && -f "$CREDS" ]] || { echo "Control Center alpha.3 test installation is incomplete" >&2; exit 1; }
grep -qx 'CONTROL_CENTER_LISTEN=0.0.0.0:8876' "$ENV_FILE" || { echo "Temporary HTTP/IP mode is not enabled" >&2; exit 1; }
grep -qx 'CONTROL_CENTER_INSECURE_HTTP=1' "$ENV_FILE" || { echo "Temporary insecure HTTP cookie mode is not enabled" >&2; exit 1; }
cp -a "$BIN" "$BACKUP"

rollback() {
  rc=$?
  trap - ERR
  echo "UI hotfix failed; restoring previous binary."
  install -m 0755 "$BACKUP" "$BIN" || true
  systemctl restart control-center.service || true
  exit "$rc"
}
trap rollback ERR

rm -rf "$SRC"
mkdir -p "$SRC"
git -C "$WORK" init -q source
git -C "$SRC" remote add origin "$REPO"
git -C "$SRC" fetch -q --depth=1 origin "$PRODUCT_COMMIT"
git -C "$SRC" checkout -q --detach FETCH_HEAD
[[ "$(git -C "$SRC" rev-parse HEAD)" == "$PRODUCT_COMMIT" ]]

# Preserve the explicitly requested temporary HTTP/IP test mode.
python3 - "$SRC/internal/httpserver/server.go" <<'PY'
from pathlib import Path
import sys
p=Path(sys.argv[1])
s=p.read_text()
old='Secure: true, SameSite: http.SameSiteStrictMode'
if s.count(old) != 2:
    raise SystemExit(f'unexpected Secure-cookie pattern count: {s.count(old)}')
s=s.replace(old, 'Secure: secureSessionCookies(), SameSite: http.SameSiteStrictMode')
marker='func decodeJSON(r *http.Request, out any) error {'
helper='''func secureSessionCookies() bool {\n\treturn strings.TrimSpace(os.Getenv("CONTROL_CENTER_INSECURE_HTTP")) != "1"\n}\n'''
if marker not in s:
    raise SystemExit('decodeJSON marker missing')
s=s.replace(marker, helper+'\n'+marker, 1)
p.write_text(s)
PY

cd "$SRC"
gofmt -w internal/httpserver/server.go
test -z "$(gofmt -l .)"
go vet ./...
go test ./...
CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -trimpath \
  -ldflags "-s -w -X github.com/ControlCenterSoft/srv-deployment/internal/buildinfo.Version=1.0.0-alpha.3+testhttp-ui-fix -X github.com/ControlCenterSoft/srv-deployment/internal/buildinfo.Commit=${PRODUCT_COMMIT}-testhttp -X github.com/ControlCenterSoft/srv-deployment/internal/buildinfo.BuiltAt=$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  -o "$WORK/control-center-fixed" ./cmd/control-center

install -m 0755 "$WORK/control-center-fixed" "$BIN"
systemctl restart control-center.service
for _ in {1..40}; do
  curl -fsS --max-time 2 "$BASE_URL/api/v1/readiness" >/dev/null 2>&1 && break
  sleep 0.25
done
curl -fsS "$BASE_URL/api/v1/readiness" >/dev/null

# Verify the embedded UI contract is actually served by the installed binary.
curl -fsS "$BASE_URL/styles.css" -o "$WORK/styles.css"
grep -Fq '[hidden] { display: none !important; }' "$WORK/styles.css"

PUBLIC_IP="$(curl -4 -fsS --max-time 5 https://api.ipify.org 2>/dev/null || true)"
[[ -n "$PUBLIC_IP" ]] || PUBLIC_IP="$(hostname -I | awk '{print $1}')"
PUBLIC_ORIGIN="http://${PUBLIC_IP}:8876"
AUTH_WORK="$(mktemp -d /tmp/control-center-ui-auth.XXXXXX)"
chmod 0700 "$AUTH_WORK"
python3 - "$CREDS" > "$AUTH_WORK/login.json" <<'PY'
import json,sys
vals={}
for line in open(sys.argv[1],encoding='utf-8'):
    if '=' in line:
        k,v=line.rstrip('\n').split('=',1); vals[k]=v
print(json.dumps({'username':vals['username'],'password':vals['password']}))
PY
code="$(curl -sS -D "$AUTH_WORK/headers" -o "$AUTH_WORK/body" -w '%{http_code}' \
  -H "Host: ${PUBLIC_IP}:8876" -H "Origin: $PUBLIC_ORIGIN" -H 'Content-Type: application/json' \
  --data-binary "@$AUTH_WORK/login.json" "$BASE_URL/api/v1/auth/login")"
[[ "$code" == 200 ]] || { echo "Browser-equivalent login failed: HTTP $code" >&2; cat "$AUTH_WORK/body"; exit 1; }
TOKEN="$(sed -n 's/^Set-Cookie: cc_session=\([^;]*\).*/\1/p' "$AUTH_WORK/headers" | tr -d '\r' | head -1)"
[[ -n "$TOKEN" ]] || { echo "Session cookie missing" >&2; exit 1; }
! grep -qi '^Set-Cookie: cc_session=.*Secure' "$AUTH_WORK/headers" || { echo "Cookie unexpectedly Secure in HTTP test mode" >&2; exit 1; }
session_code="$(curl -sS -o /dev/null -w '%{http_code}' -H "Host: ${PUBLIC_IP}:8876" -H "Cookie: cc_session=$TOKEN" "$BASE_URL/api/v1/auth/session")"
[[ "$session_code" == 200 ]] || { echo "Session verification failed: HTTP $session_code" >&2; exit 1; }
rm -rf "$AUTH_WORK"

trap - ERR
echo "WEB_LOGIN_UI_FIX=APPLIED"
echo "PRODUCT_COMMIT=$PRODUCT_COMMIT"
echo "PANEL_URL=$PUBLIC_ORIGIN"
echo "LOGIN_HTTP=$code"
echo "SESSION_HTTP=$session_code"
echo "HIDDEN_UI_CONTRACT=OK"
echo "ACTION=Close all Control Center tabs, then open a new private/incognito window or hard-refresh with Ctrl+Shift+R."
