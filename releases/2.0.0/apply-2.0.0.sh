#!/usr/bin/env bash
set -Eeuo pipefail
umask 027

PROJECT="${1:-/opt/srv-control}"
REMOTE_SHA="${2:-unknown}"
RELEASE_ID="2.0.0"
RELEASE_VERSION="2.0.0"
RELEASE_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_ROOT="$(cd -- "${RELEASE_DIR}/../.." && pwd -P)"
PAYLOAD="${RELEASE_DIR}/payload"
SYSTEM="${RELEASE_DIR}/system"
RELOAD_HELPER="${REPO_ROOT}/deploy/reload-srv-control.sh"
BACKUP_DIR="/var/lib/srv-deployment/backups/${REMOTE_SHA}-${RELEASE_ID}"
STATE_DIR="/var/lib/srv-control"
RELEASE_META="${STATE_DIR}/release.json"
APP_USER="srv-control"
APP_GROUP="srv-control"

log(){ printf '%s %s\n' "$(date -Is)" "$*"; }
fail(){ printf 'APPLY 2.0.0 FAIL: %s\n' "$*" >&2; exit 1; }

install -d -m 0750 "$BACKUP_DIR/project" "$BACKUP_DIR/system" "$BACKUP_DIR/state"

backup_project_path(){
    local rel="$1"
    install -d -m 0750 "$BACKUP_DIR/project/$(dirname -- "$rel")"
    if [[ -e "$PROJECT/$rel" ]]; then
        cp -a -- "$PROJECT/$rel" "$BACKUP_DIR/project/$rel"
    else
        : > "$BACKUP_DIR/project/${rel}.absent"
    fi
}

backup_absolute_path(){
    local path="$1" key="${1#/}"
    install -d -m 0750 "$BACKUP_DIR/system/$(dirname -- "$key")"
    if [[ -e "$path" || -L "$path" ]]; then
        cp -a -- "$path" "$BACKUP_DIR/system/$key"
    else
        : > "$BACKUP_DIR/system/${key}.absent"
    fi
}

json_value(){
    python3 - "$1" "$2" "$3" <<'PY'
import json,pathlib,sys
path=pathlib.Path(sys.argv[1]); key=sys.argv[2]; default=sys.argv[3]
try: data=json.loads(path.read_text(encoding='utf-8'))
except Exception: data={}
value=data.get(key,default)
if isinstance(value,bool): print('true' if value else 'false')
elif isinstance(value,(str,int)): print(value)
else: print(default)
PY
}

for rel in app migrations static templates alembic.ini requirements.lock; do
    backup_project_path "$rel"
done

critical_paths=(
    /usr/local/libexec/srv-control-system-agent
    /usr/local/libexec/srv-control-os-update
    /usr/local/libexec/srv-control-adguard-monitor
    /usr/local/libexec/srv-control-backup
    /usr/local/libexec/srv-control-backup-policy
    /usr/local/libexec/srv-control-os-auto-update
    /usr/local/libexec/srv-control-minecraft-repair
    /usr/local/sbin/srvcc-update-controller
    /usr/local/sbin/srvcc-github-agent
    /usr/local/sbin/srvcc-configure-auto-updates
    /etc/systemd/system/srv-control-system-agent.service
    /etc/systemd/system/srv-control-system-agent.path
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
)
for path in "${critical_paths[@]}"; do backup_absolute_path "$path"; done

for unit in \
    srvcc-github-agent.timer \
    srv-control-backup.timer \
    srv-control-os-auto-update.timer \
    minecraft-update.timer \
    srv-control-minecraft-auto-update.timer
do
    systemctl is-enabled "$unit" > "$BACKUP_DIR/state/${unit}.enabled" 2>/dev/null || true
    systemctl is-active "$unit" > "$BACKUP_DIR/state/${unit}.active" 2>/dev/null || true
done
systemctl show srv-control.service -p MainPID --value > "$BACKUP_DIR/state/main-pid.before" 2>/dev/null || true

GH_SOURCE="$(json_value "$STATE_DIR/github-update-config.json" source 'https://github.com/filosoff31/srv-deployment.git')"
GH_MODE="$(json_value "$STATE_DIR/github-update-config.json" mode automatic)"
GH_INTERVAL="$(json_value "$STATE_DIR/github-update-config.json" interval_minutes 5)"

# 2.0 deliberately does NOT create an unconditional user-visible backup here.
# The update controller evaluates backup_before_update once before entering the
# deployment transaction. This removes the 1.x double/forced-backup defect while
# retaining this private rollback snapshot regardless of operator policy.
log "Internal rollback snapshot completed; user backup policy remains authoritative"

log "Installing Control Center 2.0.0 application payload"
for rel in app migrations static templates; do
    rm -rf -- "$PROJECT/$rel"
    cp -a -- "$PAYLOAD/$rel" "$PROJECT/$rel"
done
install -m 0640 "$PAYLOAD/alembic.ini" "$PROJECT/alembic.ini"
install -m 0640 "$PAYLOAD/requirements.lock" "$PROJECT/requirements.lock"
chown -R root:"$APP_GROUP" \
    "$PROJECT/app" "$PROJECT/migrations" "$PROJECT/static" "$PROJECT/templates" \
    "$PROJECT/alembic.ini" "$PROJECT/requirements.lock"
find "$PROJECT/app" "$PROJECT/migrations" "$PROJECT/static" "$PROJECT/templates" -type d -exec chmod 0750 {} +
find "$PROJECT/app" "$PROJECT/migrations" "$PROJECT/static" "$PROJECT/templates" -type f -exec chmod 0640 {} +

install -d -m 0755 /usr/local/libexec /usr/local/sbin
helpers=(
    srv-control-system-agent srv-control-os-update srv-control-adguard-monitor srv-control-backup srv-control-backup-policy srv-control-os-auto-update
    srv-control-samba-admin srv-control-samba-agent srv-control-samba-ldif-editor srv-control-samba-monitor srv-control-samba-shares-monitor
    srv-control-minecraft-admin srv-control-minecraft-admin-core srv-control-minecraft-agent srv-control-minecraft-auto-update
    srv-control-minecraft-firewall srv-control-minecraft-monitor srv-control-minecraft-player-admin srv-control-minecraft-runner srv-control-minecraft-update
    srv-control-minecraft-repair
)
for helper in "${helpers[@]}"; do
    [[ -s "$SYSTEM/$helper" ]] || fail "managed helper missing: $helper"
    install -m 0755 -o root -g root "$SYSTEM/$helper" "/usr/local/libexec/$helper"
done
install -m 0755 -o root -g root "$SYSTEM/srvcc-update-controller" /usr/local/sbin/srvcc-update-controller

units=(
    srv-control-system-agent.service srv-control-system-agent.path
    srv-control-os-update.service srv-control-adguard-monitor.service srv-control-adguard-monitor.timer
    srv-control-backup.service srv-control-backup.timer srv-control-os-auto-update.service srv-control-os-auto-update.timer
    srv-control-samba-agent.service srv-control-samba-agent.path srv-control-samba-monitor.service srv-control-samba-monitor.timer
    srv-control-samba-shares-monitor.service srv-control-samba-shares-monitor.timer
    srv-control-minecraft-agent.service srv-control-minecraft-agent.path
    srv-control-minecraft-auto-update.service srv-control-minecraft-auto-update.timer
    srv-control-minecraft-firewall.service srv-control-minecraft-monitor.service srv-control-minecraft-monitor.timer
)
for unit in "${units[@]}"; do
    [[ -f "$SYSTEM/$unit" ]] || fail "managed unit missing: $unit"
    install -m 0644 -o root -g root "$SYSTEM/$unit" "/etc/systemd/system/$unit"
done

install -d -m 0750 -o "$APP_USER" -g "$APP_GROUP" \
    "$STATE_DIR" "$STATE_DIR/system-actions" "$STATE_DIR/system-results" \
    "$STATE_DIR/samba-actions" "$STATE_DIR/minecraft-actions"
install -d -m 0700 -o "$APP_USER" -g "$APP_GROUP" "$STATE_DIR/action-secrets" "$STATE_DIR/domain-imports"
install -d -m 0750 -o root -g "$APP_GROUP" "$STATE_DIR/backups" "$STATE_DIR/domain-backups" "$STATE_DIR/minecraft-backups"
install -d -m 0750 -o root -g root /var/lib/srvcc-agent /var/lib/srv-deployment

log "Applying database migrations"
runuser -u "$APP_USER" -- env PYTHONPATH="$PROJECT" PYTHONDONTWRITEBYTECODE=1 \
    "$PROJECT/venv/bin/alembic" -c "$PROJECT/alembic.ini" upgrade head

systemctl daemon-reload
systemctl enable --now srv-control-system-agent.path
systemctl enable --now srv-control-adguard-monitor.timer
systemctl enable --now srv-control-samba-agent.path
systemctl enable --now srv-control-samba-monitor.timer
systemctl enable --now srv-control-samba-shares-monitor.timer
systemctl enable --now srv-control-minecraft-agent.path
systemctl enable --now srv-control-minecraft-monitor.timer
systemctl enable --now srv-control-minecraft-firewall.service >/dev/null 2>&1 || true

# The real 1.3.x production line proved the legacy single-server updater is the
# authoritative path. Keep the conflicting multi-instance update timer off.
systemctl disable --now srv-control-minecraft-auto-update.timer >/dev/null 2>&1 || true
if systemctl cat minecraft-update.timer >/dev/null 2>&1; then
    systemctl enable --now minecraft-update.timer >/dev/null 2>&1 || true
fi

# Rebuild the updater from clean 2.0 sources and restore the operator-selected
# schedule. A failed legacy unit/timer is explicitly repaired here.
bash "$SYSTEM/srvcc-configure-auto-updates" \
    --repo "$GH_SOURCE" --mode "$GH_MODE" --interval-minutes "$GH_INTERVAL" --no-check-now

if /usr/local/libexec/srv-control-backup-policy scheduled; then
    systemctl enable --now srv-control-backup.timer >/dev/null
else
    systemctl disable --now srv-control-backup.timer >/dev/null 2>&1 || true
fi

OS_MODE="$(json_value "$STATE_DIR/os-update-config.json" mode manual)"
if [[ "$OS_MODE" == "automatic" ]]; then
    systemctl enable --now srv-control-os-auto-update.timer >/dev/null
else
    systemctl disable --now srv-control-os-auto-update.timer >/dev/null 2>&1 || true
fi

# Health-first Minecraft repair. A healthy server is not touched. If ordinary
# update/restart repair fails, the operator-authorized recovery path creates a
# safety backup and switches to a new recovery world. The old world remains in
# the Minecraft backup set.
if [[ -x /usr/local/sbin/srv-control-minecraft && -x /usr/local/sbin/srv-control-minecraft-worlds ]]; then
    /usr/local/libexec/srv-control-minecraft-repair repair --replace-world-on-failure \
        > "$BACKUP_DIR/state/minecraft-repair.json" \
        || fail "Minecraft Bedrock repair did not reach healthy state"
else
    fail "proven Minecraft legacy helpers are missing; refusing an unverified destructive reinstall"
fi

sync_time="$(date -Is)"
python3 - "$RELEASE_META" "$RELEASE_VERSION" "$RELEASE_ID" "$sync_time" "$REMOTE_SHA" <<'PY'
import grp,json,os,pathlib,sys,tempfile
path=pathlib.Path(sys.argv[1]); path.parent.mkdir(parents=True,exist_ok=True)
payload={'version':sys.argv[2],'release_id':sys.argv[3],'synced_at':sys.argv[4],'git_sha':sys.argv[5]}
gid=grp.getgrnam('srv-control').gr_gid
fd,tmp=tempfile.mkstemp(prefix='.release-2.0.0.',dir=str(path.parent))
try:
    os.fchown(fd,0,gid); os.fchmod(fd,0o640)
    with os.fdopen(fd,'w',encoding='utf-8') as h:
        json.dump(payload,h,ensure_ascii=False,indent=2); h.write('\n'); h.flush(); os.fsync(h.fileno())
    os.replace(tmp,path)
finally:
    try: os.unlink(tmp)
    except FileNotFoundError: pass
PY

log "Gracefully rotating Control Center workers"
"$RELOAD_HELPER" srv-control.service http://127.0.0.1:8876/api/v1/health

# Reassert automatic update scheduling after the service rotation. This is a
# direct regression guard for the 1.x failure mode where an unsuccessful update
# left the timer disabled.
if [[ "$GH_MODE" == "automatic" ]]; then
    systemctl enable --now srvcc-github-agent.timer >/dev/null
    systemctl is-enabled --quiet srvcc-github-agent.timer || fail "GitHub update timer is not enabled"
    systemctl is-active --quiet srvcc-github-agent.timer || fail "GitHub update timer is not active"
fi

log "APPLY 2.0.0 PASS: payload installed; updater rebuilt; backup policy preserved; Minecraft healthy"
