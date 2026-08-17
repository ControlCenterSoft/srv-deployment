#!/usr/bin/env bash
set -u

PROJECT="${1:-/opt/srv-control}"
REMOTE_SHA="${2:-unknown}"
RELEASE_ID="0005-network-overview"
RELEASE_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_ROOT="$(cd -- "${RELEASE_DIR}/../.." && pwd -P)"
RELOAD_HELPER="${REPO_ROOT}/deploy/reload-srv-control.sh"
STATE_ROOT="/var/lib/srv-deployment"
BACKUP_DIR="${STATE_ROOT}/backups/${REMOTE_SHA}-${RELEASE_ID}"
RELEASE_META="/var/lib/srv-control/release.json"
rc=0

log() {
    printf '%s %s\n' "$(date -Is)" "$*"
}

if [[ ! -d "$BACKUP_DIR" ]]; then
    log "ROLLBACK FAIL: backup directory is missing: $BACKUP_DIR"
    exit 1
fi

for rel in \
    app/core/network.py \
    app/routers/api.py \
    app/routers/ui.py \
    templates/internet.html \
    static/js/internet.js
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

if [[ -f "$BACKUP_DIR/release.json" ]]; then
    cp -a "$BACKUP_DIR/release.json" "$RELEASE_META" || rc=1
elif [[ -f "$BACKUP_DIR/.release-json-was-absent" ]]; then
    rm -f "$RELEASE_META" || rc=1
fi

if [[ -x "$RELOAD_HELPER" ]]; then
    "$RELOAD_HELPER" srv-control.service http://127.0.0.1:8876/api/v1/health || rc=1
else
    systemctl restart srv-control.service || rc=1
fi

if (( rc == 0 )); then
    log "ROLLBACK PASS: release=$RELEASE_ID sha=$REMOTE_SHA"
else
    log "ROLLBACK FAIL: restore completed with errors"
fi

exit "$rc"
