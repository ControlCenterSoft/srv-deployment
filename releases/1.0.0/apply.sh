#!/usr/bin/env bash
set -Eeuo pipefail
umask 027

PROJECT="${1:-/opt/srv-control}"
REMOTE_SHA="${2:-unknown}"
RELEASE_ID="1.0.0"
RELEASE_VERSION="1.0.0"
RELEASE_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_ROOT="$(cd -- "${RELEASE_DIR}/../.." && pwd -P)"
PAYLOAD="${RELEASE_DIR}/payload"
SYSTEM="${RELEASE_DIR}/system"
RELOAD_HELPER="${REPO_ROOT}/deploy/reload-srv-control.sh"
UPDATER_CONFIG="${REPO_ROOT}/bootstrap/configure-auto-updates.sh"
BACKUP_DIR="/var/lib/srv-deployment/backups/${REMOTE_SHA}-${RELEASE_ID}"
RELEASE_META="/var/lib/srv-control/release.json"
STATE_DIR="/var/lib/srv-control"
APP_USER="srv-control"
APP_GROUP="srv-control"

log() {
    printf '%s %s\n' "$(date -Is)" "$*"
}

install -d -m 0750 "$BACKUP_DIR/project" "$BACKUP_DIR/system" "$BACKUP_DIR/updater"

backup_project_path() {
    local rel="$1"
    install -d -m 0750 "$BACKUP_DIR/project/$(dirname -- "$rel")"
    if [[ -e "$PROJECT/$rel" ]]; then
        cp -a "$PROJECT/$rel" "$BACKUP_DIR/project/$rel"
    else
        : > "$BACKUP_DIR/project/${rel}.absent"
    fi
}

backup_absolute_path() {
    local path="$1"
    local key="${path#/}"
    install -d -m 0750 "$BACKUP_DIR/system/$(dirname -- "$key")"
    if [[ -e "$path" ]]; then
        cp -a "$path" "$BACKUP_DIR/system/$key"
    else
        : > "$BACKUP_DIR/system/${key}.absent"
    fi
}

for rel in \
    app \
    migrations \
    static \
    templates \
    alembic.ini \
    requirements.lock
do
    backup_project_path "$rel"
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
    backup_absolute_path "$path"
done

for path in \
    /var/lib/srvcc-agent/last-deployed-sha \
    /var/lib/srvcc-agent/last-seen-sha \
    /var/lib/srvcc-agent/last-release-fingerprint \
    /var/lib/srv-control/github-update-config.json \
    /var/lib/srv-control/github-update-status.json
do
    key="${path#/}"
    install -d -m 0750 "$BACKUP_DIR/updater/$(dirname -- "$key")"
    if [[ -e "$path" ]]; then
        cp -a "$path" "$BACKUP_DIR/updater/$key"
    else
        : > "$BACKUP_DIR/updater/${key}.absent"
    fi
done

if [[ -f "$RELEASE_META" ]]; then
    cp -a "$RELEASE_META" "$BACKUP_DIR/release.json"
else
    : > "$BACKUP_DIR/.release-json-was-absent"
fi

systemctl show srv-control.service -p MainPID --value > "$BACKUP_DIR/main-pid.before"
systemctl is-enabled srvcc-github-agent.timer > "$BACKUP_DIR/updater-timer-enabled.before" 2>/dev/null || true
systemctl is-active srvcc-github-agent.timer > "$BACKUP_DIR/updater-timer-active.before" 2>/dev/null || true

log "Installing consolidated application payload"

for rel in app migrations static templates; do
    rm -rf "$PROJECT/$rel"
    cp -a "$PAYLOAD/$rel" "$PROJECT/$rel"
done

install -m 0640 "$PAYLOAD/alembic.ini" "$PROJECT/alembic.ini"
install -m 0640 "$PAYLOAD/requirements.lock" "$PROJECT/requirements.lock"

chown -R root:"$APP_GROUP" \
    "$PROJECT/app" \
    "$PROJECT/migrations" \
    "$PROJECT/static" \
    "$PROJECT/templates" \
    "$PROJECT/alembic.ini" \
    "$PROJECT/requirements.lock"

find "$PROJECT/app" "$PROJECT/migrations" "$PROJECT/static" "$PROJECT/templates" \
    -type d -exec chmod 0750 {} +
find "$PROJECT/app" "$PROJECT/migrations" "$PROJECT/static" "$PROJECT/templates" \
    -type f -exec chmod 0640 {} +

log "Installing consolidated privileged helpers"
install -d -m 0755 /usr/local/libexec

install -m 0755 -o root -g root \
    "$SYSTEM/srv-control-system-agent" \
    /usr/local/libexec/srv-control-system-agent
install -m 0755 -o root -g root \
    "$SYSTEM/srv-control-os-update" \
    /usr/local/libexec/srv-control-os-update
install -m 0755 -o root -g root \
    "$SYSTEM/srv-control-adguard-monitor" \
    /usr/local/libexec/srv-control-adguard-monitor

for unit in \
    srv-control-system-agent.service \
    srv-control-system-agent.path \
    srv-control-os-update.service \
    srv-control-adguard-monitor.service \
    srv-control-adguard-monitor.timer
do
    install -m 0644 -o root -g root "$SYSTEM/$unit" "/etc/systemd/system/$unit"
done

install -d -m 0750 -o "$APP_USER" -g "$APP_GROUP" \
    "$STATE_DIR" \
    "$STATE_DIR/system-actions" \
    "$STATE_DIR/system-results"

systemctl daemon-reload
systemctl enable --now srv-control-system-agent.path
systemctl enable --now srv-control-adguard-monitor.timer
systemctl start srv-control-adguard-monitor.service || true

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

bash "$UPDATER_CONFIG" \
    --repo "https://github.com/filosoff31/srv-deployment.git" \
    --mode automatic \
    --interval-minutes 5 \
    --no-check-now

"$RELOAD_HELPER" srv-control.service http://127.0.0.1:8876/api/v1/health

log "APPLY PASS: release=${RELEASE_VERSION} sha=${REMOTE_SHA} synced_at=${sync_time}"
