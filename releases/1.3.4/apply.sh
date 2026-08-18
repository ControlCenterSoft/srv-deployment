#!/usr/bin/env bash
set -Eeuo pipefail
umask 027

PROJECT="${1:-/opt/srv-control}"
REMOTE_SHA="${2:-unknown}"
RELEASE_ID="1.3.0"
RELEASE_VERSION="1.3.0"
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

log() { printf '%s %s\n' "$(date -Is)" "$*"; }

install -d -m 0750 "$BACKUP_DIR/project" "$BACKUP_DIR/system" "$BACKUP_DIR/state"

backup_project_path() {
    local rel="$1"
    install -d -m 0750 "$BACKUP_DIR/project/$(dirname -- "$rel")"
    if [[ -e "$PROJECT/$rel" ]]; then cp -a "$PROJECT/$rel" "$BACKUP_DIR/project/$rel"; else : > "$BACKUP_DIR/project/${rel}.absent"; fi
}

backup_absolute_path() {
    local path="$1" key="${1#/}"
    install -d -m 0750 "$BACKUP_DIR/system/$(dirname -- "$key")"
    if [[ -e "$path" || -L "$path" ]]; then cp -a "$path" "$BACKUP_DIR/system/$key"; else : > "$BACKUP_DIR/system/${key}.absent"; fi
}

config_value() {
    python3 - "$STATE_DIR/github-update-config.json" "$1" <<'PY'
import json,pathlib,sys
try: data=json.loads(pathlib.Path(sys.argv[1]).read_text(encoding='utf-8'))
except Exception: data={}
value=data.get(sys.argv[2])
if isinstance(value,(str,int)): print(value)
PY
}

for rel in app migrations static templates alembic.ini requirements.lock; do backup_project_path "$rel"; done

old_paths=(
    /usr/local/libexec/srv-control-system-agent
    /usr/local/libexec/srv-control-os-update
    /usr/local/libexec/srv-control-adguard-monitor
    /usr/local/libexec/srv-control-backup
    /usr/local/libexec/srv-control-os-auto-update
    /usr/local/sbin/srvcc-github-agent
    /usr/local/sbin/srvcc-configure-auto-updates
    /etc/systemd/system/srv-control-system-agent.service
    /etc/systemd/system/srv-control-system-agent.path
    /etc/systemd/system/srv-control-os-update.service
    /etc/systemd/system/srv-control-adguard-monitor.service
    /etc/systemd/system/srv-control-adguard-monitor.timer
    /etc/systemd/system/srv-control-backup.service
    /etc/systemd/system/srv-control-backup.timer
    /etc/systemd/system/srv-control-os-auto-update.service
    /etc/systemd/system/srv-control-os-auto-update.timer
    /etc/systemd/system/srvcc-github-agent.service
    /etc/systemd/system/srvcc-github-agent.timer
    /etc/pam.d/srv-control
    /etc/nginx/sites-available/srv-control
    /var/lib/srv-control/session.key
    /var/lib/srv-control/login-guard.json
    /var/lib/srv-control/os-update-config.json
    /var/lib/srv-control/backup-config.json
    /var/lib/srv-control/github-update-config.json
    /var/lib/srv-control/github-update-status.json
    /var/lib/srv-control/http.keytab
    /var/lib/srv-control/sso-realm
    /var/lib/srvcc-agent/last-deployed-sha
    /var/lib/srvcc-agent/last-seen-sha
    /var/lib/srvcc-agent/last-release-fingerprint
)
for path in "${old_paths[@]}"; do backup_absolute_path "$path"; done

if [[ -f "$RELEASE_META" ]]; then cp -a "$RELEASE_META" "$BACKUP_DIR/state/release.json"; else : > "$BACKUP_DIR/state/release.json.absent"; fi
systemctl show srv-control.service -p MainPID --value > "$BACKUP_DIR/state/main-pid.before"
for unit in srvcc-github-agent.timer srv-control-backup.timer srv-control-os-auto-update.timer; do
    systemctl is-enabled "$unit" > "$BACKUP_DIR/state/${unit}.enabled" 2>/dev/null || true
    systemctl is-active "$unit" > "$BACKUP_DIR/state/${unit}.active" 2>/dev/null || true
done

GH_SOURCE="$(config_value source)"; GH_SOURCE="${GH_SOURCE:-https://github.com/filosoff31/srv-deployment.git}"
GH_MODE="$(config_value mode)"; GH_MODE="${GH_MODE:-automatic}"
GH_INTERVAL="$(config_value interval_minutes)"; GH_INTERVAL="${GH_INTERVAL:-5}"

log "Creating visible pre-release backup"
"$SYSTEM/srv-control-backup" create --actor system --reason pre-release-1.3.0 > "$BACKUP_DIR/state/pre-release-backup.json"

log "Installing SRV Control Center 1.3.0 application payload"
for rel in app migrations static templates; do rm -rf "$PROJECT/$rel"; cp -a "$PAYLOAD/$rel" "$PROJECT/$rel"; done
install -m 0640 "$PAYLOAD/alembic.ini" "$PROJECT/alembic.ini"
install -m 0640 "$PAYLOAD/requirements.lock" "$PROJECT/requirements.lock"
chown -R root:"$APP_GROUP" "$PROJECT/app" "$PROJECT/migrations" "$PROJECT/static" "$PROJECT/templates" "$PROJECT/alembic.ini" "$PROJECT/requirements.lock"
find "$PROJECT/app" "$PROJECT/migrations" "$PROJECT/static" "$PROJECT/templates" -type d -exec chmod 0750 {} +
find "$PROJECT/app" "$PROJECT/migrations" "$PROJECT/static" "$PROJECT/templates" -type f -exec chmod 0640 {} +

install -d -m 0755 /usr/local/libexec
helpers=(
    srv-control-system-agent srv-control-os-update srv-control-adguard-monitor srv-control-backup srv-control-os-auto-update
    srv-control-samba-admin srv-control-samba-agent srv-control-samba-ldif-editor srv-control-samba-monitor srv-control-samba-shares-monitor
    srv-control-minecraft-admin srv-control-minecraft-admin-core srv-control-minecraft-agent srv-control-minecraft-auto-update
    srv-control-minecraft-firewall srv-control-minecraft-monitor srv-control-minecraft-player-admin srv-control-minecraft-runner srv-control-minecraft-update
)
for helper in "${helpers[@]}"; do install -m 0755 -o root -g root "$SYSTEM/$helper" "/usr/local/libexec/$helper"; done

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
for unit in "${units[@]}"; do install -m 0644 -o root -g root "$SYSTEM/$unit" "/etc/systemd/system/$unit"; done

install -d -m 0750 -o "$APP_USER" -g "$APP_GROUP" "$STATE_DIR" "$STATE_DIR/system-actions" "$STATE_DIR/system-results" "$STATE_DIR/samba-actions" "$STATE_DIR/minecraft-actions"
install -d -m 0700 -o "$APP_USER" -g "$APP_GROUP" "$STATE_DIR/action-secrets" "$STATE_DIR/domain-imports"
install -d -m 0750 -o root -g "$APP_GROUP" "$STATE_DIR/backups" "$STATE_DIR/domain-backups" "$STATE_DIR/minecraft-backups"
install -d -m 0750 -o root -g "$APP_GROUP" /srv/shares /srv/minecraft /srv/minecraft/instances

log "Applying 1.3.0 database migration"
runuser -u "$APP_USER" -- env PYTHONPATH="$PROJECT" PYTHONDONTWRITEBYTECODE=1 "$PROJECT/venv/bin/alembic" -c "$PROJECT/alembic.ini" upgrade head

systemctl daemon-reload
systemctl enable --now srv-control-system-agent.path
systemctl enable --now srv-control-adguard-monitor.timer
systemctl enable --now srv-control-samba-agent.path
systemctl enable --now srv-control-samba-monitor.timer
systemctl enable --now srv-control-samba-shares-monitor.timer
systemctl enable --now srv-control-minecraft-agent.path
systemctl enable --now srv-control-minecraft-monitor.timer
systemctl enable --now srv-control-minecraft-auto-update.timer
systemctl enable --now srv-control-minecraft-firewall.service || true
systemctl start srv-control-adguard-monitor.service || true
systemctl start srv-control-samba-monitor.service || true
systemctl start srv-control-samba-shares-monitor.service || true
systemctl start srv-control-minecraft-monitor.service || true

sync_time="$(date -Is)"
python3 - "$RELEASE_META" "$RELEASE_VERSION" "$RELEASE_ID" "$sync_time" "$REMOTE_SHA" <<'PY'
import json,pathlib,sys
path=pathlib.Path(sys.argv[1]); payload={'version':sys.argv[2],'release_id':sys.argv[3],'synced_at':sys.argv[4],'git_sha':sys.argv[5]}
path.write_text(json.dumps(payload,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
PY
chmod 0644 "$RELEASE_META"

log "Reinstalling GitHub updater with preserved schedule"
bash "$SYSTEM/srvcc-configure-auto-updates" --repo "$GH_SOURCE" --mode "$GH_MODE" --interval-minutes "$GH_INTERVAL" --no-check-now

if python3 - "$STATE_DIR/backup-config.json" <<'PY'
import json,pathlib,sys
try: data=json.loads(pathlib.Path(sys.argv[1]).read_text(encoding='utf-8'))
except Exception: data={}
raise SystemExit(0 if data.get('scheduled') else 1)
PY
then systemctl enable --now srv-control-backup.timer; else systemctl disable --now srv-control-backup.timer >/dev/null 2>&1 || true; fi

if python3 - "$STATE_DIR/os-update-config.json" <<'PY'
import json,pathlib,sys
try: data=json.loads(pathlib.Path(sys.argv[1]).read_text(encoding='utf-8'))
except Exception: data={}
raise SystemExit(0 if data.get('mode') == 'automatic' else 1)
PY
then systemctl enable --now srv-control-os-auto-update.timer; else systemctl disable --now srv-control-os-auto-update.timer >/dev/null 2>&1 || true; fi

log "Gracefully rotating Control Center workers"
"$RELOAD_HELPER" srv-control.service http://127.0.0.1:8876/api/v1/health
log "APPLY PASS: release=${RELEASE_VERSION} sha=${REMOTE_SHA} synced_at=${sync_time}"
