#!/usr/bin/env bash
set -Eeuo pipefail

PRODUCT="Control Center"
VERSION="2.2.0"
ROOT="/opt/control-center"
ETC="/etc/control-center"
SERVICE="control-center-web.service"
NGINX_SITE="/etc/nginx/sites-available/control-center"
REPO_RAW_BASE="${CONTROL_CENTER_RAW_BASE:-https://raw.githubusercontent.com/filosoff31/srv-deployment/release/2.2.0}"

log(){ printf '[%s] %s\n' "$PRODUCT" "$*"; }
die(){ printf '[%s] ERROR: %s\n' "$PRODUCT" "$*" >&2; exit 1; }

[[ ${EUID:-$(id -u)} -eq 0 ]] || die "Run as root: sudo bash installer/install.sh"
command -v apt-get >/dev/null || die "This bootstrap currently supports Debian/Ubuntu systems with apt."
command -v systemctl >/dev/null || die "systemd is required."

log "Preflight"
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y --no-install-recommends python3 python3-pam python3-gunicorn nginx ca-certificates curl

getent passwd www-data >/dev/null || die "www-data user is missing after nginx installation."
install -d -m 0755 "$ROOT/app/static" "$ETC"

backup_dir="/var/backups/control-center/2.2.0-$(date -u +%Y%m%dT%H%M%SZ)"
install -d -m 0700 "$backup_dir"
for path in "$NGINX_SITE" "/etc/systemd/system/$SERVICE"; do
  if [[ -e "$path" ]]; then
    cp -a "$path" "$backup_dir/$(basename "$path")"
  fi
done

fetch(){
  local rel="$1" dst="$2"
  curl -fsSL --retry 3 --retry-delay 1 "$REPO_RAW_BASE/$rel" -o "$dst"
}

log "Installing web application"
fetch app/control_center.py "$ROOT/app/control_center.py"
fetch app/static/style.css "$ROOT/app/static/style.css"
chmod 0755 "$ROOT/app/control_center.py"
chmod 0644 "$ROOT/app/static/style.css"
chown -R root:root "$ROOT"

if [[ ! -s "$ETC/session.key" ]]; then
  umask 027
  python3 - <<'PY' > "$ETC/session.key"
import secrets
print(secrets.token_hex(64))
PY
fi
chown root:www-data "$ETC/session.key"
chmod 0640 "$ETC/session.key"

cat > "/etc/systemd/system/$SERVICE" <<'UNIT'
[Unit]
Description=Control Center 2.2 web interface
After=network.target

[Service]
Type=simple
User=www-data
Group=www-data
WorkingDirectory=/opt/control-center/app
Environment=CONTROL_CENTER_SESSION_KEY=/etc/control-center/session.key
ExecStart=/usr/bin/gunicorn3 --workers 2 --bind 127.0.0.1:8876 --access-logfile - --error-logfile - control_center:application
Restart=on-failure
RestartSec=3
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ProtectHome=true
ReadOnlyPaths=/opt/control-center
ReadOnlyPaths=/etc/control-center

[Install]
WantedBy=multi-user.target
UNIT

cat > "$NGINX_SITE" <<'NGINX'
server {
    listen 80 default_server;
    listen [::]:80 default_server;
    server_name _;

    client_max_body_size 16m;

    location / {
        proxy_pass http://127.0.0.1:8876;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_connect_timeout 5s;
        proxy_read_timeout 30s;
    }
}
NGINX

rm -f /etc/nginx/sites-enabled/default
ln -sfn "$NGINX_SITE" /etc/nginx/sites-enabled/control-center
nginx -t
systemctl daemon-reload
systemctl enable --now "$SERVICE"
systemctl enable --now nginx.service
systemctl restart "$SERVICE"
systemctl reload nginx.service

log "Acceptance"
for i in {1..20}; do
  if curl -fsS http://127.0.0.1:8876/api/v1/health >/tmp/control-center-health.json 2>/dev/null; then break; fi
  sleep 1
done
python3 - <<'PY'
import json
p=json.load(open('/tmp/control-center-health.json', encoding='utf-8'))
assert p['status']=='ok',p
assert p['product']=='Control Center',p
assert p['version']=='2.2.0',p
PY
curl -fsS http://127.0.0.1/api/v1/health | python3 -c 'import json,sys; p=json.load(sys.stdin); assert p["status"]=="ok" and p["version"]=="2.2.0"'
rm -f /tmp/control-center-health.json

log "INSTALL PASS — $PRODUCT $VERSION"
log "Open http://<server-ip>/ and sign in with a local system account."
