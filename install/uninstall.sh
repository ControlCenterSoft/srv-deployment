#!/usr/bin/env bash
set -Eeuo pipefail
[[ ${EUID:-$(id -u)} -eq 0 ]] || { echo 'Запустите от root.'; exit 1; }
systemctl disable --now control-center-update.timer 2>/dev/null || true
systemctl stop control-center-update.service 2>/dev/null || true
systemctl disable --now control-center 2>/dev/null || true
rm -f /etc/systemd/system/control-center.service /etc/systemd/system/control-center-update.service /etc/systemd/system/control-center-update.timer
rm -f /usr/local/sbin/control-center-update
systemctl daemon-reload
rm -rf /opt/control-center /var/lib/control-center
id control-center >/dev/null 2>&1 && userdel control-center || true
echo 'Control Center удален.'
