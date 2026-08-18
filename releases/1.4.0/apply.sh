#!/usr/bin/env bash
set -Eeuo pipefail
umask 027
PROJECT="${1:-/opt/srv-control}"; REMOTE_SHA="${2:-unknown}"; RELEASE_ID="1.4.0"; RELEASE_VERSION="1.4.0"
RELEASE_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"; REPO_ROOT="$(cd -- "$RELEASE_DIR/../.." && pwd -P)"
BACKUP_DIR="/var/lib/srv-deployment/backups/${REMOTE_SHA}-${RELEASE_ID}"; STATE_DIR=/var/lib/srv-control; META="$STATE_DIR/release.json"; APP_USER=srv-control; APP_GROUP=srv-control
log(){ printf '%s %s\n' "$(date -Is)" "$*"; }
install -d -m 0750 "$BACKUP_DIR/project" "$BACKUP_DIR/system" "$BACKUP_DIR/state"
backup_project(){ local r="$1"; install -d -m 0750 "$BACKUP_DIR/project/$(dirname "$r")"; if [[ -e "$PROJECT/$r" ]]; then cp -a "$PROJECT/$r" "$BACKUP_DIR/project/$r"; else : > "$BACKUP_DIR/project/${r}.absent"; fi; }
backup_abs(){ local p="$1" k="${1#/}"; install -d -m 0750 "$BACKUP_DIR/system/$(dirname "$k")"; if [[ -e "$p" || -L "$p" ]]; then cp -a "$p" "$BACKUP_DIR/system/$k"; else : > "$BACKUP_DIR/system/${k}.absent"; fi; }
changed=(app/main.py app/core/release14.py app/routers/release14.py migrations/versions/14f0a1400001_dhcp_pxe_network_redirects.py templates/shell-1.4.html templates/services-1.4.html templates/dhcp-1.4.html templates/pxe-1.4.html templates/network-1.4.html templates/shares-1.4.html templates/system-1.4.html static/js/services-1.4.js static/js/dhcp-1.4.js static/js/pxe-1.4.js static/js/network-1.4.js static/js/shares-1.4.js static/js/system-1.4.js static/css/release-1.4.css)
for p in "${changed[@]}"; do backup_project "$p"; done
system_paths=(/usr/local/libexec/srv-control-backup /usr/local/libexec/srv-control-release14-agent /usr/local/libexec/srv-control-pxe-probe /etc/systemd/system/srv-control-release14-agent.service /etc/systemd/system/srv-control-release14-agent.path /etc/systemd/system/srv-control-backup-retention.service /etc/systemd/system/srv-control-backup-retention.path)
for p in "${system_paths[@]}"; do backup_abs "$p"; done
if [[ -f "$META" ]]; then cp -a "$META" "$BACKUP_DIR/state/release.json"; else : > "$BACKUP_DIR/state/release.json.absent"; fi

# Deliberately create the mandatory pre-release snapshot with the currently
# installed 1.3 worker before replacing that worker with the 1.4 PXE-aware one.
log "Creating pre-release 1.4.0 backup with current worker"
/usr/local/libexec/srv-control-backup create --actor system --reason pre-release-1.4.0 > "$BACKUP_DIR/state/pre-release-backup.json"

log "Installing incremental 1.4.0 application files"
for p in "${changed[@]}"; do
    case "$p" in
        app/core/release14.py)
            tmp="$(mktemp)"
            cat "$RELEASE_DIR"/payload/app/core/release14.parts/{00,01,02,03,04,05,06,07}.part > "$tmp"
            install -D -m 0640 -o root -g "$APP_GROUP" "$tmp" "$PROJECT/$p"
            rm -f "$tmp" ;;
        app/routers/release14.py)
            tmp="$(mktemp)"
            cat "$RELEASE_DIR"/payload/app/routers/release14.parts/{00,01,02,03}.part > "$tmp"
            install -D -m 0640 -o root -g "$APP_GROUP" "$tmp" "$PROJECT/$p"
            rm -f "$tmp" ;;
        *) install -D -m 0640 -o root -g "$APP_GROUP" "$RELEASE_DIR/payload/$p" "$PROJECT/$p" ;;
    esac
done

tmp_agent="$(mktemp)"
cat "$RELEASE_DIR"/system/srv-control-release14-agent.parts/{00,01,02,03,04,05,06,07,08,09,10,11,11a,12}.part > "$tmp_agent"
python3 -m py_compile "$tmp_agent" "$RELEASE_DIR/system/srv-control-pxe-probe" "$RELEASE_DIR/system/srv-control-backup"
install -m 0755 -o root -g root "$tmp_agent" /usr/local/libexec/srv-control-release14-agent
install -m 0755 -o root -g root "$RELEASE_DIR/system/srv-control-pxe-probe" /usr/local/libexec/srv-control-pxe-probe
install -m 0755 -o root -g root "$RELEASE_DIR/system/srv-control-backup" /usr/local/libexec/srv-control-backup
rm -f "$tmp_agent"
for u in srv-control-release14-agent.service srv-control-release14-agent.path srv-control-backup-retention.service srv-control-backup-retention.path; do install -m 0644 -o root -g root "$RELEASE_DIR/system/$u" "/etc/systemd/system/$u"; done
install -d -m 0750 -o "$APP_USER" -g "$APP_GROUP" "$STATE_DIR/release14-actions" "$STATE_DIR/pxe" "$STATE_DIR/pxe/uploads"
install -d -m 0755 -o root -g "$APP_GROUP" "$STATE_DIR/release14-results" /srv/pxe /srv/pxe/media /srv/pxe/media/boot /srv/pxe/media/images /srv/pxe/media/isos /srv/pxe/media/software /srv/tftp
install -d -m 0750 -o root -g "$APP_GROUP" /srv/pxe/profiles
log "Applying database migration 14f0a1400001"
runuser -u "$APP_USER" -- env PYTHONPATH="$PROJECT" PYTHONDONTWRITEBYTECODE=1 "$PROJECT/venv/bin/alembic" -c "$PROJECT/alembic.ini" upgrade head
systemctl daemon-reload
systemctl enable --now srv-control-release14-agent.path
systemctl enable --now srv-control-backup-retention.path
sync_time="$(date -Is)"
python3 - "$META" "$RELEASE_VERSION" "$RELEASE_ID" "$sync_time" "$REMOTE_SHA" <<'PY'
import json,pathlib,sys
p=pathlib.Path(sys.argv[1]);p.write_text(json.dumps({'version':sys.argv[2],'release_id':sys.argv[3],'synced_at':sys.argv[4],'git_sha':sys.argv[5]},ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
PY
chmod 0644 "$META"
log "Rotating Control Center workers"
"$REPO_ROOT/deploy/reload-srv-control.sh" srv-control.service http://127.0.0.1:8876/api/v1/health
log "APPLY PASS: release=1.4.0 sha=$REMOTE_SHA"
