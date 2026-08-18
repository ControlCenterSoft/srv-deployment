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
  control-center-dhcp-apply.path control-center-dhcp-apply.service
  control-center-license-apply.path control-center-license-apply.service
)
for u in "${units[@]}"; do systemctl disable --now "$u" 2>/dev/null || systemctl stop "$u" 2>/dev/null || true; done
for u in "${units[@]}"; do rm -f "/etc/systemd/system/$u"; done
rm -f /usr/local/sbin/control-center-update /usr/local/sbin/control-center-os-update /usr/local/sbin/control-center-network-apply /usr/local/sbin/control-center-market-apply /usr/local/sbin/control-center-dhcp-apply /usr/local/sbin/control-center-license-apply
rm -rf /opt/control-center /etc/control-center
systemctl daemon-reload
systemctl reset-failed >/dev/null 2>&1 || true
if ! $KEEP_DATA; then
  rm -rf /var/lib/control-center /var/lib/control-center-license
else
  echo 'Данные и лицензия сохранены (--keep-data).'
fi
id control-center >/dev/null 2>&1 && userdel control-center || true
echo 'Control Center удален.'
