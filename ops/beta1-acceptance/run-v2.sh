#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

PRODUCT_REPO="https://github.com/ControlCenterSoft/srv-deployment.git"
PRODUCT_COMMIT="d1ef2551c829e9b4b34d83bbdc2ec46baa8c9eca"
PRODUCT_VERSION="1.0.0-beta.1"
DIAG_SSH="git@github.com:ControlCenterSoft/control-center-server-diagnostics..git"
WORK="/opt/control-center-beta1-acceptance-v2"
SRC="$WORK/source"
REPORT_DIR="$WORK/report"
REPORT="$REPORT_DIR/report.txt"
FULL_LOG="$REPORT_DIR/full.log"
DIAG_BUNDLE="$REPORT_DIR/control-center-diagnostics.tar.gz"
CREDS="/root/control-center-admin-credentials.txt"
ENV_FILE="/etc/control-center/control-center.env"
NGINX_CONF="/etc/nginx/conf.d/control-center-test-http.conf"
BACKEND_URL="http://127.0.0.1:8877"
PROXY_URL="http://127.0.0.1:8876"
TRUST_KEY="/etc/control-center/update-public-key.pem"
KEY_DIR="$WORK/test-update-trust"
PRIVATE_KEY="$KEY_DIR/update-private.pem"
PUBLIC_KEY="$KEY_DIR/update-public.pem"
BETA1_PACKAGE="$WORK/control-center-1.0.0-beta.1-signed-test.tar.gz"
STARTED_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
TS="$(date -u +%Y%m%dT%H%M%SZ)"
HOST="$(hostname -s 2>/dev/null || hostname)"
HOST_SAFE="$(printf '%s' "$HOST" | tr -cs 'A-Za-z0-9._-' '-')"
REPORT_BRANCH="reports/${HOST_SAFE}/${TS}-beta1-v2"
STATUS="FAILED"
STEP="preflight"
UPDATE_ACCEPTANCE="not-run"
RESTORE_BETA1="not-run"
PRESERVE_REINSTALL="not-run"
BROWSER_PROXY="not-run"
TRUST_RESTORED="not-run"

[[ $EUID -eq 0 ]] || { echo "Run as root" >&2; exit 1; }
mkdir -p "$REPORT_DIR"
chmod 0700 "$WORK" "$REPORT_DIR"
: > "$FULL_LOG"
exec > >(tee -a "$FULL_LOG") 2>&1

wait_url() {
  local url="$1" needle="${2:-}" body
  for _ in {1..80}; do
    if body="$(curl -fsS --max-time 2 "$url" 2>/dev/null)"; then
      if [[ -z "$needle" ]] || grep -Fq "$needle" <<<"$body"; then return 0; fi
    fi
    sleep 0.25
  done
  return 1
}

public_ip() {
  local ip
  ip="$(curl -4 -fsS --max-time 5 https://api.ipify.org 2>/dev/null || true)"
  [[ -n "$ip" ]] || ip="$(hostname -I 2>/dev/null | awk '{print $1}')"
  printf '%s' "$ip"
}

push_report() {
  command -v git >/dev/null 2>&1 || return 0
  if ! GIT_TERMINAL_PROMPT=0 GIT_SSH_COMMAND='ssh -o BatchMode=yes -o StrictHostKeyChecking=accept-new -o ConnectTimeout=8' git ls-remote "$DIAG_SSH" >/dev/null 2>&1; then
    echo "REPORT_SENT=NO"; return 0
  fi
  local tmp="$(mktemp -d /tmp/control-center-beta1-v2-report.XXXXXX)"
  GIT_TERMINAL_PROMPT=0 GIT_SSH_COMMAND='ssh -o BatchMode=yes -o StrictHostKeyChecking=accept-new -o ConnectTimeout=8' git clone -q "$DIAG_SSH" "$tmp/repo" || { rm -rf "$tmp"; echo "REPORT_SENT=NO"; return 0; }
  cd "$tmp/repo"
  git checkout -q -b "$REPORT_BRANCH"
  mkdir -p "reports/$HOST_SAFE/$TS"
  cp "$REPORT" "reports/$HOST_SAFE/$TS/report.txt"
  [[ ! -f "$DIAG_BUNDLE" ]] || cp "$DIAG_BUNDLE" "reports/$HOST_SAFE/$TS/control-center-diagnostics.tar.gz"
  git add "reports/$HOST_SAFE/$TS"
  git -c user.name='Control Center Test Host' -c user.email='control-center-test-host@localhost' commit -q -m "Beta1 v2 real-host acceptance: $HOST_SAFE $TS"
  if GIT_TERMINAL_PROMPT=0 GIT_SSH_COMMAND='ssh -o BatchMode=yes -o StrictHostKeyChecking=accept-new -o ConnectTimeout=8' git push -q origin "$REPORT_BRANCH"; then
    echo "REPORT_SENT=YES"
    echo "REPORT_BRANCH=$REPORT_BRANCH"
  else
    echo "REPORT_SENT=NO"
  fi
  cd /
  rm -rf "$tmp"
}

restore_trust() {
  if [[ -f "$WORK/trust.before" ]]; then
    install -o root -g root -m 0644 "$WORK/trust.before" "$TRUST_KEY"
    TRUST_RESTORED="previous-key"
  elif [[ -f "$WORK/trust.was-absent" ]]; then
    rm -f -- "$TRUST_KEY"
    TRUST_RESTORED="removed-test-key"
  fi
}

finalize() {
  local rc=$?
  trap - EXIT
  rm -f -- "$PRIVATE_KEY" 2>/dev/null || true
  restore_trust || true
  local public="$(public_ip)"
  local panel="http://${public}:8876"
  {
    echo "CONTROL CENTER BETA1 V2 REAL-HOST ACCEPTANCE"
    echo "started_at=$STARTED_AT"
    echo "finished_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo "host=$HOST"
    echo "status=$STATUS"
    echo "last_step=$STEP"
    echo "product_version=$PRODUCT_VERSION"
    echo "product_commit=$PRODUCT_COMMIT"
    echo "update_acceptance=$UPDATE_ACCEPTANCE"
    echo "restored_beta1=$RESTORE_BETA1"
    echo "preserve_state_reinstall=$PRESERVE_REINSTALL"
    echo "browser_http_proxy=$BROWSER_PROXY"
    echo "trust_restored=$TRUST_RESTORED"
    echo "panel_url=$panel"
    echo "service_active=$(systemctl is-active control-center.service 2>/dev/null || true)"
    echo "service_enabled=$(systemctl is-enabled control-center.service 2>/dev/null || true)"
    echo "nginx_active=$(systemctl is-active nginx.service 2>/dev/null || true)"
    echo "current_target=$(readlink /usr/local/lib/control-center/current 2>/dev/null || true)"
    echo "config_mode=$(stat -c %a /etc/control-center 2>/dev/null || true)"
    echo "state_mode=$(stat -c %a /var/lib/control-center 2>/dev/null || true)"
    echo "log_mode=$(stat -c %a /var/log/control-center 2>/dev/null || true)"
    echo "test_private_key_removed=$([[ ! -f "$PRIVATE_KEY" ]] && echo true || echo false)"
    echo
    echo "--- BACKEND VERSION ---"
    curl -fsS "$BACKEND_URL/api/v1/version" 2>/dev/null || true
    echo
    echo "--- BACKEND READINESS ---"
    curl -fsS "$BACKEND_URL/api/v1/readiness" 2>/dev/null || true
    echo
    echo "--- PROXY HEALTH ---"
    curl -fsS "$PROXY_URL/api/v1/health" 2>/dev/null || true
    echo
    echo "--- SYSTEMD STATUS ---"
    systemctl status control-center.service --no-pager -l 2>&1 | tail -n 100 || true
    echo
    echo "--- JOURNAL TAIL ---"
    journalctl -u control-center.service --no-pager -n 240 2>&1 || true
    echo
    echo "NOTE: passwords, password hashes, cookies, CSRF tokens, request bodies and private signing keys are excluded."
  } > "$REPORT"
  chmod 0600 "$REPORT"
  push_report || true
  echo
  echo "FINAL_STATUS=$STATUS"
  echo "LOCAL_REPORT=$REPORT"
  [[ -f "$DIAG_BUNDLE" ]] && echo "LOCAL_DIAGNOSTICS=$DIAG_BUNDLE"
  echo "PANEL_URL=$panel"
  echo "ADMIN_CREDENTIALS=$CREDS"
  exit "$rc"
}
trap finalize EXIT

STEP="dependencies"
echo "=== Dependencies ==="
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq git curl ca-certificates golang-go python3 tar gzip openssl nginx openssh-client >/dev/null
for c in git curl go python3 tar sha256sum openssl nginx systemctl ss; do command -v "$c" >/dev/null || { echo "Missing command: $c"; exit 1; }; done
[[ -d /run/systemd/system ]] || { echo "systemd is not running"; exit 1; }
[[ -f "$CREDS" ]] || { echo "Missing admin credentials file: $CREDS"; exit 1; }
[[ -f "$ENV_FILE" ]] || { echo "Missing Control Center environment file: $ENV_FILE"; exit 1; }

PUBLIC_IP="$(public_ip)"
[[ -n "$PUBLIC_IP" ]] || { echo "Unable to determine public IP"; exit 1; }
PUBLIC_ORIGIN="http://${PUBLIC_IP}:8876"
echo "PUBLIC_IP=$PUBLIC_IP"
echo "PANEL_URL=$PUBLIC_ORIGIN"

STEP="fetch-build"
echo "=== Fetch and validate exact beta.1 hardening commit ==="
rm -rf "$SRC"
mkdir -p "$SRC"
git -C "$WORK" init -q source
git -C "$SRC" remote add origin "$PRODUCT_REPO"
git -C "$SRC" fetch -q --depth=1 origin "$PRODUCT_COMMIT"
git -C "$SRC" checkout -q --detach FETCH_HEAD
[[ "$(git -C "$SRC" rev-parse HEAD)" == "$PRODUCT_COMMIT" ]]
cd "$SRC"
test -z "$(gofmt -l .)"
go vet ./...
go test ./...
bash -n install/install.sh install/uninstall.sh install/update.sh scripts/build.sh scripts/auth-acceptance.sh scripts/operations-acceptance.sh scripts/update-acceptance.sh
VERSION="$PRODUCT_VERSION" COMMIT="$PRODUCT_COMMIT" ./scripts/build.sh
sha256sum -c dist/SHA256SUMS
[[ "$(./dist/control-center-linux-amd64 build-info --field version)" == "$PRODUCT_VERSION" ]]
[[ "$(./dist/control-center-linux-amd64 build-info --field commit)" == "$PRODUCT_COMMIT" ]]

STEP="signing-trust"
echo "=== Generate ephemeral test update trust ==="
rm -rf "$KEY_DIR"
mkdir -p "$KEY_DIR"
chmod 0700 "$KEY_DIR"
rm -f -- "$WORK/trust.before" "$WORK/trust.was-absent"
if [[ -f "$TRUST_KEY" ]]; then cp -a "$TRUST_KEY" "$WORK/trust.before"; else : > "$WORK/trust.was-absent"; fi
openssl genpkey -algorithm ED25519 -out "$PRIVATE_KEY"
openssl pkey -in "$PRIVATE_KEY" -pubout -out "$PUBLIC_KEY"
chmod 0600 "$PRIVATE_KEY"
chmod 0644 "$PUBLIC_KEY"
go run ./cmd/release-tool package \
  --binary ./dist/control-center-linux-amd64 \
  --version "$PRODUCT_VERSION" \
  --commit "$PRODUCT_COMMIT" \
  --arch amd64 \
  --private-key "$PRIVATE_KEY" \
  --output "$BETA1_PACKAGE" >/dev/null

STEP="prepare-backend-config"
echo "=== Prepare backend binding (proxy not switched yet) ==="
cp -a "$ENV_FILE" "$WORK/control-center.env.before"
python3 - "$ENV_FILE" <<'PY'
from pathlib import Path
import sys
p=Path(sys.argv[1])
lines=p.read_text().splitlines()
remove={'CONTROL_CENTER_LISTEN','CONTROL_CENTER_INSECURE_HTTP'}
lines=[line for line in lines if line.split('=',1)[0] not in remove]
lines.append('CONTROL_CENTER_LISTEN=127.0.0.1:8877')
p.write_text('\n'.join(lines)+'\n')
PY
chown root:control-center "$ENV_FILE"
chmod 0640 "$ENV_FILE"

STEP="install-beta1"
echo "=== Install/reinstall beta.1 hardening commit ==="
CONTROL_CENTER_UPDATE_PUBLIC_KEY="$PUBLIC_KEY" CONTROL_CENTER_ACCEPTANCE_URL="$BACKEND_URL" ./install/install.sh --reinstall
wait_url "$BACKEND_URL/api/v1/readiness" '"ready":true'
[[ "$(/usr/local/lib/control-center/current/control-center build-info --field version)" == "$PRODUCT_VERSION" ]]
[[ "$(/usr/local/lib/control-center/current/control-center build-info --field commit)" == "$PRODUCT_COMMIT" ]]
[[ "$(stat -c %a /etc/control-center)" == 750 ]]
[[ "$(stat -c %a /var/lib/control-center)" == 750 ]]
[[ "$(stat -c %a /var/log/control-center)" == 750 ]]
cmp -s "$PUBLIC_KEY" "$TRUST_KEY"

STEP="activate-http-proxy"
echo "=== Activate HTTP/IP proxy only after backend readiness ==="
cat > "$NGINX_CONF" <<'NGINX'
server {
    listen 0.0.0.0:8876 default_server;
    server_name _;
    location / {
        proxy_pass http://127.0.0.1:8877;
        proxy_http_version 1.1;
        proxy_set_header Host $http_host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto http;
        proxy_cookie_flags cc_session nosecure;
    }
}
NGINX
nginx -t
systemctl enable nginx.service >/dev/null 2>&1 || true
systemctl restart nginx.service
wait_url "$PROXY_URL/api/v1/health" '"status":"ok"'
if command -v ufw >/dev/null 2>&1 && ufw status 2>/dev/null | grep -q '^Status: active'; then ufw allow 8876/tcp >/dev/null || true; fi

STEP="browser-auth"
echo "=== Browser-path authentication ==="
AUTH_WORK="$(mktemp -d /tmp/control-center-beta1-v2-auth.XXXXXX)"
chmod 0700 "$AUTH_WORK"
python3 - "$CREDS" > "$AUTH_WORK/admin-login.json" <<'PY'
import json,sys
vals={}
for line in open(sys.argv[1],encoding='utf-8'):
    if '=' in line:
        k,v=line.rstrip('\n').split('=',1); vals[k]=v
if not vals.get('username') or not vals.get('password'):
    raise SystemExit('credentials file incomplete')
print(json.dumps({'username':vals['username'],'password':vals['password']}))
PY
direct_code="$(curl -sS -D "$AUTH_WORK/direct-h" -o "$AUTH_WORK/direct-b" -w '%{http_code}' -H "Host: ${PUBLIC_IP}:8876" -H "Origin: $PUBLIC_ORIGIN" -H 'Content-Type: application/json' --data-binary "@$AUTH_WORK/admin-login.json" "$BACKEND_URL/api/v1/auth/login")"
[[ "$direct_code" == 200 ]]
grep -qi '^Set-Cookie: cc_session=.*Secure' "$AUTH_WORK/direct-h"
proxy_code="$(curl -sS -D "$AUTH_WORK/proxy-h" -o "$AUTH_WORK/proxy-b" -w '%{http_code}' -H "Host: ${PUBLIC_IP}:8876" -H "Origin: $PUBLIC_ORIGIN" -H 'Content-Type: application/json' --data-binary "@$AUTH_WORK/admin-login.json" "$PROXY_URL/api/v1/auth/login")"
[[ "$proxy_code" == 200 ]]
! grep -qi '^Set-Cookie: cc_session=.*Secure' "$AUTH_WORK/proxy-h"
grep -qi '^Set-Cookie: cc_session=.*HttpOnly' "$AUTH_WORK/proxy-h"
grep -qi '^Set-Cookie: cc_session=.*SameSite=Strict' "$AUTH_WORK/proxy-h"
ADMIN_TOKEN="$(sed -n 's/^Set-Cookie: cc_session=\([^;]*\).*/\1/p' "$AUTH_WORK/proxy-h" | tr -d '\r' | head -1)"
[[ -n "$ADMIN_TOKEN" ]]
session_code="$(curl -sS -o /dev/null -w '%{http_code}' -H "Host: ${PUBLIC_IP}:8876" -H "Cookie: cc_session=$ADMIN_TOKEN" "$PROXY_URL/api/v1/auth/session")"
[[ "$session_code" == 200 ]]
for endpoint in /api/v1/system/status /api/v1/rbac/users /api/v1/operations?limit=5 /api/v1/audit?limit=5 /api/v1/diagnostics/summary; do
  code="$(curl -sS -o /dev/null -w '%{http_code}' -H "Host: ${PUBLIC_IP}:8876" -H "Cookie: cc_session=$ADMIN_TOKEN" "$PROXY_URL$endpoint")"
  [[ "$code" == 200 ]] || { echo "Authenticated regression endpoint failed: $endpoint HTTP $code" >&2; exit 1; }
done
BROWSER_PROXY="passed"
rm -rf "$AUTH_WORK"

STEP="update-acceptance"
echo "=== Signed update negative/rollback acceptance ==="
CONTROL_CENTER_ACCEPTANCE_URL="$BACKEND_URL" \
CONTROL_CENTER_UPDATE_HEALTH_URL="$BACKEND_URL" \
CONTROL_CENTER_UPDATE_PRIVATE_KEY="$PRIVATE_KEY" \
./scripts/update-acceptance.sh
UPDATE_ACCEPTANCE="passed"

STEP="restore-beta1"
echo "=== Restore exact beta.1 after synthetic update tests ==="
CONTROL_CENTER_UPDATE_HEALTH_URL="$BACKEND_URL" /usr/local/sbin/control-center-update --package "$BETA1_PACKAGE" --allow-downgrade
wait_url "$BACKEND_URL/api/v1/version" '"version":"1.0.0-beta.1"'
[[ "$(/usr/local/lib/control-center/current/control-center build-info --field commit)" == "$PRODUCT_COMMIT" ]]
RESTORE_BETA1="passed"

STEP="repair-reinstall"
echo "=== Repair/reinstall trust and state preservation ==="
CONTROL_CENTER_ACCEPTANCE_URL="$BACKEND_URL" ./install/install.sh --repair
CONTROL_CENTER_ACCEPTANCE_URL="$BACKEND_URL" ./install/install.sh --reinstall
wait_url "$BACKEND_URL/api/v1/readiness" '"ready":true'
cmp -s "$PUBLIC_KEY" "$TRUST_KEY"

STEP="preserve-uninstall-reinstall"
echo "=== Preserve-state uninstall/reinstall ==="
./install/uninstall.sh
[[ -f "$ENV_FILE" ]]
[[ -d /var/lib/control-center ]]
[[ -f "$TRUST_KEY" ]]
CONTROL_CENTER_ACCEPTANCE_URL="$BACKEND_URL" ./install/install.sh
wait_url "$BACKEND_URL/api/v1/readiness" '"ready":true'
[[ "$(/usr/local/lib/control-center/current/control-center build-info --field commit)" == "$PRODUCT_COMMIT" ]]
cmp -s "$PUBLIC_KEY" "$TRUST_KEY"
PRESERVE_REINSTALL="passed"

STEP="diagnostics"
echo "=== Final diagnostics export ==="
AUTH_WORK="$(mktemp -d /tmp/control-center-beta1-v2-final.XXXXXX)"
python3 - "$CREDS" > "$AUTH_WORK/login.json" <<'PY'
import json,sys
vals={}
for line in open(sys.argv[1],encoding='utf-8'):
    if '=' in line:
        k,v=line.rstrip('\n').split('=',1); vals[k]=v
print(json.dumps({'username':vals['username'],'password':vals['password']}))
PY
curl -sS -D "$AUTH_WORK/h" -o "$AUTH_WORK/b" -H "Host: ${PUBLIC_IP}:8876" -H "Origin: $PUBLIC_ORIGIN" -H 'Content-Type: application/json' --data-binary "@$AUTH_WORK/login.json" "$PROXY_URL/api/v1/auth/login" >/dev/null
TOKEN="$(sed -n 's/^Set-Cookie: cc_session=\([^;]*\).*/\1/p' "$AUTH_WORK/h" | tr -d '\r' | head -1)"
[[ -n "$TOKEN" ]]
curl -fsS -H "Host: ${PUBLIC_IP}:8876" -H "Cookie: cc_session=$TOKEN" "$PROXY_URL/api/v1/diagnostics/export" -o "$DIAG_BUNDLE"
tar -tzf "$DIAG_BUNDLE" | grep -qx 'manifest.json'
rm -rf "$AUTH_WORK"

STEP="completed"
STATUS="PASSED"
echo "=== BETA1 V2 REAL-HOST ACCEPTANCE PASSED ==="
