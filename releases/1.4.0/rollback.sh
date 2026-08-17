#!/usr/bin/env bash
set -Eeuo pipefail
PROJECT="${1:-/opt/srv-control}"; REMOTE_SHA="${2:-unknown}"; RELEASE_ID=1.4.0
RELEASE_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"; REPO_ROOT="$(cd -- "$RELEASE_DIR/../.." && pwd -P)"; BACKUP_DIR="/var/lib/srv-deployment/backups/${REMOTE_SHA}-${RELEASE_ID}"
[[ -d "$BACKUP_DIR" ]] || { echo "ROLLBACK FAIL: backup dir missing: $BACKUP_DIR" >&2; exit 1; }
log(){ printf '%s %s\n' "$(date -Is)" "$*"; }
subprocess_units=(srv-control-release14-agent.path srv-control-backup-retention.path); for u in "${subprocess_units[@]}"; do systemctl disable --now "$u" >/dev/null 2>&1 || true; done
log "Downgrading database to 1.3 schema"
runuser -u srv-control -- env PYTHONPATH="$PROJECT" PYTHONDONTWRITEBYTECODE=1 "$PROJECT/venv/bin/alembic" -c "$PROJECT/alembic.ini" downgrade 13f0a1300001
restore_project(){ local r="$1"; if [[ -e "$BACKUP_DIR/project/$r" || -L "$BACKUP_DIR/project/$r" ]]; then install -d "$(dirname "$PROJECT/$r")"; rm -rf "$PROJECT/$r"; cp -a "$BACKUP_DIR/project/$r" "$PROJECT/$r"; elif [[ -f "$BACKUP_DIR/project/${r}.absent" ]]; then rm -rf "$PROJECT/$r"; fi; }
restore_abs(){ local p="$1" k="${1#/}"; if [[ -e "$BACKUP_DIR/system/$k" || -L "$BACKUP_DIR/system/$k" ]]; then install -d "$(dirname "$p")"; rm -rf "$p"; cp -a "$BACKUP_DIR/system/$k" "$p"; elif [[ -f "$BACKUP_DIR/system/${k}.absent" ]]; then rm -rf "$p"; fi; }
changed=(app/main.py app/core/release14.py app/routers/release14.py migrations/versions/14f0a1400001_dhcp_pxe_network_redirects.py templates/shell-1.4.html templates/services-1.4.html templates/dhcp-1.4.html templates/pxe-1.4.html templates/network-1.4.html templates/shares-1.4.html templates/system-1.4.html static/js/services-1.4.js static/js/dhcp-1.4.js static/js/pxe-1.4.js static/js/network-1.4.js static/js/shares-1.4.js static/js/system-1.4.js static/css/release-1.4.css)
for p in "${changed[@]}"; do restore_project "$p"; done
for p in /usr/local/libexec/srv-control-release14-agent /etc/systemd/system/srv-control-release14-agent.service /etc/systemd/system/srv-control-release14-agent.path /etc/systemd/system/srv-control-backup-retention.service /etc/systemd/system/srv-control-backup-retention.path; do restore_abs "$p"; done
if [[ -f "$BACKUP_DIR/state/release.json" ]]; then cp -a "$BACKUP_DIR/state/release.json" /var/lib/srv-control/release.json; elif [[ -f "$BACKUP_DIR/state/release.json.absent" ]]; then rm -f /var/lib/srv-control/release.json; fi
systemctl daemon-reload
"$REPO_ROOT/deploy/reload-srv-control.sh" srv-control.service http://127.0.0.1:8876/api/v1/health
log "ROLLBACK PASS: restored pre-1.4.0 application and schema"
