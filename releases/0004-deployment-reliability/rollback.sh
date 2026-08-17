#!/usr/bin/env bash
set -u

PROJECT="${1:-/opt/srv-control}"
REMOTE_SHA="${2:-unknown}"
RELEASE_ID="0004-deployment-reliability"
STATE_ROOT="/var/lib/srv-deployment"
BACKUP_DIR="${STATE_ROOT}/backups/${REMOTE_SHA}-${RELEASE_ID}"
RELEASE_META="/var/lib/srv-control/release.json"
SERVICE_UNIT="/etc/systemd/system/srv-control.service"
rc=0

log() {
    printf '%s %s\n' "$(date -Is)" "$*"
}

if [[ ! -d "$BACKUP_DIR" ]]; then
    log "ROLLBACK FAIL: backup directory is missing: $BACKUP_DIR"
    exit 1
fi

for rel in \
    app/routers/api.py \
    templates/system.html \
    static/js/system.js
do
    if [[ -f "$BACKUP_DIR/project/$rel" ]]; then
        cp -a "$BACKUP_DIR/project/$rel" "$PROJECT/$rel" || rc=1
    elif [[ -f "$BACKUP_DIR/project/${rel}.absent" ]]; then
        rm -f "$PROJECT/$rel" || rc=1
    else
        log "ROLLBACK WARN: backup metadata missing for $rel"
        rc=1
    fi
done

if [[ -f "$BACKUP_DIR/srv-control.service" ]]; then
    cp -a "$BACKUP_DIR/srv-control.service" "$SERVICE_UNIT" || rc=1
elif [[ -f "$BACKUP_DIR/.service-unit-was-absent" ]]; then
    rm -f "$SERVICE_UNIT" || rc=1
fi

if [[ -f "$BACKUP_DIR/release.json" ]]; then
    cp -a "$BACKUP_DIR/release.json" "$RELEASE_META" || rc=1
elif [[ -f "$BACKUP_DIR/.release-json-was-absent" ]]; then
    rm -f "$RELEASE_META" || rc=1
fi

systemctl daemon-reload || rc=1
systemctl restart srv-control.service || rc=1

if (( rc == 0 )); then
    log "ROLLBACK PASS: release=$RELEASE_ID sha=$REMOTE_SHA"
else
    log "ROLLBACK FAIL: restore completed with errors"
fi

exit "$rc"
