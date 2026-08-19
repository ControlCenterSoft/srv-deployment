#!/usr/bin/env bash
set -Eeuo pipefail
[[ ${EUID:-$(id -u)} -eq 0 ]] || { echo 'Запустите от root: sudo bash install/install.sh'; exit 1; }
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BASE="$ROOT_DIR/install/install-base-1.0.8.sh"
TMP="$(mktemp /tmp/control-center-install-1.0.10.XXXXXX)"
OLD_WEB_ENV="$(cat /etc/control-center/web.env 2>/dev/null || true)"
trap 'rm -f "$TMP"' EXIT
[[ -f "$BASE" ]] || { echo 'Отсутствует install/install-base-1.0.8.sh' >&2; exit 1; }

python3 - "$BASE" "$TMP" <<'PY'
from pathlib import Path
import sys
src,dst=map(Path,sys.argv[1:]);text=src.read_text()
old_root='ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"'
if old_root not in text:
    raise SystemExit('Base 1.0.8 ROOT_DIR marker not found')
text=text.replace(old_root,'ROOT_DIR="${CONTROL_CENTER_RELEASE_ROOT:?}"',1)
text=text.replace('Control Center 1.0.8 build 20260819.2','Control Center 1.0.10 build 20260819.4')
text=text.replace("'VERSION=1.0.7','VERSION=1.0.8'","'VERSION=1.0.7','VERSION=1.0.10'")
text=text.replace("'BUILD=20260818.2','BUILD=20260819.2'","'BUILD=20260818.2','BUILD=20260819.4'")
text=text.replace('control-center-install-1.0.8.','control-center-install-1.0.10.')
dst.write_text(text)
PY
chmod 0755 "$TMP"
CONTROL_CENTER_RELEASE_ROOT="$ROOT_DIR" bash "$TMP" "$@"

install -m 0755 "$ROOT_DIR/system/control-center-web-run" /usr/local/sbin/control-center-web-run
install -m 0755 "$ROOT_DIR/system/control-center-web-apply" /usr/local/sbin/control-center-web-apply
install -m 0755 "$ROOT_DIR/system/control-center-hostname-apply" /usr/local/sbin/control-center-hostname-apply
install -m 0755 "$ROOT_DIR/network/control-center-network-apply" /usr/local/sbin/control-center-network-apply

OLD_PORT="$(printf '%s\n' "$OLD_WEB_ENV" | sed -n 's/^CONTROL_CENTER_PORT=//p' | head -1)"
PORT="${OLD_PORT:-$(sed -n 's/^CONTROL_CENTER_PORT=//p' /etc/control-center/web.env 2>/dev/null | head -1)}"; PORT="${PORT:-8080}"
SSL="$(printf '%s\n' "$OLD_WEB_ENV" | sed -n 's/^CONTROL_CENTER_SSL=//p' | head -1)"; SSL="${SSL:-0}"
STANDARD="$(printf '%s\n' "$OLD_WEB_ENV" | sed -n 's/^CONTROL_CENTER_STANDARD_PORT=//p' | head -1)"; STANDARD="${STANDARD:-0}"
CERT=/etc/control-center/tls/server.crt
KEY=/etc/control-center/tls/server.key
cat >/etc/control-center/web.env <<EOF
CONTROL_CENTER_PORT=$PORT
CONTROL_CENTER_SSL=$SSL
CONTROL_CENTER_STANDARD_PORT=$STANDARD
CONTROL_CENTER_CERT=$CERT
CONTROL_CENTER_KEY=$KEY
EOF
chown root:root /etc/control-center/web.env; chmod 0600 /etc/control-center/web.env

cat >/etc/systemd/system/control-center.service <<'UNIT'
[Unit]
Description=Control Center web interface
After=network-online.target postgresql.service
Wants=network-online.target postgresql.service
[Service]
Type=simple
User=control-center
Group=control-center
WorkingDirectory=/opt/control-center/app
Environment=PYTHONDONTWRITEBYTECODE=1
EnvironmentFile=-/etc/control-center/database.env
EnvironmentFile=-/etc/control-center/web.env
ExecStart=/usr/local/sbin/control-center-web-run
Restart=on-failure
RestartSec=3
AmbientCapabilities=CAP_NET_BIND_SERVICE
CapabilityBoundingSet=CAP_NET_BIND_SERVICE
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ProtectHome=true
ProtectKernelTunables=true
ProtectKernelModules=true
ProtectControlGroups=true
RestrictSUIDSGID=true
LockPersonality=true
ReadWritePaths=/var/lib/control-center
ReadOnlyPaths=/var/lib/control-center-system /var/lib/control-center-license /etc/netplan/90-control-center.yaml /etc/dnsmasq.d/control-center-dhcp.conf
InaccessiblePaths=/var/lib/control-center-root
[Install]
WantedBy=multi-user.target
UNIT
cat >/etc/systemd/system/control-center-hostname-apply.service <<'UNIT'
[Unit]
Description=Control Center hostname configuration apply
After=systemd-hostnamed.service
[Service]
Type=oneshot
ExecStart=/usr/local/sbin/control-center-hostname-apply
UNIT
cat >/etc/systemd/system/control-center-hostname-apply.path <<'UNIT'
[Unit]
Description=Control Center hostname request watcher
[Path]
PathExists=/var/lib/control-center/hostname-pending.json
Unit=control-center-hostname-apply.service
[Install]
WantedBy=multi-user.target
UNIT
cat >/etc/systemd/system/control-center-db-migrate.service <<'UNIT'
[Unit]
Description=Control Center PostgreSQL schema migration
After=postgresql.service
Wants=postgresql.service
[Service]
Type=oneshot
User=control-center
Group=control-center
EnvironmentFile=-/etc/control-center/database.env
ExecStart=/opt/control-center/venv/bin/python /opt/control-center/app/db_migrate.py
Restart=on-failure
RestartSec=30s
[Install]
WantedBy=multi-user.target
UNIT

systemctl daemon-reload
systemctl enable --now control-center-hostname-apply.path
systemctl enable control-center-db-migrate.service
# Apply migration 003 immediately when PostgreSQL is healthy. If it is down,
# Restart=on-failure keeps retrying until the database becomes available.
systemctl restart control-center-db-migrate.service || true
systemctl restart control-center
SCHEME=http; CURL=(-fsS --max-time 3)
if [[ "$SSL" == 1 || "$SSL" == true ]]; then SCHEME=https; CURL=(-kfsS --max-time 3); fi
for _ in $(seq 1 20); do if curl "${CURL[@]}" "$SCHEME://127.0.0.1:$PORT/api/health" >/dev/null 2>&1; then break; fi; sleep 1; done
curl "${CURL[@]}" "$SCHEME://127.0.0.1:$PORT/api/health" >/dev/null

echo 'Control Center 1.0.10 build 20260819.4 установлен.'
echo "Web UI: $SCHEME://SERVER:$PORT"
echo 'Samba AD-DC: expanded readiness + dry-run plan; installation/provisioning remain disabled until the next release.'
