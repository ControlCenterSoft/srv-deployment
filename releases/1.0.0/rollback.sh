#!/usr/bin/env bash
set -u

PROJECT="${1:-/opt/srv-control}"
REMOTE_SHA="${2:-unknown}"
RELEASE_ID="1.0.0"
BACKUP_DIR="/var/lib/srv-deployment/backups/${REMOTE_SHA}-${RELEASE_ID}"
RELEASE_META="/var/lib/srv-control/release.json"
rc=0

log() {
    printf '%s %s\n' "$(date -Is)" "$*"
}

[[ -d "$BACKUP_DIR" ]] || {
    log "ROLLBACK FAIL: backup directory missing: $BACKUP_DIR"
    exit 1
}

restore_project_path() {
    local rel="$1"
    rm -rf "$PROJECT/$rel"
    if [[ -e "$BACKUP_DIR/project/$rel" ]]; then
        install -d -m 0750 "$(dirname -- "$PROJECT/$rel")"
        cp -a "$BACKUP_DIR/project/$rel" "$PROJECT/$rel" || rc=1
    elif [[ -e "$BACKUP_DIR/project/${rel}.absent" ]]; then
        :
    else
        log "ROLLBACK WARN: backup metadata missing for project/$rel"
        rc=1
    fi
}

restore_absolute_path() {
    local path="$1"
    local key="${path#/}"
    rm -rf "$path"
    if [[ -e "$BACKUP_DIR/system/$key" ]]; then
        install -d -m 0755 "$(dirname -- "$path")"
        cp -a "$BACKUP_DIR/system/$key" "$path" || rc=1
    elif [[ -e "$BACKUP_DIR/system/${key}.absent" ]]; then
        :
    else
        log "ROLLBACK WARN: backup metadata missing for $path"
        rc=1
    fi
}

restore_updater_state() {
    local path="$1"
    local key="${path#/}"
    rm -f "$path"
    if [[ -e "$BACKUP_DIR/updater/$key" ]]; then
        install -d -m 0750 "$(dirname -- "$path")"
        cp -a "$BACKUP_DIR/updater/$key" "$path" || rc=1
    elif [[ -e "$BACKUP_DIR/updater/${key}.absent" ]]; then
        :
    else
        log "ROLLBACK WARN: updater backup metadata missing for $path"
        rc=1
    fi
}

for rel in app migrations static templates alembic.ini requirements.lock; do
    restore_project_path "$rel"
done

for path in \
    /usr/local/libexec/srv-control-system-agent \
    /usr/local/libexec/srv-control-os-update \
    /usr/local/libexec/srv-control-adguard-monitor \
    /etc/systemd/system/srv-control-system-agent.service \
    /etc/systemd/system/srv-control-system-agent.path \
    /etc/systemd/system/srv-control-os-update.service \
    /etc/systemd/system/srv-control-adguard-monitor.service \
    /etc/systemd/system/srv-control-adguard-monitor.timer \
    /usr/local/sbin/srvcc-github-agent \
    /usr/local/sbin/srvcc-configure-auto-updates \
    /etc/systemd/system/srvcc-github-agent.service \
    /etc/systemd/system/srvcc-github-agent.timer
do
    restore_absolute_path "$path"
done

for path in \
    /var/lib/srvcc-agent/last-deployed-sha \
    /var/lib/srvcc-agent/last-seen-sha \
    /var/lib/srvcc-agent/last-release-fingerprint \
    /var/lib/srv-control/github-update-config.json \
    /var/lib/srv-control/github-update-status.json
do
    restore_updater_state "$path"
done

if [[ -f "$BACKUP_DIR/release.json" ]]; then
    cp -a "$BACKUP_DIR/release.json" "$RELEASE_META" || rc=1
elif [[ -f "$BACKUP_DIR/.release-json-was-absent" ]]; then
    rm -f "$RELEASE_META" || rc=1
fi

systemctl daemon-reload || rc=1
systemctl enable --now srv-control-system-agent.path >/dev/null 2>&1 || true
systemctl enable --now srv-control-adguard-monitor.timer >/dev/null 2>&1 || true

timer_enabled="$(cat "$BACKUP_DIR/updater-timer-enabled.before" 2>/dev/null || true)"
timer_active="$(cat "$BACKUP_DIR/updater-timer-active.before" 2>/dev/null || true)"

if [[ "$timer_enabled" == "enabled" ]]; then
    systemctl enable srvcc-github-agent.timer >/dev/null 2>&1 || rc=1
else
    systemctl disable srvcc-github-agent.timer >/dev/null 2>&1 || true
fi

if [[ "$timer_active" == "active" ]]; then
    systemctl restart srvcc-github-agent.timer >/dev/null 2>&1 || rc=1
else
    systemctl stop srvcc-github-agent.timer >/dev/null 2>&1 || true
fi

if [[ -x /usr/local/sbin/srvcc-github-agent ]]; then
    chmod 0755 /usr/local/sbin/srvcc-github-agent || true
fi

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)"
if [[ -x "$REPO_ROOT/deploy/reload-srv-control.sh" ]]; then
    "$REPO_ROOT/deploy/reload-srv-control.sh" \
        srv-control.service \
        http://127.0.0.1:8876/api/v1/health || rc=1
else
    systemctl restart srv-control.service || rc=1
fi

if (( rc == 0 )); then
    log "ROLLBACK PASS: release=$RELEASE_ID sha=$REMOTE_SHA"
else
    log "ROLLBACK FAIL: restore completed with errors"
fi

exit "$rc"
