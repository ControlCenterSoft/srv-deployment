#!/usr/bin/env bash
set -Eeuo pipefail
umask 027

PROJECT="${1:-/opt/srv-control}"
REMOTE_SHA="${2:-unknown}"
RELEASE_ID="0003-system-overview"
RELEASE_VERSION="0.3.0"
RELEASE_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
PAYLOAD="${RELEASE_DIR}/payload"
STATE_ROOT="/var/lib/srv-deployment"
BACKUP_DIR="${STATE_ROOT}/backups/${REMOTE_SHA}-${RELEASE_ID}"
RELEASE_META="/var/lib/srv-control/release.json"

log() {
    printf '%s %s\n' "$(date -Is)" "$*"
}

install -d -m 0750 "$BACKUP_DIR"

backup_path() {
    local rel="$1"

    install -d -m 0750 "$BACKUP_DIR/$(dirname -- "$rel")"

    if [[ -e "$PROJECT/$rel" ]]; then
        cp -a "$PROJECT/$rel" "$BACKUP_DIR/$rel"
    else
        : > "$BACKUP_DIR/${rel}.absent"
    fi
}

for rel in \
    app/core/metrics.py \
    app/routers/ui.py \
    templates/system.html \
    static/js/system.js
do
    backup_path "$rel"
done

if [[ -f "$RELEASE_META" ]]; then
    cp -a "$RELEASE_META" "$BACKUP_DIR/release.json"
else
    : > "$BACKUP_DIR/.release-json-was-absent"
fi

install -m 0644 "$PAYLOAD/app/core/metrics.py" "$PROJECT/app/core/metrics.py"
install -m 0644 "$PAYLOAD/app/routers/ui.py" "$PROJECT/app/routers/ui.py"
install -m 0644 "$PAYLOAD/templates/system.html" "$PROJECT/templates/system.html"
install -m 0644 "$PAYLOAD/static/js/system.js" "$PROJECT/static/js/system.js"

sync_time="$(date -Is)"
tmp="$(mktemp /var/lib/srv-control/release.json.tmp.XXXXXX)"
python3 - "$tmp" "$RELEASE_VERSION" "$RELEASE_ID" "$sync_time" "$REMOTE_SHA" <<'PY'
import json
import pathlib
import sys

path = pathlib.Path(sys.argv[1])
payload = {
    "version": sys.argv[2],
    "release_id": sys.argv[3],
    "synced_at": sys.argv[4],
    "git_sha": sys.argv[5],
}
path.write_text(
    json.dumps(
        payload,
        ensure_ascii=False,
        indent=2,
    ) + "\n",
    encoding="utf-8",
)
PY
chmod 0644 "$tmp"
mv -f "$tmp" "$RELEASE_META"

systemctl restart srv-control.service

log "APPLY PASS: release=${RELEASE_VERSION} sha=${REMOTE_SHA} synced_at=${sync_time}"
