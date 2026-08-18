#!/usr/bin/env bash
set -Eeuo pipefail
[[ ${EUID:-$(id -u)} -eq 0 ]] || { echo 'Запустите от root: sudo bash install/install.sh'; exit 1; }
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_DIR=/opt/control-center
STATE_DIR=/var/lib/control-center
SERVICE_USER=control-center
VERSION=1.0.3
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y python3 python3-venv iproute2 ca-certificates curl git util-linux netplan.io procps
if ! id "$SERVICE_USER" >/dev/null 2>&1; then useradd --system --home "$APP_DIR" --shell /usr/sbin/nologin "$SERVICE_USER"; fi
install -d -m 0755 "$APP_DIR" "$STATE_DIR"
if [[ ! -f "$STATE_DIR/update-settings.json" ]]; then printf '%s\n' '{"automatic_updates":true,"interval_minutes":60,"channel":"production"}' >"$STATE_DIR/update-settings.json"; fi
python3 - "$STATE_DIR/update-settings.json" <<'PY'
import json,sys
p=sys.argv[1]
try:s=json.load(open(p))
except:s={}
legacy={'hourly':60,'daily':1440,'weekly':10080}
try:mins=int(s.get('interval_minutes',legacy.get(s.get('frequency'),60)))
except:mins=60
s={'automatic_updates':bool(s.get('automatic_updates',True)),'interval_minutes':max(5,min(mins,10080)),'channel':'production'}
open(p,'w').write(json.dumps(s,ensure_ascii=False,indent=2)+'\n')
PY
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
install -m 0755 "$ROOT_DIR/network/control-center-network-apply" /usr/local/sbin/control-center-network-apply
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
cat >/etc/systemd/system/control-center-network-apply.service <<'UNIT'
[Unit]
Description=Control Center apply validated network configuration
After=network-pre.target
[Service]
Type=oneshot
ExecStart=/usr/local/sbin/control-center-network-apply
UNIT
cat >/etc/systemd/system/control-center-network-apply.path <<'UNIT'
[Unit]
Description=Control Center network configuration watcher
[Path]
PathExists=/var/lib/control-center/network-pending.json
Unit=control-center-network-apply.service
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
UNIT
cat >/etc/systemd/system/control-center-update.timer <<'UNIT'
[Unit]
Description=Control Center automatic update timer
[Timer]
OnBootSec=2min
OnUnitActiveSec=1min
AccuracySec=15s
Persistent=true
Unit=control-center-update.service
[Install]
WantedBy=timers.target
UNIT
systemctl daemon-reload
systemctl enable --now control-center
systemctl enable --now control-center-network-apply.path
systemctl enable --now control-center-update.timer
sleep 1
curl -fsS http://127.0.0.1:8080/api/health >/dev/null
echo "Control Center $VERSION установлен."
echo 'Dashboard: CPU/RAM/Top-3/Storage/WAN telemetry активен.'
echo 'Интервал автообновления задается вручную в минутах.'
echo 'Откройте: http://SERVER_IP:8080'
