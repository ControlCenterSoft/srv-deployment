#!/usr/bin/env bash
set -u

PROJECT="${1:-/opt/srv-control}"
REMOTE_SHA="${2:-unknown}"
RELEASE_ID="1.1.0"
RELEASE_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_ROOT="$(cd -- "${RELEASE_DIR}/../.." && pwd -P)"
RELOAD_HELPER="${REPO_ROOT}/deploy/reload-srv-control.sh"
BACKUP_DIR="/var/lib/srv-deployment/backups/${REMOTE_SHA}-${RELEASE_ID}"
STATE_DIR="/var/lib/srv-control"

fail() {
    printf 'ROLLBACK FAIL: %s\n' "$*" >&2
    exit 1
}

[[ -d "$BACKUP_DIR" ]] || fail "deployment backup missing: $BACKUP_DIR"

for unit in \
    srvcc-github-agent.timer \
    srv-control-backup.timer \
    srv-control-os-auto-update.timer \
    srv-control-system-agent.path \
    srv-control-adguard-monitor.timer
do
    systemctl stop "$unit" >/dev/null 2>&1 || true
done

restore_project_path() {
    local rel="$1"
    if [[ -e "$BACKUP_DIR/project/${rel}.absent" ]]; then
        rm -rf "$PROJECT/$rel"
        return
    fi
    [[ -e "$BACKUP_DIR/project/$rel" ]] || fail "project backup missing: $rel"
    rm -rf "$PROJECT/$rel"
    install -d -m 0750 "$(dirname -- "$PROJECT/$rel")"
    cp -a "$BACKUP_DIR/project/$rel" "$PROJECT/$rel"
}

restore_absolute_path() {
    local path="$1"
    local key="${path#/}"
    if [[ -e "$BACKUP_DIR/system/${key}.absent" ]]; then
        rm -rf "$path"
        return
    fi
    [[ -e "$BACKUP_DIR/system/$key" || -L "$BACKUP_DIR/system/$key" ]] \
        || fail "system backup missing: $path"
    rm -rf "$path"
    install -d -m 0755 "$(dirname -- "$path")"
    cp -a "$BACKUP_DIR/system/$key" "$path"
}

for rel in app migrations static templates alembic.ini requirements.lock; do
    restore_project_path "$rel"
done

for path in \
    /usr/local/libexec/srv-control-system-agent \
    /usr/local/libexec/srv-control-os-update \
    /usr/local/libexec/srv-control-adguard-monitor \
    /usr/local/libexec/srv-control-backup \
    /usr/local/libexec/srv-control-os-auto-update \
    /usr/local/sbin/srvcc-github-agent \
    /usr/local/sbin/srvcc-configure-auto-updates \
    /etc/systemd/system/srv-control-system-agent.service \
    /etc/systemd/system/srv-control-system-agent.path \
    /etc/systemd/system/srv-control-os-update.service \
    /etc/systemd/system/srv-control-adguard-monitor.service \
    /etc/systemd/system/srv-control-adguard-monitor.timer \
    /etc/systemd/system/srv-control-backup.service \
    /etc/systemd/system/srv-control-backup.timer \
    /etc/systemd/system/srv-control-os-auto-update.service \
    /etc/systemd/system/srv-control-os-auto-update.timer \
    /etc/systemd/system/srvcc-github-agent.service \
    /etc/systemd/system/srvcc-github-agent.timer \
    /etc/pam.d/srv-control \
    /etc/nginx/sites-available/srv-control \
    /var/lib/srv-control/session.key \
    /var/lib/srv-control/auth.json \
    /var/lib/srv-control/admin-bootstrap.txt \
    /var/lib/srv-control/login-guard.json \
    /var/lib/srv-control/os-update-config.json \
    /var/lib/srv-control/backup-config.json \
    /var/lib/srv-control/github-update-config.json \
    /var/lib/srv-control/github-update-status.json \
    /var/lib/srv-control/http.keytab \
    /var/lib/srv-control/sso-realm \
    /var/lib/srvcc-agent/last-deployed-sha \
    /var/lib/srvcc-agent/last-seen-sha \
    /var/lib/srvcc-agent/last-release-fingerprint
do
    restore_absolute_path "$path"
done

if [[ -e "$BACKUP_DIR/state/release.json.absent" ]]; then
    rm -f "$STATE_DIR/release.json"
else
    [[ -s "$BACKUP_DIR/state/release.json" ]] || fail "release metadata backup missing"
    cp -a "$BACKUP_DIR/state/release.json" "$STATE_DIR/release.json"
fi

systemctl daemon-reload

restore_timer_state() {
    local unit="$1"
    local enabled=""
    local active=""
    enabled="$(cat "$BACKUP_DIR/state/${unit}.enabled" 2>/dev/null || true)"
    active="$(cat "$BACKUP_DIR/state/${unit}.active" 2>/dev/null || true)"

    if [[ "$enabled" == "enabled" ]]; then
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

restore_timer_state srvcc-github-agent.timer
restore_timer_state srv-control-backup.timer
restore_timer_state srv-control-os-auto-update.timer

if [[ -e /etc/systemd/system/srv-control-system-agent.path ]]; then
    systemctl enable --now srv-control-system-agent.path >/dev/null 2>&1 || true
fi
if [[ -e /etc/systemd/system/srv-control-adguard-monitor.timer ]]; then
    systemctl enable --now srv-control-adguard-monitor.timer >/dev/null 2>&1 || true
fi

if [[ -s /etc/nginx/sites-available/srv-control ]]; then
    nginx -t >/dev/null 2>&1 || fail "restored nginx configuration is invalid"
    systemctl reload nginx.service >/dev/null 2>&1 || true
fi

if [[ -x "$RELOAD_HELPER" ]] && systemctl is-active --quiet srv-control.service; then
    "$RELOAD_HELPER" srv-control.service http://127.0.0.1:8876/api/v1/health \
        || fail "restored Control Center failed healthcheck"
else
    systemctl restart srv-control.service \
        || fail "failed to restart restored Control Center"
fi

printf 'ROLLBACK PASS: release=%s sha=%s\n' "$RELEASE_ID" "$REMOTE_SHA"
