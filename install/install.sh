#!/usr/bin/env bash
set -Eeuo pipefail

[[ ${EUID:-$(id -u)} -eq 0 ]] || { echo 'Запустите от root: sudo bash install/install.sh'; exit 1; }
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_DIR=/opt/control-center
STATE_DIR=/var/lib/control-center
SERVICE_USER=control-center
VERSION=1.0.1

export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y python3 python3-venv iproute2 ca-certificates curl git util-linux

if ! id "$SERVICE_USER" >/dev/null 2>&1; then
  useradd --system --home "$APP_DIR" --shell /usr/sbin/nologin "$SERVICE_USER"
fi
install -d -m 0755 "$APP_DIR" "$STATE_DIR"

if [[ ! -f "$STATE_DIR/update-settings.json" ]]; then
cat >"$STATE_DIR/update-settings.json" <<'JSON'
{
  "automatic_updates": true,
  "frequency": "hourly",
  "channel": "production"
}
JSON
fi
chown -R "$SERVICE_USER:$SERVICE_USER" "$STATE_DIR"

systemctl stop control-center 2>/dev/null || true
rm -rf "$APP_DIR/app" "$APP_DIR/venv"
cp -a "$ROOT_DIR/app" "$APP_DIR/app"
printf '%s\n' "$VERSION" >"$APP_DIR/VERSION"
python3 -m venv "$APP_DIR/venv"
"$APP_DIR/venv/bin/pip" install --upgrade pip
"$APP_DIR/venv/bin/pip" install -r "$ROOT_DIR/requirements.txt"
chown -R "$SERVICE_USER:$SERVICE_USER" "$APP_DIR"

install -m 0755 "$ROOT_DIR/update/control-center-update" /usr/local/sbin/control-center-update

cat >/etc/systemd/system/control-center.service <<'UNIT'
[Unit]
Description=Control Center web interface
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=control-center
Group=control-center
WorkingDirectory=/opt/control-center/app
Environment=CONTROL_CENTER_HOST=0.0.0.0
Environment=CONTROL_CENTER_PORT=8080
ExecStart=/opt/control-center/venv/bin/python /opt/control-center/app/main.py
Restart=on-failure
RestartSec=3
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

[Install]
WantedBy=multi-user.target
UNIT

cat >/etc/systemd/system/control-center-update.service <<'UNIT'
[Unit]
Description=Control Center automatic update check
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/control-center-update
Nice=10
IOSchedulingClass=best-effort
IOSchedulingPriority=7
UNIT

cat >/etc/systemd/system/control-center-update.timer <<'UNIT'
[Unit]
Description=Control Center automatic update timer

[Timer]
OnBootSec=5min
OnUnitActiveSec=15min
RandomizedDelaySec=2min
Persistent=true
Unit=control-center-update.service

[Install]
WantedBy=timers.target
UNIT

systemctl daemon-reload
systemctl enable --now control-center
systemctl enable --now control-center-update.timer
sleep 1
curl -fsS http://127.0.0.1:8080/api/health >/dev/null

echo "Control Center $VERSION установлен."
echo 'Автоматические обновления: включены, production, проверка каждый час.'
echo 'Настройки: Web UI -> Настройки.'
echo 'Откройте: http://SERVER_IP:8080'
