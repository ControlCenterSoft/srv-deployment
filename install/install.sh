#!/usr/bin/env bash
set -Eeuo pipefail
[[ ${EUID:-$(id -u)} -eq 0 ]] || { echo 'Запустите от root: sudo bash install/install.sh'; exit 1; }
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_DIR=/opt/control-center
STATE_DIR=/var/lib/control-center
SYSTEM_STATE_DIR=/var/lib/control-center-system
ROOT_STATE_DIR=/var/lib/control-center-root
LICENSE_DIR=/var/lib/control-center-license
SERVICE_USER=control-center
DB_NAME=control_center
DB_DSN="dbname=control_center user=control-center host=/var/run/postgresql"
DB_ENV=/etc/control-center/database.env
WEB_ENV=/etc/control-center/web.env
VERSION=1.0.7
BUILD=20260818.2
APT_LOCK=/run/control-center-apt.lock

exec 8>"$APT_LOCK"
flock -w 900 8 || { echo 'Менеджер пакетов занят. Повторите установку позже.'; exit 1; }
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y python3 python3-venv iproute2 ca-certificates curl git util-linux netplan.io procps openssl postgresql postgresql-client

if ! id "$SERVICE_USER" >/dev/null 2>&1; then useradd --system --home "$APP_DIR" --shell /usr/sbin/nologin "$SERVICE_USER"; fi
install -d -o "$SERVICE_USER" -g "$SERVICE_USER" -m 0755 "$APP_DIR" "$STATE_DIR"
install -d -o root -g "$SERVICE_USER" -m 0750 "$SYSTEM_STATE_DIR" "$SYSTEM_STATE_DIR/modules" "$LICENSE_DIR"
install -d -o root -g root -m 0700 "$ROOT_STATE_DIR"
install -d -o root -g root -m 0755 /etc/control-center

systemctl enable --now postgresql >/dev/null
for _ in $(seq 1 30); do
  if runuser -u postgres -- pg_isready -q >/dev/null 2>&1; then break; fi
  sleep 1
done
runuser -u postgres -- pg_isready -q || { echo 'PostgreSQL не запустился.' >&2; exit 1; }

if ! runuser -u postgres -- psql -d postgres -Atqc "SELECT 1 FROM pg_roles WHERE rolname='$SERVICE_USER'" | grep -qx 1; then
  runuser -u postgres -- psql -v ON_ERROR_STOP=1 -d postgres -c 'CREATE ROLE "control-center" LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION CONNECTION LIMIT 20 PASSWORD NULL;'
else
  runuser -u postgres -- psql -v ON_ERROR_STOP=1 -d postgres -c 'ALTER ROLE "control-center" LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION CONNECTION LIMIT 20 PASSWORD NULL;'
fi
if ! runuser -u postgres -- psql -d postgres -Atqc "SELECT 1 FROM pg_database WHERE datname='$DB_NAME'" | grep -qx 1; then
  runuser -u postgres -- createdb --owner="$SERVICE_USER" "$DB_NAME"
fi
runuser -u postgres -- psql -v ON_ERROR_STOP=1 -d postgres -c 'ALTER DATABASE control_center OWNER TO "control-center";'
if ! runuser -u "$SERVICE_USER" -- psql -d "$DB_NAME" -Atqc 'SELECT current_user' | grep -qx "$SERVICE_USER"; then
  echo 'PostgreSQL local peer authentication для пользователя control-center недоступна.' >&2
  echo 'Проверьте pg_hba.conf: локальные Unix-socket подключения должны разрешать peer authentication.' >&2
  exit 1
fi
printf 'CONTROL_CENTER_DB_DSN="%s"\n' "$DB_DSN" >"$DB_ENV"
chown root:root "$DB_ENV"; chmod 0600 "$DB_ENV"

for name in network-config.json dhcp-config.json; do
  old="$STATE_DIR/$name"; new="$SYSTEM_STATE_DIR/$name"
  if [[ ! -e "$new" && -f "$old" && ! -L "$old" ]]; then
    cp -- "$old" "$new"
    chown root:"$SERVICE_USER" "$new"; chmod 0640 "$new"
  fi
done

if [[ ! -f "$SYSTEM_STATE_DIR/modules/dhcp.json" && -f "$STATE_DIR/modules/dhcp.json" && ! -L "$STATE_DIR/modules/dhcp.json" ]] \
   && dpkg-query -W -f='${Status}' dnsmasq 2>/dev/null | grep -q 'install ok installed' \
   && [[ -f /etc/dnsmasq.d/control-center-dhcp.conf ]] \
   && dnsmasq --test --conf-file=/etc/dnsmasq.d/control-center-dhcp.conf >/dev/null 2>&1; then
  configured=false; grep -q '^dhcp-range=' /etc/dnsmasq.d/control-center-dhcp.conf && configured=true
  printf '{"installed":true,"package":"dnsmasq","package_owned":false,"configured":%s}\n' "$configured" >"$SYSTEM_STATE_DIR/modules/dhcp.json"
  chown root:"$SERVICE_USER" "$SYSTEM_STATE_DIR/modules/dhcp.json"; chmod 0640 "$SYSTEM_STATE_DIR/modules/dhcp.json"
fi

rm -f "$STATE_DIR/license.json"
rm -rf "$STATE_DIR"/rollback-* "$STATE_DIR/90-control-center.yaml.rollback" "$STATE_DIR/control-center-dhcp.conf.rollback"
rm -f "$STATE_DIR/network-pending.json" "$STATE_DIR/market-pending.json" "$STATE_DIR/dhcp-pending.json" "$STATE_DIR/license-pending.json" "$STATE_DIR/os-update-now" "$STATE_DIR/web-pending.json"

[[ -f "$STATE_DIR/update-settings.json" && ! -L "$STATE_DIR/update-settings.json" ]] || { rm -f "$STATE_DIR/update-settings.json"; printf '%s\n' '{"automatic_updates":true,"interval_minutes":60,"channel":"production"}' >"$STATE_DIR/update-settings.json"; }
[[ -f "$STATE_DIR/os-update-settings.json" && ! -L "$STATE_DIR/os-update-settings.json" ]] || { rm -f "$STATE_DIR/os-update-settings.json"; printf '%s\n' '{"automatic_updates":false,"interval_minutes":1440}' >"$STATE_DIR/os-update-settings.json"; }
chown "$SERVICE_USER:$SERVICE_USER" "$STATE_DIR" "$STATE_DIR/update-settings.json" "$STATE_DIR/os-update-settings.json"
chmod 0640 "$STATE_DIR/update-settings.json" "$STATE_DIR/os-update-settings.json"

rm -rf "$STATE_DIR/modules"; ln -s "$SYSTEM_STATE_DIR/modules" "$STATE_DIR/modules"
for name in update-status.json os-update-status.json license-status.json network-config.json network-status.json market-status.json dhcp-config.json dhcp-status.json web-config.json web-status.json; do
  rm -f "$STATE_DIR/$name"
  ln -s "$SYSTEM_STATE_DIR/$name" "$STATE_DIR/$name"
done
chown -h "$SERVICE_USER:$SERVICE_USER" "$STATE_DIR/modules" "$STATE_DIR"/*.json 2>/dev/null || true
chown -R root:"$SERVICE_USER" "$SYSTEM_STATE_DIR" "$LICENSE_DIR"
find "$SYSTEM_STATE_DIR" -type d -exec chmod 0750 {} +
find "$SYSTEM_STATE_DIR" -type f -exec chmod 0640 {} +
chmod 0750 "$LICENSE_DIR"
if [[ -f "$LICENSE_DIR/license.json" ]]; then chown root:"$SERVICE_USER" "$LICENSE_DIR/license.json"; chmod 0640 "$LICENSE_DIR/license.json"; fi
if [[ -f /etc/netplan/90-control-center.yaml ]]; then chown root:"$SERVICE_USER" /etc/netplan/90-control-center.yaml; chmod 0640 /etc/netplan/90-control-center.yaml; fi

OLD_WEB_PORT=""
if [[ -f "$WEB_ENV" ]]; then OLD_WEB_PORT="$(sed -n 's/^CONTROL_CENTER_PORT=\([0-9][0-9]*\)$/\1/p' "$WEB_ENV" | head -n1)"; fi

systemctl stop control-center 2>/dev/null || true
rm -rf "$APP_DIR/app" "$APP_DIR/venv"
cp -a "$ROOT_DIR/app" "$APP_DIR/app"
printf '%s\n' "$VERSION" >"$APP_DIR/VERSION"
printf '%s\n' "$BUILD" >"$APP_DIR/BUILD"
python3 -m venv "$APP_DIR/venv"
"$APP_DIR/venv/bin/pip" install --upgrade pip
"$APP_DIR/venv/bin/pip" install -r "$ROOT_DIR/requirements.txt"
chown -R "$SERVICE_USER:$SERVICE_USER" "$APP_DIR"

runuser -u "$SERVICE_USER" -- env CONTROL_CENTER_DB_DSN="$DB_DSN" "$APP_DIR/venv/bin/python" "$APP_DIR/app/db_migrate.py"
WEB_PORT="$OLD_WEB_PORT"
if [[ -z "$WEB_PORT" ]]; then
  WEB_PORT="$(runuser -u "$SERVICE_USER" -- env CONTROL_CENTER_DB_DSN="$DB_DSN" "$APP_DIR/venv/bin/python" "$APP_DIR/app/db_cli.py" get-web-port 2>/dev/null || echo 8080)"
fi
[[ "$WEB_PORT" =~ ^[0-9]+$ ]] && (( WEB_PORT >= 1024 && WEB_PORT <= 65535 )) || WEB_PORT=8080
printf 'CONTROL_CENTER_PORT=%s\n' "$WEB_PORT" >"$WEB_ENV"
chown root:root "$WEB_ENV"; chmod 0600 "$WEB_ENV"
runuser -u "$SERVICE_USER" -- env CONTROL_CENTER_DB_DSN="$DB_DSN" "$APP_DIR/venv/bin/python" "$APP_DIR/app/db_cli.py" set-web-port "$WEB_PORT" >/dev/null
runuser -u "$SERVICE_USER" -- env CONTROL_CENTER_DB_DSN="$DB_DSN" CONTROL_CENTER_PORT="$WEB_PORT" "$APP_DIR/venv/bin/python" - <<'PY'
import sys
sys.path.insert(0,'/opt/control-center/app')
import main,database
main.APP_VERSION='1.0.7'; main.APP_BUILD='20260818.2'
database.bootstrap_from_runtime(main)
PY

install -m 0755 "$ROOT_DIR/update/control-center-update" /usr/local/sbin/control-center-update
install -m 0755 "$ROOT_DIR/update/control-center-os-update" /usr/local/sbin/control-center-os-update
install -m 0755 "$ROOT_DIR/network/control-center-network-apply" /usr/local/sbin/control-center-network-apply
install -m 0755 "$ROOT_DIR/market/control-center-market-apply" /usr/local/sbin/control-center-market-apply
install -m 0755 "$ROOT_DIR/market/control-center-dhcp-apply" /usr/local/sbin/control-center-dhcp-apply
install -m 0755 "$ROOT_DIR/license/control-center-license-apply" /usr/local/sbin/control-center-license-apply
install -m 0755 "$ROOT_DIR/system/control-center-web-apply" /usr/local/sbin/control-center-web-apply
install -m 0644 "$ROOT_DIR/license/vendor-public.pem" /etc/control-center/license-public.pem

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
ExecStart=/opt/control-center/venv/bin/gunicorn --workers 2 --threads 2 --timeout 30 --bind 0.0.0.0:${CONTROL_CENTER_PORT} --access-logfile - --error-logfile - wsgi:app
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
ReadOnlyPaths=/var/lib/control-center-system /var/lib/control-center-license /etc/netplan/90-control-center.yaml /etc/dnsmasq.d/control-center-dhcp.conf
InaccessiblePaths=/var/lib/control-center-root
[Install]
WantedBy=multi-user.target
UNIT
cat >/etc/systemd/system/control-center-web-apply.service <<'UNIT'
[Unit]
Description=Control Center Web port configuration apply
After=postgresql.service
Wants=postgresql.service
[Service]
Type=oneshot
EnvironmentFile=-/etc/control-center/database.env
ExecStart=/usr/local/sbin/control-center-web-apply
UNIT
cat >/etc/systemd/system/control-center-web-apply.path <<'UNIT'
[Unit]
Description=Control Center Web port request watcher
[Path]
PathExists=/var/lib/control-center/web-pending.json
Unit=control-center-web-apply.service
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
cat >/etc/systemd/system/control-center-dhcp-server.service <<'UNIT'
[Unit]
Description=Control Center DHCP Server
After=network-online.target
Wants=network-online.target
ConditionPathExists=/etc/dnsmasq.d/control-center-dhcp.conf
[Service]
Type=simple
ExecStart=/usr/sbin/dnsmasq --keep-in-foreground --conf-file=/etc/dnsmasq.d/control-center-dhcp.conf
Restart=on-failure
RestartSec=3
NoNewPrivileges=true
PrivateTmp=true
ProtectHome=true
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
systemctl enable --now control-center control-center-web-apply.path control-center-network-apply.path control-center-market-apply.path control-center-dhcp-apply.path control-center-license-apply.path control-center-update.timer control-center-os-update.timer
if [[ -f "$SYSTEM_STATE_DIR/modules/dhcp.json" ]] && python3 - "$SYSTEM_STATE_DIR/modules/dhcp.json" <<'PY'
import json,sys
try:j=json.load(open(sys.argv[1]))
except:raise SystemExit(1)
raise SystemExit(0 if j.get('installed') else 1)
PY
then
  systemctl disable --now dnsmasq.service >/dev/null 2>&1 || true
  if command -v dnsmasq >/dev/null 2>&1 && grep -q '^dhcp-range=' /etc/dnsmasq.d/control-center-dhcp.conf 2>/dev/null && dnsmasq --test --conf-file=/etc/dnsmasq.d/control-center-dhcp.conf >/dev/null 2>&1; then
    systemctl enable --now control-center-dhcp-server.service
  fi
fi
sleep 2
HEALTH="$(curl -fsS "http://127.0.0.1:$WEB_PORT/api/health")"
python3 - "$HEALTH" "$VERSION" "$BUILD" <<'PY'
import json,sys
j=json.loads(sys.argv[1]); version=sys.argv[2]; build=sys.argv[3]
assert j.get('status')=='ok' and j.get('version')==version and j.get('build')==build, j
assert j.get('database')=='ok', j
PY
DB_HEALTH="$(curl -fsS "http://127.0.0.1:$WEB_PORT/api/database/status")"
python3 - "$DB_HEALTH" <<'PY'
import json,sys
j=json.loads(sys.argv[1]); assert j.get('ok') is True and j.get('database')=='control_center', j
PY

echo "Control Center $VERSION build $BUILD установлен."
echo "PostgreSQL: локальная БД $DB_NAME, Unix socket + peer authentication."
echo "Web UI: Gunicorn production WSGI, порт $WEB_PORT."
echo 'Порт Web UI можно изменить в Настройки → Web-панель.'
echo "Откройте: http://SERVER_IP:$WEB_PORT"
