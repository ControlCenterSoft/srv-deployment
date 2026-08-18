#!/usr/bin/env bash
set -Eeuo pipefail
[[ ${EUID:-$(id -u)} -eq 0 ]] || { echo 'Запустите от root: sudo bash install/install.sh'; exit 1; }
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_DIR=/opt/control-center
STATE_DIR=/var/lib/control-center
ROOT_STATE_DIR=/var/lib/control-center-root
LICENSE_DIR=/var/lib/control-center-license
SERVICE_USER=control-center
VERSION=1.0.5
APT_LOCK=/run/control-center-apt.lock
exec 8>"$APT_LOCK"
flock -w 900 8 || { echo 'Менеджер пакетов занят. Повторите установку позже.'; exit 1; }
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y python3 python3-venv iproute2 ca-certificates curl git util-linux netplan.io procps openssl
if ! id "$SERVICE_USER" >/dev/null 2>&1; then useradd --system --home "$APP_DIR" --shell /usr/sbin/nologin "$SERVICE_USER"; fi
install -d -o "$SERVICE_USER" -g "$SERVICE_USER" -m 0755 "$APP_DIR" "$STATE_DIR" "$STATE_DIR/modules"
install -d -o root -g root -m 0700 "$ROOT_STATE_DIR"
install -d -o root -g root -m 0755 "$LICENSE_DIR" /etc/control-center
# 1.0.5 pre-audit stored license state in a web-writable directory. Never trust or migrate it.
rm -f "$STATE_DIR/license.json"
[[ -f "$STATE_DIR/update-settings.json" ]] || printf '%s\n' '{"automatic_updates":true,"interval_minutes":60,"channel":"production"}' >"$STATE_DIR/update-settings.json"
[[ -f "$STATE_DIR/os-update-settings.json" ]] || printf '%s\n' '{"automatic_updates":false,"interval_minutes":1440}' >"$STATE_DIR/os-update-settings.json"
chown "$SERVICE_USER:$SERVICE_USER" "$STATE_DIR/update-settings.json" "$STATE_DIR/os-update-settings.json"
systemctl stop control-center 2>/dev/null || true
rm -rf "$APP_DIR/app" "$APP_DIR/venv"
cp -a "$ROOT_DIR/app" "$APP_DIR/app"
printf '%s\n' "$VERSION" >"$APP_DIR/VERSION"
python3 -m venv "$APP_DIR/venv"
"$APP_DIR/venv/bin/pip" install --upgrade pip
"$APP_DIR/venv/bin/pip" install -r "$ROOT_DIR/requirements.txt"
chown -R "$SERVICE_USER:$SERVICE_USER" "$APP_DIR"
install -m 0755 "$ROOT_DIR/update/control-center-update" /usr/local/sbin/control-center-update
install -m 0755 "$ROOT_DIR/update/control-center-os-update" /usr/local/sbin/control-center-os-update
install -m 0755 "$ROOT_DIR/network/control-center-network-apply" /usr/local/sbin/control-center-network-apply
install -m 0755 "$ROOT_DIR/market/control-center-market-apply" /usr/local/sbin/control-center-market-apply
install -m 0755 "$ROOT_DIR/market/control-center-dhcp-apply" /usr/local/sbin/control-center-dhcp-apply
install -m 0755 "$ROOT_DIR/license/control-center-license-apply" /usr/local/sbin/control-center-license-apply
install -m 0644 "$ROOT_DIR/license/vendor-public.pem" /etc/control-center/license-public.pem
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
Environment=PYTHONDONTWRITEBYTECODE=1
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
ReadOnlyPaths=/var/lib/control-center-license
InaccessiblePaths=/var/lib/control-center-root
[Install]
WantedBy=multi-user.target
UNIT
cat >/etc/systemd/system/control-center-network-apply.service <<'UNIT'
[Unit]
Description=Control Center network configuration apply
[Service]
Type=oneshot
ExecStart=/usr/local/sbin/control-center-network-apply
UNIT
cat >/etc/systemd/system/control-center-network-apply.path <<'UNIT'
[Unit]
Description=Control Center network request watcher
[Path]
PathExists=/var/lib/control-center/network-pending.json
Unit=control-center-network-apply.service
[Install]
WantedBy=multi-user.target
UNIT
cat >/etc/systemd/system/control-center-market-apply.service <<'UNIT'
[Unit]
Description=Control Center Market module lifecycle
After=network-online.target
Wants=network-online.target
[Service]
Type=oneshot
ExecStart=/usr/local/sbin/control-center-market-apply
UNIT
cat >/etc/systemd/system/control-center-market-apply.path <<'UNIT'
[Unit]
Description=Control Center Market request watcher
[Path]
PathExists=/var/lib/control-center/market-pending.json
Unit=control-center-market-apply.service
[Install]
WantedBy=multi-user.target
UNIT
cat >/etc/systemd/system/control-center-dhcp-apply.service <<'UNIT'
[Unit]
Description=Control Center DHCP configuration apply
[Service]
Type=oneshot
ExecStart=/usr/local/sbin/control-center-dhcp-apply
UNIT
cat >/etc/systemd/system/control-center-dhcp-apply.path <<'UNIT'
[Unit]
Description=Control Center DHCP request watcher
[Path]
PathExists=/var/lib/control-center/dhcp-pending.json
Unit=control-center-dhcp-apply.service
[Install]
WantedBy=multi-user.target
UNIT
cat >/etc/systemd/system/control-center-license-apply.service <<'UNIT'
[Unit]
Description=Control Center Professional license activation
[Service]
Type=oneshot
ExecStart=/usr/local/sbin/control-center-license-apply
UNIT
cat >/etc/systemd/system/control-center-license-apply.path <<'UNIT'
[Unit]
Description=Control Center license request watcher
[Path]
PathExists=/var/lib/control-center/license-pending.json
Unit=control-center-license-apply.service
[Install]
WantedBy=multi-user.target
UNIT
cat >/etc/systemd/system/control-center-update.service <<'UNIT'
[Unit]
Description=Control Center production update check
After=network-online.target
Wants=network-online.target
[Service]
Type=oneshot
ExecStart=/usr/local/sbin/control-center-update
Nice=10
UNIT
cat >/etc/systemd/system/control-center-update.timer <<'UNIT'
[Unit]
Description=Control Center production update timer
[Timer]
OnBootSec=2min
OnUnitActiveSec=1min
AccuracySec=15s
Persistent=true
Unit=control-center-update.service
[Install]
WantedBy=timers.target
UNIT
cat >/etc/systemd/system/control-center-os-update.service <<'UNIT'
[Unit]
Description=Control Center OS and package update
After=network-online.target
Wants=network-online.target
[Service]
Type=oneshot
ExecStart=/usr/local/sbin/control-center-os-update
Nice=10
UNIT
cat >/etc/systemd/system/control-center-os-update.timer <<'UNIT'
[Unit]
Description=Control Center OS and package update timer
[Timer]
OnBootSec=5min
OnUnitActiveSec=1min
AccuracySec=15s
Persistent=true
Unit=control-center-os-update.service
[Install]
WantedBy=timers.target
UNIT
systemctl daemon-reload
systemctl enable --now control-center control-center-network-apply.path control-center-market-apply.path control-center-dhcp-apply.path control-center-license-apply.path control-center-update.timer control-center-os-update.timer
sleep 1
curl -fsS http://127.0.0.1:8080/api/health >/dev/null
echo "Control Center $VERSION установлен."
echo 'Редакция по умолчанию: Home. Professional активируется подписанной лицензией.'
echo 'Обновления Control Center и ОС/пакетов доступны в Настройки.'
echo 'Откройте: http://SERVER_IP:8080'
