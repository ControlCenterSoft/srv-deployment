#!/usr/bin/env bash
set -Eeuo pipefail
[[ ${EUID:-$(id -u)} -eq 0 ]] || { echo 'Запустите от root.'; exit 1; }
KEEP_DATA=false
[[ "${1:-}" == "--keep-data" ]] && KEEP_DATA=true
units=(
  control-center.service
  control-center-update.timer control-center-update.service
  control-center-os-update.timer control-center-os-update.service
  control-center-network-apply.path control-center-network-apply.service
  control-center-market-apply.path control-center-market-apply.service
  control-center-dhcp-server.service control-center-dhcp-apply.path control-center-dhcp-apply.service
  control-center-license-apply.path control-center-license-apply.service
)
for u in "${units[@]}"; do systemctl disable --now "$u" 2>/dev/null || systemctl stop "$u" 2>/dev/null || true; done
for u in "${units[@]}"; do rm -f "/etc/systemd/system/$u"; done
rm -f /usr/local/sbin/control-center-update /usr/local/sbin/control-center-os-update /usr/local/sbin/control-center-network-apply /usr/local/sbin/control-center-market-apply /usr/local/sbin/control-center-dhcp-apply /usr/local/sbin/control-center-license-apply
rm -rf /opt/control-center /etc/control-center
systemctl daemon-reload
systemctl reset-failed >/dev/null 2>&1 || true
if ! $KEEP_DATA; then
  if [[ -f /var/lib/control-center/modules/dhcp.json ]]; then
    OWNED="$(python3 - /var/lib/control-center/modules/dhcp.json <<'PY'
import json,sys
try:j=json.load(open(sys.argv[1]))
except:j={}
print('true' if j.get('package_owned',True) else 'false')
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
  rm -rf /var/lib/control-center /var/lib/control-center-root /var/lib/control-center-license
else
  echo 'Данные, root rollback state и лицензия сохранены (--keep-data).'
fi
id control-center >/dev/null 2>&1 && userdel control-center || true
echo 'Control Center удален.'
