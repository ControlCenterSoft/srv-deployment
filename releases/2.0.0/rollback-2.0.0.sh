#!/usr/bin/env bash
set -Eeuo pipefail
umask 027

PROJECT="${1:-/opt/srv-control}"
REMOTE_SHA="${2:-unknown}"
RELEASE_ID="2.0.0"
REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd -P)"
RELOAD_HELPER="${REPO_ROOT}/deploy/reload-srv-control.sh"
BACKUP_DIR="/var/lib/srv-deployment/backups/${REMOTE_SHA}-${RELEASE_ID}"

fail(){ printf 'ROLLBACK 2.0.0 FAIL: %s\n' "$*" >&2; exit 1; }
log(){ printf '%s %s\n' "$(date -Is)" "$*"; }

[[ "$(id -u)" -eq 0 ]] || fail "must run as root"
[[ -d "$BACKUP_DIR" ]] || fail "rollback snapshot missing: $BACKUP_DIR"

restore_project_path(){
    local rel="$1" src="$BACKUP_DIR/project/$1" absent="$BACKUP_DIR/project/${1}.absent"
    rm -rf -- "$PROJECT/$rel"
    if [[ -e "$src" || -L "$src" ]]; then
        install -d -m 0750 "$PROJECT/$(dirname -- "$rel")"
        cp -a -- "$src" "$PROJECT/$rel"
    elif [[ -f "$absent" ]]; then
        :
    else
        fail "rollback state missing for project path: $rel"
    fi
}

restore_absolute_path(){
    local path="$1" key="${1#/}" src="$BACKUP_DIR/system/${1#/}" absent="$BACKUP_DIR/system/${1#/}.absent"
    rm -rf -- "$path"
    if [[ -e "$src" || -L "$src" ]]; then
        install -d -m 0755 "$(dirname -- "$path")"
        cp -a -- "$src" "$path"
    elif [[ -f "$absent" ]]; then
        :
    else
        fail "rollback state missing for absolute path: $path"
    fi
}

# Do not stop srvcc-github-agent.service from inside its own deployment process.
# Quiesce only future schedules while files and units are restored.
systemctl disable --now srvcc-github-agent.timer >/dev/null 2>&1 || true
systemctl disable --now srv-control-minecraft-auto-update.timer >/dev/null 2>&1 || true
systemctl disable --now srv-control-release14-agent.path >/dev/null 2>&1 || true
systemctl disable --now srv-control-backup-retention.path >/dev/null 2>&1 || true

for rel in app migrations static templates alembic.ini requirements.lock; do
    restore_project_path "$rel"
done

critical_paths=(
    /usr/local/libexec/srv-control-system-agent
    /usr/local/libexec/srv-control-os-update
    /usr/local/libexec/srv-control-adguard-monitor
    /usr/local/libexec/srv-control-backup
    /usr/local/libexec/srv-control-backup-policy
    /usr/local/libexec/srv-control-os-auto-update
    /usr/local/libexec/srv-control-minecraft-repair
    /usr/local/libexec/srv-control-minecraft-legacy
    /usr/local/libexec/srv-control-release14-agent
    /usr/local/libexec/srv-control-pxe-probe
    /usr/local/sbin/srv-control-minecraft
    /usr/local/sbin/srv-control-minecraft-worlds
    /usr/local/sbin/srv-control-minecraft-players
    /usr/local/sbin/srv-control-minecraft-restore
    /usr/local/sbin/srv-control-minecraft-live
    /usr/local/sbin/srvcc-update-controller
    /usr/local/sbin/srvcc-github-agent
    /usr/local/sbin/srvcc-configure-auto-updates
    /etc/sudoers.d/srv-control-minecraft-legacy
    /etc/systemd/system/srv-control-system-agent.service
    /etc/systemd/system/srv-control-system-agent.path
    /etc/systemd/system/srv-control-release14-agent.service
    /etc/systemd/system/srv-control-release14-agent.path
    /etc/systemd/system/srv-control-backup-retention.service
    /etc/systemd/system/srv-control-backup-retention.path
    /etc/systemd/system/srv-control-os-update.service
    /etc/systemd/system/srv-control-backup.service
    /etc/systemd/system/srv-control-backup.timer
    /etc/systemd/system/srv-control-os-auto-update.service
    /etc/systemd/system/srv-control-os-auto-update.timer
    /etc/systemd/system/srvcc-github-agent.service
    /etc/systemd/system/srvcc-github-agent.timer
    /var/lib/srv-control/release.json
    /var/lib/srv-control/github-update-config.json
    /var/lib/srv-control/github-update-status.json
    /var/lib/srv-control/os-update-config.json
    /var/lib/srv-control/backup-config.json
    /var/lib/srvcc-agent/accepted-release-fingerprint
    /var/lib/srvcc-agent/blocked-release.json
    /var/lib/srvcc-agent/last-release-fingerprint
    /var/lib/srv-control/session.key
    /opt/minecraft-bedrock/server.properties
    /opt/minecraft/server.properties
    /srv/minecraft/server.properties
    /var/lib/minecraft/server.properties
)
for path in "${critical_paths[@]}"; do restore_absolute_path "$path"; done

systemctl daemon-reload
systemctl reset-failed srv-control.service srv-control-system-agent.service srvcc-github-agent.service >/dev/null 2>&1 || true
systemctl enable --now srv-control-system-agent.path >/dev/null 2>&1 || true

restore_timer_state(){
    local unit="$1" enabled_file="$BACKUP_DIR/state/${1}.enabled" active_file="$BACKUP_DIR/state/${1}.active"
    local enabled="" active=""
    [[ -f "$enabled_file" ]] && enabled="$(cat "$enabled_file" 2>/dev/null || true)"
    [[ -f "$active_file" ]] && active="$(cat "$active_file" 2>/dev/null || true)"
    if [[ "$enabled" == "enabled" || "$enabled" == "enabled-runtime" ]]; then
        systemctl enable "$unit" >/dev/null 2>&1 || true
    else
        systemctl disable "$unit" >/dev/null 2>&1 || true
    fi
    if [[ "$active" == "active" ]]; then
        systemctl start "$unit" >/dev/null 2>&1 || true
    else
        systemctl stop "$unit" >/dev/null 2>&1 || true
    fi
}

for unit in \
    srvcc-github-agent.timer \
    srv-control-backup.timer \
    srv-control-os-auto-update.timer \
    srv-control-release14-agent.path \
    srv-control-backup-retention.path \
    minecraft-update.timer \
    srv-control-minecraft-auto-update.timer
do
    restore_timer_state "$unit"
done

if [[ -x "$RELOAD_HELPER" ]]; then
    "$RELOAD_HELPER" srv-control.service http://127.0.0.1:8876/api/v1/health \
        || fail "previous Control Center failed to recover after rollback"
else
    systemctl restart srv-control.service
fi

log "ROLLBACK 2.0.0 PASS: previous application, updater state, policies, DHCP/PXE agents, Minecraft compatibility helpers and Minecraft selection restored"
