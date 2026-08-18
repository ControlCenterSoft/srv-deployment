#!/usr/bin/env bash
set -euo pipefail
[[ ${EUID:-$(id -u)} -eq 0 ]] || { echo 'Запустите от root.'; exit 1; }
systemctl disable --now control-center 2>/dev/null || true
rm -f /etc/systemd/system/control-center.service
systemctl daemon-reload
rm -rf /opt/control-center
id control-center >/dev/null 2>&1 && userdel control-center || true
echo 'Control Center удален.'
