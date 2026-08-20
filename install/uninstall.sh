#!/usr/bin/env bash
set -Eeuo pipefail
PURGE=0
if [[ ${1:-} == "--purge" ]]; then PURGE=1; shift; fi
if [[ $# -ne 0 ]]; then echo "Usage: $0 [--purge]" >&2; exit 2; fi
[[ $EUID -eq 0 ]] || { echo "installer must run as root" >&2; exit 1; }

systemctl disable --now control-center.service >/dev/null 2>&1 || true
systemctl disable --now control-center-privileged-worker.service >/dev/null 2>&1 || true
rm -f \
  /etc/systemd/system/control-center.service \
  /etc/systemd/system/control-center-privileged-worker.service \
  /usr/local/sbin/control-center-update
rm -rf /usr/local/lib/control-center
systemctl daemon-reload

if (( PURGE )); then
  rm -rf \
    /etc/control-center \
    /var/lib/control-center \
    /var/log/control-center \
    /var/log/control-center-privileged
  id -u control-center >/dev/null 2>&1 && userdel control-center || true
  getent group control-center >/dev/null && groupdel control-center || true
  echo "Control Center and privileged worker uninstalled and data purged."
else
  echo "Control Center and privileged worker uninstalled. Configuration, update trust, state and privileged audit log were preserved."
fi
