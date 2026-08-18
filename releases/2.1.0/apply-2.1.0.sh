#!/usr/bin/env bash
set -Eeuo pipefail
umask 027

PROJECT="${1:-/opt/srv-control}"
REMOTE_SHA="${2:-unknown}"
RELEASE_ID="2.1.0"
RELEASE_VERSION="2.1.0"
RELEASE_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_ROOT="$(cd -- "${RELEASE_DIR}/../.." && pwd -P)"
BASE_RELEASE="${REPO_ROOT}/releases/2.0.0"
SYSTEM="${RELEASE_DIR}/system"
STATE_DIR="/var/lib/srv-control"
RELEASE_META="${STATE_DIR}/release.json"
BACKUP_DIR="/var/lib/srv-deployment/backups/${REMOTE_SHA}-${RELEASE_ID}"
CANONICAL_UNIT="srv-control-minecraft-bedrock.service"
ROLES=(srv-control-minecraft srv-control-minecraft-worlds srv-control-minecraft-players srv-control-minecraft-restore srv-control-minecraft-live)

log(){ printf '%s %s\n' "$(date -Is)" "$*"; }
fail(){ printf 'APPLY 2.1.0 FAIL: %s\n' "$*" >&2; exit 1; }

current_version(){
    python3 - "$RELEASE_META" <<'PY'
import json,pathlib,sys
try: data=json.loads(pathlib.Path(sys.argv[1]).read_text(encoding='utf-8'))
except Exception: data={}
print(str(data.get('version') or ''))
PY
}

SOURCE_VERSION="$(current_version)"
[[ "$SOURCE_VERSION" == "1.3.8" || "$SOURCE_VERSION" == "2.0.0" ]] || fail "unsupported source version: $SOURCE_VERSION"

install -d -m 0750 "$BACKUP_DIR/system" "$BACKUP_DIR/state"
printf '%s\n' "$SOURCE_VERSION" > "$BACKUP_DIR/state/source-version"

backup_path(){
    local path="$1" key="${1#/}"
    install -d -m 0750 "$BACKUP_DIR/system/$(dirname -- "$key")"
    if [[ -e "$path" || -L "$path" ]]; then
        cp -a -- "$path" "$BACKUP_DIR/system/$key"
    else
        : > "$BACKUP_DIR/system/${key}.absent"
    fi
}

backup_path "$RELEASE_META"
backup_path "/etc/systemd/system/$CANONICAL_UNIT"
backup_path "/usr/local/libexec/srv-control-minecraft-normalize"
backup_path "/usr/local/libexec/srv-control-minecraft-dispatch"
for role in "${ROLES[@]}"; do
    backup_path "/usr/local/sbin/$role"
    backup_path "/usr/local/libexec/$role"
done
for unit in minecraft-update.timer srv-control-minecraft-auto-update.timer "$CANONICAL_UNIT"; do
    systemctl is-enabled "$unit" > "$BACKUP_DIR/state/${unit}.enabled" 2>/dev/null || true
    systemctl is-active "$unit" > "$BACKUP_DIR/state/${unit}.active" 2>/dev/null || true
done

if [[ "$SOURCE_VERSION" == "1.3.8" ]]; then
    log "Carrying forward the complete published 2.0.0 platform before Minecraft normalization"
    bash "$BASE_RELEASE/apply-2.0.0.sh" "$PROJECT" "$REMOTE_SHA"
fi

# Whether 2.0.0 was just carried forward or was already installed, prove its
# published acceptance contract before changing Minecraft service ownership.
log "Validating the published 2.0.0 baseline"
bash "$BASE_RELEASE/acceptance-2.0.0.sh" "$PROJECT" "$REMOTE_SHA"

install -d -m 0755 /usr/local/libexec /usr/local/sbin
install -m 0755 -o root -g root "$SYSTEM/srv-control-minecraft-normalize" /usr/local/libexec/srv-control-minecraft-normalize
install -m 0755 -o root -g root "$SYSTEM/srv-control-minecraft-dispatch" /usr/local/libexec/srv-control-minecraft-dispatch

# Keep the proven 2.0 legacy implementation as a data/control backend but do not
# expose it directly. The 2.1 dispatcher is the public privileged entry point and
# keeps start/stop/restart/update/restore operations bound to one canonical unit.
for role in "${ROLES[@]}"; do
    install -m 0755 -o root -g root "$BASE_RELEASE/system/srv-control-minecraft-legacy" "/usr/local/libexec/$role"
    install -m 0755 -o root -g root "$SYSTEM/srv-control-minecraft-dispatch" "/usr/local/sbin/$role"
done

# Existing sudoers rules already authorize exactly these historical /usr/local/sbin
# paths, so no privilege surface expansion is needed for 2.1.0.
if command -v visudo >/dev/null 2>&1 && [[ -f /etc/sudoers.d/srv-control-minecraft-legacy ]]; then
    visudo -cf /etc/sudoers.d/srv-control-minecraft-legacy >/dev/null || fail "existing Minecraft sudoers rule is invalid"
fi

log "Normalizing the live Bedrock runtime into $CANONICAL_UNIT"
if ! /usr/local/libexec/srv-control-minecraft-normalize normalize > "$BACKUP_DIR/state/minecraft-normalize.json"; then
    cat "$BACKUP_DIR/state/minecraft-normalize.json" >&2 || true
    fail "Minecraft service normalization failed"
fi
cat "$BACKUP_DIR/state/minecraft-normalize.json"

systemctl disable --now srv-control-minecraft-auto-update.timer >/dev/null 2>&1 || true
if systemctl cat minecraft-update.timer >/dev/null 2>&1; then
    systemctl enable --now minecraft-update.timer >/dev/null 2>&1 || true
fi

sync_time="$(date -Is)"
python3 - "$RELEASE_META" "$RELEASE_VERSION" "$RELEASE_ID" "$sync_time" "$REMOTE_SHA" <<'PY'
import grp,json,os,pathlib,sys,tempfile
path=pathlib.Path(sys.argv[1]); path.parent.mkdir(parents=True,exist_ok=True)
payload={'version':sys.argv[2],'release_id':sys.argv[3],'synced_at':sys.argv[4],'git_sha':sys.argv[5]}
try: gid=grp.getgrnam('srv-control').gr_gid
except KeyError: gid=0
fd,tmp=tempfile.mkstemp(prefix='.release-2.1.0.',dir=str(path.parent))
try:
    os.fchown(fd,0,gid); os.fchmod(fd,0o640)
    with os.fdopen(fd,'w',encoding='utf-8') as handle:
        json.dump(payload,handle,ensure_ascii=False,indent=2); handle.write('\n'); handle.flush(); os.fsync(handle.fileno())
    os.replace(tmp,path)
finally:
    try: os.unlink(tmp)
    except FileNotFoundError: pass
PY

# Verify the dispatcher can observe exactly the canonical service after metadata
# transition. This catches the 2.0 failure mode where the game process was alive
# but Control Center could not safely restart it.
sudo -n -u root /usr/local/sbin/srv-control-minecraft status > "$BACKUP_DIR/state/minecraft-control-status.json" 2>/dev/null \
    || /usr/local/sbin/srv-control-minecraft status > "$BACKUP_DIR/state/minecraft-control-status.json"
python3 - "$BACKUP_DIR/state/minecraft-control-status.json" <<'PY'
import json,pathlib,sys
p=json.loads(pathlib.Path(sys.argv[1]).read_text(encoding='utf-8'))
assert p.get('ok') is True,p
assert p.get('service') == 'srv-control-minecraft-bedrock.service',p
assert p.get('active') is True,p
assert p.get('healthy') is True,p
print('MINECRAFT CONTROL PASS:',p.get('service'),p.get('level_name'),p.get('port'))
PY

log "APPLY 2.1.0 PASS: 2.0 carry-forward accepted; Minecraft canonical service healthy; source=$SOURCE_VERSION"
