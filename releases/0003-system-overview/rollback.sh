#!/usr/bin/env bash
set -Eeuo pipefail

PROJECT="${1:-/opt/srv-control}"
REMOTE_SHA="${2:-unknown}"
RELEASE_ID="0003-system-overview"
STATE_ROOT="/var/lib/srv-deployment"
BACKUP_DIR="${STATE_ROOT}/backups/${REMOTE_SHA}-${RELEASE_ID}"
RELEASE_META="/var/lib/srv-control/release.json"

restore_path() {
    local rel="$1"

    if [[ -f "$BACKUP_DIR/${rel}.absent" ]]; then
        rm -f "$PROJECT/$rel"
        return
    fi

    if [[ -e "$BACKUP_DIR/$rel" ]]; then
        install -d -m 0755 "$PROJECT/$(dirname -- "$rel")"
        cp -a "$BACKUP_DIR/$rel" "$PROJECT/$rel"
    fi
}

for rel in \
    app/core/metrics.py \
    app/routers/ui.py \
    templates/system.html \
    static/js/system.js
do
    restore_path "$rel"
done

if [[ -f "$BACKUP_DIR/.release-json-was-absent" ]]; then
    rm -f "$RELEASE_META"
elif [[ -f "$BACKUP_DIR/release.json" ]]; then
    cp -a "$BACKUP_DIR/release.json" "$RELEASE_META"
fi

systemctl restart srv-control.service

printf 'ROLLBACK PASS: release=%s sha=%s\n' \
    "$RELEASE_ID" "$REMOTE_SHA"
