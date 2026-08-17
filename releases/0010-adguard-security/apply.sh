#!/usr/bin/env bash
set -Eeuo pipefail
umask 027

PROJECT="${1:-/opt/srv-control}"
REMOTE_SHA="${2:-unknown}"
RELEASE_ID="0010-adguard-security"
RELEASE_VERSION="0.10.0"
RELEASE_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_ROOT="$(cd -- "${RELEASE_DIR}/../.." && pwd -P)"
PAYLOAD="${REPO_ROOT}/installer/payload"
RELOAD_HELPER="${REPO_ROOT}/deploy/reload-srv-control.sh"
SYSTEM_INSTALLER="${REPO_ROOT}/installer/install-system-admin.sh"
BACKUP_DIR="/var/lib/srv-deployment/backups/${REMOTE_SHA}-${RELEASE_ID}"
RELEASE_META="/var/lib/srv-control/release.json"

log() { printf '%s %s\n' "$(date -Is)" "$*"; }
install -d -m 0750 "$BACKUP_DIR/project" "$BACKUP_DIR/system"

backup_project_path() {
    local rel="$1"; install -d -m 0750 "$BACKUP_DIR/project/$(dirname -- "$rel")"
    if [[ -e "$PROJECT/$rel" ]]; then cp -a "$PROJECT/$rel" "$BACKUP_DIR/project/$rel"; else : > "$BACKUP_DIR/project/${rel}.absent"; fi
}
backup_absolute_path() {
    local path="$1" key="${1#/}"; install -d -m 0750 "$BACKUP_DIR/system/$(dirname -- "$key")"
    if [[ -e "$path" ]]; then cp -a "$path" "$BACKUP_DIR/system/$key"; else : > "$BACKUP_DIR/system/${key}.absent"; fi
}

for rel in app/core/auth.py app/core/system_admin.py app/routers/api.py templates/system.html static/js/system.js; do backup_project_path "$rel"; done
for path in /usr/local/libexec/srv-control-system-agent /usr/local/libexec/srv-control-adguard-monitor /etc/systemd/system/srv-control-adguard-monitor.service /etc/systemd/system/srv-control-adguard-monitor.timer /var/lib/srv-control/login-guard.json; do backup_absolute_path "$path"; done

if [[ -f "$RELEASE_META" ]]; then cp -a "$RELEASE_META" "$BACKUP_DIR/release.json"; else : > "$BACKUP_DIR/.release-json-was-absent"; fi
systemctl show srv-control.service -p MainPID --value > "$BACKUP_DIR/main-pid.before"

install -m 0644 "$PAYLOAD/app/core/auth.py" "$PROJECT/app/core/auth.py"
install -m 0644 "$PAYLOAD/app/core/system_admin.py" "$PROJECT/app/core/system_admin.py"
install -m 0644 "$PAYLOAD/app/routers/api.py" "$PROJECT/app/routers/api.py"
install -m 0644 "$PAYLOAD/templates/system.html" "$PROJECT/templates/system.html"
install -m 0644 "$PAYLOAD/static/js/system.js" "$PROJECT/static/js/system.js"

bash "$SYSTEM_INSTALLER"

sync_time="$(date -Is)"
tmp="$(mktemp /var/lib/srv-control/release.json.tmp.XXXXXX)"
python3 - "$tmp" "$RELEASE_VERSION" "$RELEASE_ID" "$sync_time" "$REMOTE_SHA" <<'PY'
import json, pathlib, sys
path = pathlib.Path(sys.argv[1])
path.write_text(json.dumps({"version":sys.argv[2],"release_id":sys.argv[3],"synced_at":sys.argv[4],"git_sha":sys.argv[5]}, ensure_ascii=False, indent=2)+"\n", encoding="utf-8")
PY
chmod 0644 "$tmp"; mv -f "$tmp" "$RELEASE_META"
"$RELOAD_HELPER" srv-control.service http://127.0.0.1:8876/api/v1/health
log "APPLY PASS: release=${RELEASE_VERSION} sha=${REMOTE_SHA} synced_at=${sync_time}"
