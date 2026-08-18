#!/usr/bin/env bash
set -Eeuo pipefail
REMOTE_SHA="${1:-unknown}"
BACKUP="/var/lib/srv-deployment/backups/${REMOTE_SHA}-2.1.3"
[[ -d "$BACKUP" ]] || { echo "ROLLBACK 2.1.3 FAIL: backup not found" >&2; exit 1; }
[[ ! -f "$BACKUP/nginx-site" ]] || cp -a "$BACKUP/nginx-site" /etc/nginx/sites-available/srv-control
if [[ -d "$BACKUP/chrony" ]]; then rm -rf /etc/chrony; cp -a "$BACKUP/chrony" /etc/chrony; fi
[[ ! -f "$BACKUP/release.json" ]] || cp -a "$BACKUP/release.json" /var/lib/srv-control/release.json
nginx -t && systemctl reload nginx.service
systemctl restart chrony.service 2>/dev/null || true
systemctl restart srv-control.service
echo "ROLLBACK 2.1.3 PASS"
