#!/usr/bin/env bash
set -u

PROJECT="${1:-/opt/srv-control}"
REMOTE_SHA="${2:-unknown}"
RELEASE_ID="0008-system-security-admin"
RELEASE_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_ROOT="$(cd -- "${RELEASE_DIR}/../.." && pwd -P)"
RELOAD_HELPER="${REPO_ROOT}/deploy/reload-srv-control.sh"
BACKUP_DIR="/var/lib/srv-deployment/backups/${REMOTE_SHA}-${RELEASE_ID}"
RELEASE_META="/var/lib/srv-control/release.json"
rc=0

log() {
    printf '%s %s\n' "$(date -Is)" "$*"
}

[[ -d "$BACKUP_DIR" ]] || {
    log "ROLLBACK FAIL: backup directory missing"
    exit 1
}

systemctl disable --now srv-control-system-agent.path >/dev/null 2>&1 || true

restore_project_path() {
    local rel="$1"
    if [[ -e "$BACKUP_DIR/project/$rel" ]]; then
        install -d -m 0750 "$PROJECT/$(dirname -- "$rel")"
        cp -a "$BACKUP_DIR/project/$rel" "$PROJECT/$rel" || rc=1
    elif [[ -f "$BACKUP_DIR/project/${rel}.absent" ]]; then
        rm -f "$PROJECT/$rel" || rc=1
    else
        log "ROLLBACK WARN: missing project backup metadata for $rel"
        rc=1
    fi
}

restore_absolute_path() {
    local path="$1"
    local key="${path#/}"
    if [[ -e "$BACKUP_DIR/system/$key" ]]; then
        install -d "$(dirname -- "$path")"
        cp -a "$BACKUP_DIR/system/$key" "$path" || rc=1
    elif [[ -f "$BACKUP_DIR/system/${key}.absent" ]]; then
        rm -f "$path" || rc=1
    else
        log "ROLLBACK WARN: missing system backup metadata for $path"
        rc=1
    fi
}

for rel in \
    app/core/auth.py \
    app/core/system_admin.py \
    app/routers/api.py \
    templates/system.html \
    static/js/system.js \
    static/css/system-admin.css
do
    restore_project_path "$rel"
done

for path in \
    /usr/local/libexec/srv-control-system-agent \
    /usr/local/libexec/srv-control-os-update \
    /etc/systemd/system/srv-control-system-agent.service \
    /etc/systemd/system/srv-control-system-agent.path \
    /etc/systemd/system/srv-control-os-update.service \
    /var/lib/srv-control/auth.json \
    /var/lib/srv-control/session.key \
    /var/lib/srv-control/admin-bootstrap.txt
do
    restore_absolute_path "$path"
done

if [[ -f "$BACKUP_DIR/release.json" ]]; then
    cp -a "$BACKUP_DIR/release.json" "$RELEASE_META" || rc=1
elif [[ -f "$BACKUP_DIR/.release-json-was-absent" ]]; then
    rm -f "$RELEASE_META" || rc=1
fi

systemctl daemon-reload || rc=1

if [[ -f /etc/systemd/system/srv-control-system-agent.path ]]; then
    systemctl enable --now srv-control-system-agent.path >/dev/null 2>&1 || true
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
