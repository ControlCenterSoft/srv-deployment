#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

BASE_COMMIT="29c0d19418113ee05835e8fc67e4a9e799dfc7f3"
REPO="https://github.com/ControlCenterSoft/srv-deployment.git"
WORK="/opt/control-center-http-test-access"
SRC="$WORK/source"
ENV_FILE="/etc/control-center/control-center.env"
BIN="/usr/local/lib/control-center/control-center"
CREDS="/root/control-center-admin-credentials.txt"
BASE_URL="http://127.0.0.1:8876"
BACKUP_ENV="$WORK/control-center.env.before-http"
BACKUP_BIN="$WORK/control-center.before-http"
REPORT="$WORK/http-access-report.txt"
DIAG_SSH="git@github.com:ControlCenterSoft/control-center-server-diagnostics..git"
TS="$(date -u +%Y%m%dT%H%M%SZ)"
HOST="$(hostname -s 2>/dev/null || hostname)"
HOST_SAFE="$(printf '%s' "$HOST" | tr -cs 'A-Za-z0-9._-' '-')"
REPORT_BRANCH="reports/${HOST_SAFE}/${TS}-http-ip-access"

[[ $EUID -eq 0 ]] || { echo "Run as root" >&2; exit 1; }
mkdir -p "$WORK"; chmod 0700 "$WORK"

rollback() {
  rc=$?
  trap - ERR
  echo "HTTP test-access configuration failed; restoring previous runtime."
  if [[ -f "$BACKUP_ENV" ]]; then install -m 0640 -o root -g control-center "$BACKUP_ENV" "$ENV_FILE"; fi
  if [[ -f "$BACKUP_BIN" ]]; then install -m 0755 "$BACKUP_BIN" "$BIN"; fi
  systemctl daemon-reload || true
  systemctl restart control-center.service || true
  exit "$rc"
}
trap rollback ERR

command -v git >/dev/null || apt-get update -qq && apt-get install -y -qq git >/dev/null
for c in git go python3 curl systemctl ss; do command -v "$c" >/dev/null || { echo "Missing command: $c" >&2; exit 1; }; done
[[ -f "$ENV_FILE" && -f "$BIN" && -f "$CREDS" ]] || { echo "Accepted alpha.3 installation/credentials not found." >&2; exit 1; }
cp -a "$ENV_FILE" "$BACKUP_ENV"
cp -a "$BIN" "$BACKUP_BIN"

rm -rf "$SRC"
mkdir -p "$SRC"
git -C "$WORK" init -q source
git -C "$SRC" remote add origin "$REPO"
git -C "$SRC" fetch -q --depth=1 origin "$BASE_COMMIT"
git -C "$SRC" checkout -q --detach FETCH_HEAD
[[ "$(git -C "$SRC" rev-parse HEAD)" == "$BASE_COMMIT" ]]

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
VERSION='1.0.0-alpha.3+testhttp' COMMIT="$BASE_COMMIT-testhttp" ./scripts/build.sh
sha256sum -c dist/SHA256SUMS

python3 - "$ENV_FILE" <<'PY'
from pathlib import Path
import sys
p=Path(sys.argv[1])
lines=p.read_text().splitlines()
keys={'CONTROL_CENTER_LISTEN','CONTROL_CENTER_INSECURE_HTTP'}
lines=[x for x in lines if x.split('=',1)[0] not in keys]
lines += ['CONTROL_CENTER_LISTEN=0.0.0.0:8876','CONTROL_CENTER_INSECURE_HTTP=1']
p.write_text('\n'.join(lines)+'\n')
PY
chown root:control-center "$ENV_FILE"
chmod 0640 "$ENV_FILE"

install -m 0755 dist/control-center-linux-amd64 "$BIN"
systemctl restart control-center.service
for _ in {1..40}; do
  if curl -fsS --max-time 2 "$BASE_URL/api/v1/readiness" >/dev/null 2>&1; then break; fi
  sleep 0.25
done
curl -fsS "$BASE_URL/api/v1/readiness" >/dev/null
ss -ltn | grep -Eq '(^|[[:space:]])0\.0\.0\.0:8876[[:space:]]' || { echo "Service is not listening on 0.0.0.0:8876" >&2; exit 1; }

if command -v ufw >/dev/null 2>&1; then
  if ufw status 2>/dev/null | grep -q '^Status: active'; then
    ufw allow 8876/tcp >/dev/null
    echo "UFW_RULE=ALLOW_8876_TCP"
  else
    echo "UFW_STATUS=INACTIVE"
  fi
else
  echo "UFW_STATUS=NOT_INSTALLED"
fi

SEC="$(mktemp -d /tmp/control-center-http-cookie.XXXXXX)"
chmod 0700 "$SEC"
python3 - "$CREDS" > "$SEC/login.json" <<'PY'
import json,sys
vals={}
for line in open(sys.argv[1],encoding='utf-8'):
    if '=' in line:
        k,v=line.rstrip('\n').split('=',1); vals[k]=v
print(json.dumps({'username':vals['username'],'password':vals['password']}))
PY
code="$(curl -sS -D "$SEC/headers" -o "$SEC/body" -w '%{http_code}' -H 'Content-Type: application/json' -H "Origin: $BASE_URL" --data-binary "@$SEC/login.json" "$BASE_URL/api/v1/auth/login")"
[[ "$code" == 200 ]] || { echo "HTTP-mode login failed: $code" >&2; exit 1; }
grep -qi '^Set-Cookie: cc_session=.*HttpOnly' "$SEC/headers"
grep -qi '^Set-Cookie: cc_session=.*SameSite=Strict' "$SEC/headers"
if grep -qi '^Set-Cookie: cc_session=.*Secure' "$SEC/headers"; then
  echo "Session cookie still has Secure flag in HTTP test mode" >&2
  exit 1
fi
rm -rf "$SEC"

PUBLIC_IP="$(curl -4 -fsS --max-time 5 https://api.ipify.org 2>/dev/null || true)"
if [[ -z "$PUBLIC_IP" ]]; then PUBLIC_IP="$(hostname -I 2>/dev/null | awk '{print $1}')"; fi
PANEL_URL="http://${PUBLIC_IP}:8876"

{
  echo "CONTROL CENTER TEMPORARY HTTP IP ACCESS"
  echo "finished_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "host=$HOST"
  echo "base_commit=$BASE_COMMIT"
  echo "mode=temporary-insecure-http"
  echo "listen=0.0.0.0:8876"
  echo "panel_url=$PANEL_URL"
  echo "service_active=$(systemctl is-active control-center.service 2>/dev/null || true)"
  echo "readiness=$(curl -fsS "$BASE_URL/api/v1/readiness" 2>/dev/null || true)"
  echo "cookie_secure=false"
  echo "credentials_file=$CREDS"
  echo "warning=HTTP transmits credentials/session without TLS; test use only"
} > "$REPORT"
chmod 0600 "$REPORT"

if GIT_TERMINAL_PROMPT=0 GIT_SSH_COMMAND='ssh -o BatchMode=yes -o StrictHostKeyChecking=accept-new -o ConnectTimeout=8' git ls-remote "$DIAG_SSH" >/dev/null 2>&1; then
  TMP="$(mktemp -d /tmp/control-center-http-report.XXXXXX)"
  GIT_TERMINAL_PROMPT=0 GIT_SSH_COMMAND='ssh -o BatchMode=yes -o StrictHostKeyChecking=accept-new -o ConnectTimeout=8' git clone -q "$DIAG_SSH" "$TMP/repo"
  cd "$TMP/repo"
  git checkout -q -b "$REPORT_BRANCH"
  mkdir -p "reports/$HOST_SAFE/$TS"
  cp "$REPORT" "reports/$HOST_SAFE/$TS/http-access-report.txt"
  git add "reports/$HOST_SAFE/$TS/http-access-report.txt"
  git -c user.name='Control Center Test Host' -c user.email='control-center-test-host@localhost' commit -q -m "HTTP IP access report: $HOST_SAFE $TS"
  GIT_TERMINAL_PROMPT=0 GIT_SSH_COMMAND='ssh -o BatchMode=yes -o StrictHostKeyChecking=accept-new -o ConnectTimeout=8' git push -q origin "$REPORT_BRANCH" || true
  cd /
  rm -rf "$TMP"
fi

trap - ERR
echo "HTTP_IP_ACCESS=ENABLED"
echo "PANEL_URL=$PANEL_URL"
echo "LOGIN=admin"
echo "PASSWORD_FILE=$CREDS"
echo "WARNING=Temporary HTTP test mode; credentials and session are not protected by TLS."
