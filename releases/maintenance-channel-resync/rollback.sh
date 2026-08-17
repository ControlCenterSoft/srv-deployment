#!/usr/bin/env bash
set -u

PROJECT="${1:-/opt/srv-control}"
REMOTE_SHA="${2:-unknown}"
RELEASE_ID="maintenance-channel-resync"
BACKUP_DIR="/var/lib/srv-deployment/backups/${REMOTE_SHA}-${RELEASE_ID}"
RELEASE_META="/var/lib/srv-control/release.json"

if [[ ! -s "$BACKUP_DIR/release.json" ]]; then
    printf 'ROLLBACK FAIL: release metadata backup missing\n' >&2
    exit 1
fi

cp -a "$BACKUP_DIR/release.json" "$RELEASE_META"
printf 'ROLLBACK PASS: maintenance resync sha=%s\n' "$REMOTE_SHA"
