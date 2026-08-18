#!/usr/bin/env bash
set -Eeuo pipefail
[[ ${EUID:-$(id -u)} -eq 0 ]] || { echo 'Запустите от root.'; exit 1; }
KEEP_DATA=false
[[ "${1:-}" == "--keep-data" ]] && KEEP_DATA=true
SYSTEM_STATE=/var/lib/control-center-system
DB_NAME=control_center
units=(
  control-center.service
  control-center-update.timer control-center-update.service
  control-center-os-update.timer control-center-os-update.service
  control-center-web-apply.path control-center-web-apply.service
  control-center-network-apply.path control-center-network-apply.service
  control-center-market-apply.path control-center-market-apply.service
  control-center-dhcp-server.service control-center-dhcp-apply.path control-center-dhcp-apply.service
  control-center-license-apply.path control-center-license-apply.service
)
for u in "${units[@]}"; do systemctl disable --now "$u" 2>/dev/null || systemctl stop "$u" 2>/dev/null || true; done
for u in "${units[@]}"; do rm -f "/etc/systemd/system/$u"; done
rm -f /usr/local/sbin/control-center-update /usr/local/sbin/control-center-os-update /usr/local/sbin/control-center-web-apply /usr/local/sbin/control-center-network-apply /usr/local/sbin/control-center-market-apply /usr/local/sbin/control-center-dhcp-apply /usr/local/sbin/control-center-license-apply
rm -rf /opt/control-center /etc/control-center
systemctl daemon-reload
systemctl reset-failed >/dev/null 2>&1 || true

if ! $KEEP_DATA; then
  if [[ -f "$SYSTEM_STATE/modules/dhcp.json" ]]; then
    OWNED="$(python3 - "$SYSTEM_STATE/modules/dhcp.json" <<'PY'
import json,sys
try:j=json.load(open(sys.argv[1]))
except:j={}
print('true' if j.get('installed') and j.get('package_owned',False) else 'false')
PY
)"
    if [[ "$OWNED" == true ]]; then
      exec 8>/run/control-center-apt.lock
      if flock -w 300 8; then
        export DEBIAN_FRONTEND=noninteractive
        apt-get remove -y dnsmasq || true
      fi
    fi
  fi
  rm -f /etc/dnsmasq.d/control-center-dhcp.conf

  if systemctl is-active --quiet postgresql || systemctl start postgresql >/dev/null 2>&1; then
    if runuser -u postgres -- psql -d postgres -Atqc "SELECT 1 FROM pg_database WHERE datname='$DB_NAME'" 2>/dev/null | grep -qx 1; then
      runuser -u postgres -- psql -d postgres -v ON_ERROR_STOP=1 -c "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname='$DB_NAME' AND pid<>pg_backend_pid();" >/dev/null || true
      runuser -u postgres -- dropdb --if-exists "$DB_NAME" || true
    fi
    if runuser -u postgres -- psql -d postgres -Atqc "SELECT 1 FROM pg_roles WHERE rolname='control-center'" 2>/dev/null | grep -qx 1; then
      runuser -u postgres -- psql -d postgres -v ON_ERROR_STOP=1 -c 'DROP ROLE IF EXISTS "control-center";' >/dev/null || true
    fi
  fi

  rm -rf /var/lib/control-center /var/lib/control-center-system /var/lib/control-center-root /var/lib/control-center-license
  id control-center >/dev/null 2>&1 && userdel control-center || true
  echo 'База control_center и роль PostgreSQL control-center удалены. Сам PostgreSQL не удаляется, чтобы не затронуть другие приложения.'
else
  echo 'Web/system/root/license state, PostgreSQL database и служебная УЗ control-center сохранены (--keep-data).'
fi
echo 'Control Center удален.'
