#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

PRODUCT_REPO="https://github.com/ControlCenterSoft/srv-deployment.git"
PRODUCT_COMMIT="26a099e36aa543faf6953e47f31ec0178095e00b"
PRODUCT_VERSION="1.0.0-beta.1"
WORK="/opt/control-center-beta1-recovery"
SRC="$WORK/source"
ENV_FILE="/etc/control-center/control-center.env"
NGINX_CONF="/etc/nginx/conf.d/control-center-test-http.conf"
BACKEND_URL="http://127.0.0.1:8877"
PROXY_URL="http://127.0.0.1:8876"
CREDS="/root/control-center-admin-credentials.txt"

[[ $EUID -eq 0 ]] || { echo "Run as root" >&2; exit 1; }
mkdir -p "$WORK"
chmod 0700 "$WORK"

wait_url() {
  local url="$1" needle="${2:-}" body
  for _ in {1..60}; do
    if body="$(curl -fsS --max-time 2 "$url" 2>/dev/null)"; then
      [[ -z "$needle" ]] || grep -Fq "$needle" <<<"$body" || { sleep 0.25; continue; }
      return 0
    fi
    sleep 0.25
  done
  return 1
}

for c in git go curl python3 systemctl nginx sha256sum; do
  command -v "$c" >/dev/null || { echo "Missing command: $c" >&2; exit 1; }
done
[[ -f "$ENV_FILE" ]] || { echo "Missing $ENV_FILE" >&2; exit 1; }

# Restore the intended beta.1 backend binding without changing state/users.
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
VERSION="$PRODUCT_VERSION" COMMIT="$PRODUCT_COMMIT" ./scripts/build.sh
sha256sum -c dist/SHA256SUMS

# Reinstall exact beta.1 over existing state. Installer preserves state/config/trust.
CONTROL_CENTER_ACCEPTANCE_URL="$BACKEND_URL" ./install/install.sh --reinstall
wait_url "$BACKEND_URL/api/v1/readiness" '"ready":true'

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

if command -v ufw >/dev/null 2>&1 && ufw status 2>/dev/null | grep -q '^Status: active'; then
  ufw allow 8876/tcp >/dev/null || true
fi

version="$(curl -fsS "$BACKEND_URL/api/v1/version")"
readiness="$(curl -fsS "$BACKEND_URL/api/v1/readiness")"

printf '%s\n' "BETA1_PANEL_RECOVERY=PASSED"
printf '%s\n' "SERVICE_ACTIVE=$(systemctl is-active control-center.service)"
printf '%s\n' "NGINX_ACTIVE=$(systemctl is-active nginx.service)"
printf '%s\n' "BACKEND=$BACKEND_URL"
printf '%s\n' "PANEL_URL=http://$(curl -4 -fsS --max-time 5 https://api.ipify.org 2>/dev/null || hostname -I | awk '{print $1}'):8876"
printf '%s\n' "VERSION=$version"
printf '%s\n' "READINESS=$readiness"
printf '%s\n' "CURRENT_TARGET=$(readlink /usr/local/lib/control-center/current 2>/dev/null || true)"
printf '%s\n' "ADMIN_CREDENTIALS=$CREDS"
