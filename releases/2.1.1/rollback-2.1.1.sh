#!/usr/bin/env bash
set -Eeuo pipefail
umask 027

PROJECT="${1:-/opt/srv-control}"
REMOTE_SHA="${2:-unknown}"
RELEASE_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_ROOT="$(cd -- "${RELEASE_DIR}/../.." && pwd -P)"
BASE_RELEASE="${REPO_ROOT}/releases/2.1.0"
BACKUP_DIR="/var/lib/srv-deployment/backups/${REMOTE_SHA}-2.1.1"
CANONICAL_UNIT="srv-control-minecraft-bedrock.service"
UPDATE_TIMER="srv-control-minecraft-bedrock-update.timer"
TARGET_USER="minecraft"
TARGET_GROUP="minecraft"
ROLES=(srv-control-minecraft srv-control-minecraft-worlds srv-control-minecraft-players srv-control-minecraft-restore srv-control-minecraft-live)

fail(){ printf 'ROLLBACK 2.1.1 FAIL: %s\n' "$*" >&2; exit 1; }
warn(){ printf 'ROLLBACK 2.1.1 WARN: %s\n' "$*" >&2; }

[[ -d "$BACKUP_DIR" ]] || fail "2.1.1 rollback snapshot is missing: $BACKUP_DIR"
ORIGINAL_SOURCE="$(cat "$BACKUP_DIR/state/original-source-version" 2>/dev/null || true)"
[[ "$ORIGINAL_SOURCE" == "1.3.8" || "$ORIGINAL_SOURCE" == "2.0.0" || "$ORIGINAL_SOURCE" == "2.1.0" ]] || fail "rollback source version is invalid: $ORIGINAL_SOURCE"

restore_path(){
    local path="$1" key="${1#/}" saved="$BACKUP_DIR/system/${1#/}" absent="$BACKUP_DIR/system/${1#/}.absent"
    if [[ -e "$saved" || -L "$saved" ]]; then
        install -d -m 0755 "$(dirname -- "$path")"
        rm -rf -- "$path"
        cp -a -- "$saved" "$path"
    elif [[ -e "$absent" ]]; then
        rm -rf -- "$path"
    fi
}

restore_timer_state(){
    local unit="$1" enabled active
    enabled="$(cat "$BACKUP_DIR/state/${unit}.enabled" 2>/dev/null || true)"
    active="$(cat "$BACKUP_DIR/state/${unit}.active" 2>/dev/null || true)"
    if [[ "$enabled" == "enabled" || "$enabled" == "enabled-runtime" ]]; then systemctl enable "$unit" >/dev/null 2>&1 || true; else systemctl disable "$unit" >/dev/null 2>&1 || true; fi
    if [[ "$active" == "active" ]]; then systemctl start "$unit" >/dev/null 2>&1 || true; else systemctl stop "$unit" >/dev/null 2>&1 || true; fi
}

systemctl disable --now "$UPDATE_TIMER" >/dev/null 2>&1 || true
systemctl stop "$CANONICAL_UNIT" >/dev/null 2>&1 || true

restore_path /var/lib/srv-control/release.json
restore_path "/etc/systemd/system/$CANONICAL_UNIT"
restore_path /etc/systemd/system/srv-control-minecraft-permissions.service
restore_path /etc/systemd/system/srv-control-minecraft-bedrock-update.service
restore_path /etc/systemd/system/srv-control-minecraft-bedrock-update.timer
restore_path /usr/local/libexec/srv-control-minecraft-permissions
restore_path /usr/local/libexec/srv-control-minecraft-bedrock-update
restore_path /usr/local/libexec/srv-control-minecraft-dispatch
restore_path /usr/local/libexec/srv-control-minecraft-2.1.0
restore_path /usr/local/libexec/srv-control-minecraft-agent
restore_path "$PROJECT/app/core/minecraft_privileged.py"
restore_path "$PROJECT/app/routers/minecraft_legacy.py"
for role in "${ROLES[@]}"; do restore_path "/usr/local/sbin/$role"; done
systemctl daemon-reload

RUNTIME="$(cat "$BACKUP_DIR/state/runtime-path" 2>/dev/null || true)"
META="$BACKUP_DIR/state/runtime-metadata.jsonl"
if [[ -d "$RUNTIME" && -s "$META" ]]; then
    python3 - "$RUNTIME" "$META" <<'PY'
import json,os,pathlib,stat,sys
root=pathlib.Path(sys.argv[1]).resolve(); meta=pathlib.Path(sys.argv[2])
restored=0
for raw in meta.read_text(encoding='utf-8').splitlines():
    if not raw.strip(): continue
    row=json.loads(raw); rel=row['path']; path=root if rel == '.' else root / rel
    try: info=path.lstat()
    except FileNotFoundError: continue
    os.lchown(path,int(row['uid']),int(row['gid']))
    if not stat.S_ISLNK(info.st_mode): os.chmod(path,int(row['mode']))
    restored += 1
print('RUNTIME METADATA RESTORE PASS:',restored)
PY
else
    warn "runtime metadata snapshot is unavailable; ownership rollback could not be fully replayed"
fi

if [[ "$ORIGINAL_SOURCE" == "2.1.0" ]]; then
    restore_timer_state minecraft-update.timer
    restore_timer_state srv-control-minecraft-auto-update.timer
    restore_timer_state srv-control-minecraft-agent.path
    restore_timer_state "$CANONICAL_UNIT"
    if [[ "$(cat "$BACKUP_DIR/state/${CANONICAL_UNIT}.active" 2>/dev/null || true)" == "active" ]]; then
        systemctl reset-failed "$CANONICAL_UNIT" >/dev/null 2>&1 || true
        systemctl start "$CANONICAL_UNIT" || fail "restored 2.1.0 Minecraft service could not be started"
    fi
    /usr/local/sbin/srv-control-minecraft status > /tmp/srvcc-2.1.1-rollback-status.json || { cat /tmp/srvcc-2.1.1-rollback-status.json >&2 || true; fail "restored 2.1.0 Minecraft status failed"; }
    python3 - /tmp/srvcc-2.1.1-rollback-status.json <<'PY'
import json,sys
p=json.load(open(sys.argv[1],encoding='utf-8'))
assert p.get('ok') is True,p
assert p.get('active') is True,p
assert p.get('healthy') is True,p
assert p.get('port_listening') is True,p
assert p.get('world_exists') is True,p
print('2.1.0 ROLLBACK HEALTH PASS:',p.get('service'),p.get('level_name'),p.get('port'))
PY
    rm -f /tmp/srvcc-2.1.1-rollback-status.json
else
    bash "$BASE_RELEASE/rollback-2.1.0.sh" "$PROJECT" "$REMOTE_SHA" || fail "frozen 2.1.0 rollback failed while returning to $ORIGINAL_SOURCE"
fi

if [[ "$(cat "$BACKUP_DIR/state/target-user-existed" 2>/dev/null || echo yes)" == "no" ]]; then command -v userdel >/dev/null 2>&1 && userdel "$TARGET_USER" >/dev/null 2>&1 || warn "temporary minecraft account could not be removed"; fi
if [[ "$(cat "$BACKUP_DIR/state/target-group-existed" 2>/dev/null || echo yes)" == "no" ]]; then command -v groupdel >/dev/null 2>&1 && groupdel "$TARGET_GROUP" >/dev/null 2>&1 || warn "temporary minecraft group could not be removed"; fi

systemctl restart srv-control.service >/dev/null 2>&1 || fail "Control Center could not be restarted after rollback"
for _ in $(seq 1 30); do curl -fsS --max-time 5 http://127.0.0.1:8876/api/v1/health >/dev/null 2>&1 && break; sleep 1; done
curl -fsS --max-time 10 http://127.0.0.1:8876/api/v1/health >/dev/null || fail "Control Center health did not recover after rollback"

printf 'ROLLBACK 2.1.1 PASS: restored source=%s; Minecraft UI bridge/agent, runtime metadata and scheduler state replayed\n' "$ORIGINAL_SOURCE"
