#!/usr/bin/env bash
set -Eeuo pipefail
umask 027

PROJECT="${1:-/opt/srv-control}"
REMOTE_SHA="${2:-unknown}"
RELEASE_ID="0009-system-action-history"
RELEASE_VERSION="0.9.0"
RELEASE_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_ROOT="$(cd -- "${RELEASE_DIR}/../.." && pwd -P)"
PAYLOAD="${REPO_ROOT}/installer/payload"
RELOAD_HELPER="${REPO_ROOT}/deploy/reload-srv-control.sh"
STATE_ROOT="/var/lib/srv-deployment"
BACKUP_DIR="${STATE_ROOT}/backups/${REMOTE_SHA}-${RELEASE_ID}"
RELEASE_META="/var/lib/srv-control/release.json"

log() {
    printf '%s %s\n' "$(date -Is)" "$*"
}

install -d -m 0750 "$BACKUP_DIR/project"

backup_project_path() {
    local rel="$1"
    install -d -m 0750 "$BACKUP_DIR/project/$(dirname -- "$rel")"
    if [[ -e "$PROJECT/$rel" ]]; then
        cp -a "$PROJECT/$rel" "$BACKUP_DIR/project/$rel"
    else
        : > "$BACKUP_DIR/project/${rel}.absent"
    fi
}

for rel in \
    app/core/system_admin.py \
    templates/system.html \
    static/js/system.js \
    static/css/system-admin.css
do
    backup_project_path "$rel"
done

if [[ -f "$RELEASE_META" ]]; then
    cp -a "$RELEASE_META" "$BACKUP_DIR/release.json"
else
    : > "$BACKUP_DIR/.release-json-was-absent"
fi

systemctl show srv-control.service -p MainPID --value > "$BACKUP_DIR/main-pid.before"

install -m 0644 "$PAYLOAD/app/core/system_admin.py" "$PROJECT/app/core/system_admin.py"
install -m 0644 "$PAYLOAD/templates/system.html" "$PROJECT/templates/system.html"
install -m 0644 "$PAYLOAD/static/js/system.js" "$PROJECT/static/js/system.js"
install -m 0644 "$PAYLOAD/static/css/system-admin.css" "$PROJECT/static/css/system-admin.css"

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
    json.dumps(payload, ensure_ascii=False, indent=2) + "\n",
    encoding="utf-8",
)
PY
chmod 0644 "$tmp"
mv -f "$tmp" "$RELEASE_META"

"$RELOAD_HELPER" srv-control.service http://127.0.0.1:8876/api/v1/health

log "APPLY PASS: release=${RELEASE_VERSION} sha=${REMOTE_SHA} synced_at=${sync_time}"
