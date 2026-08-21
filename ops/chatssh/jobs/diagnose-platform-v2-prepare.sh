#!/usr/bin/env bash
set -Eeuo pipefail

printf '=== RUNTIME ===\n'
/usr/local/lib/control-center/current/control-center build-info --field version || true
/usr/local/lib/control-center/current/control-center build-info --field commit || true

printf '\n=== PREPARE UNIT ===\n'
systemctl show control-center-platform-v2-prepare.service \
  -p LoadState -p ActiveState -p SubState -p Result -p ExecMainStatus \
  -p NoNewPrivileges -p ProtectSystem -p ReadWritePaths -p CapabilityBoundingSet --no-pager || true

printf '\n=== PREPARE JOURNAL ===\n'
journalctl -u control-center-platform-v2-prepare.service -n 120 --no-pager -o short-iso-precise || true

printf '\n=== TARGET STATE ===\n'
stat -c '%A %U:%G %n' /usr/local/sbin/control-center-update /etc/systemd/system/control-center-privileged-worker.service 2>&1 || true
sha256sum /usr/local/sbin/control-center-update /etc/systemd/system/control-center-privileged-worker.service 2>&1 || true
systemctl is-active control-center-privileged-worker.service || true
systemctl is-enabled control-center-privileged-worker.service || true

printf '\n=== MIGRATION STATE ===\n'
find /var/lib/control-center/platform-migrations -maxdepth 1 -type f -printf '%f %m %u:%g\n' 2>/dev/null | sort || true
