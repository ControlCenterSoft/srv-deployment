#!/usr/bin/env bash
set -Eeuo pipefail
umask 027

PROJECT="${1:-/opt/srv-control}"
REMOTE_SHA="${2:-unknown}"
RELEASE_ID="2.1.2"
RELEASE_VERSION="2.1.2"
RELEASE_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_ROOT="$(cd -- "${RELEASE_DIR}/../.." && pwd -P)"
BASE_RELEASE="${REPO_ROOT}/releases/2.1.1"
SYSTEM="${RELEASE_DIR}/system"
PAYLOAD="${RELEASE_DIR}/payload"
STATE_DIR="/var/lib/srv-control"
RELEASE_META="${STATE_DIR}/release.json"
BACKUP_DIR="/var/lib/srv-deployment/backups/${REMOTE_SHA}-${RELEASE_ID}"
DELEGATE_ROOT="/usr/local/libexec/srv-control-minecraft-2.1.1"
ROLES=(srv-control-minecraft srv-control-minecraft-worlds srv-control-minecraft-players srv-control-minecraft-restore srv-control-minecraft-live)

log(){ printf '%s %s\n' "$(date -Is)" "$*"; }
fail(){ printf 'APPLY 2.1.2 FAIL: %s\n' "$*" >&2; exit 1; }

release_version(){
    python3 - "$RELEASE_META" <<'PY'
import json,pathlib,sys
try: data=json.loads(pathlib.Path(sys.argv[1]).read_text(encoding='utf-8'))
except Exception: data={}
print(str(data.get('version') or ''))
PY
}

ORIGINAL_SOURCE="$(release_version)"
case "$ORIGINAL_SOURCE" in
    1.3.8|2.0.0|2.1.0|2.1.1) ;;
    *) fail "unsupported source version: ${ORIGINAL_SOURCE:-missing}" ;;
esac

install -d -m 0750 "$BACKUP_DIR/system" "$BACKUP_DIR/state"
printf '%s\n' "$ORIGINAL_SOURCE" > "$BACKUP_DIR/state/original-source-version"

if [[ "$ORIGINAL_SOURCE" != "2.1.1" ]]; then
    log "Applying frozen 2.1.1 baseline before 2.1.2 status repair"
    bash "$BASE_RELEASE/apply-2.1.1.sh" "$PROJECT" "$REMOTE_SHA"
fi
[[ "$(release_version)" == "2.1.1" ]] || fail "2.1.1 baseline was not established"

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
backup_path "$PROJECT/templates/minecraft.html"
backup_path "$PROJECT/static/js/minecraft-status-2.1.2.js"
backup_path "$DELEGATE_ROOT"
for role in "${ROLES[@]}"; do
    backup_path "/usr/local/sbin/$role"
done

install -d -m 0755 -o root -g root "$PROJECT/static/js"
rm -rf "$DELEGATE_ROOT"
install -d -m 0755 -o root -g root "$DELEGATE_ROOT"

# Freeze the exact working 2.1.1 public entry points as delegates. The new 2.1.2
# dispatcher changes only canonical status/service semantics; all other mature
# operations continue through the frozen 2.1.1 implementation.
for role in "${ROLES[@]}"; do
    [[ -x "/usr/local/sbin/$role" ]] || fail "2.1.1 helper is missing: $role"
    install -m 0755 -o root -g root "/usr/local/sbin/$role" "$DELEGATE_ROOT/$role"
    install -m 0755 -o root -g root "$SYSTEM/srv-control-minecraft-dispatch" "/usr/local/sbin/$role"
done

install -m 0644 -o root -g root \
    "$PAYLOAD/static/js/minecraft-status-2.1.2.js" \
    "$PROJECT/static/js/minecraft-status-2.1.2.js"
python3 "$SYSTEM/srv-control-minecraft-ui-status-patch" "$PROJECT/templates/minecraft.html"

# The 2.1.1 privilege repair must remain intact. 2.1.2 never weakens the web
# sandbox and does not reintroduce sudo into the application worker.
[[ "$(systemctl show srv-control.service -p NoNewPrivileges --value)" == "yes" ]] \
    || fail "NoNewPrivileges unexpectedly disabled"
! grep -Fq '["/usr/bin/sudo", "-n", str(helper), *args]' "$PROJECT/app/routers/minecraft_legacy.py" \
    || fail "legacy sudo privilege path reappeared"

sync_time="$(date -Is)"
python3 - "$RELEASE_META" "$RELEASE_VERSION" "$RELEASE_ID" "$sync_time" "$REMOTE_SHA" <<'PY'
import grp,json,os,pathlib,sys,tempfile
path=pathlib.Path(sys.argv[1]); path.parent.mkdir(parents=True,exist_ok=True)
payload={'version':sys.argv[2],'release_id':sys.argv[3],'synced_at':sys.argv[4],'git_sha':sys.argv[5]}
try: gid=grp.getgrnam('srv-control').gr_gid
except KeyError: gid=0
fd,tmp=tempfile.mkstemp(prefix='.release-2.1.2.',dir=str(path.parent))
try:
    os.fchown(fd,0,gid); os.fchmod(fd,0o640)
    with os.fdopen(fd,'w',encoding='utf-8') as h:
        json.dump(payload,h,ensure_ascii=False,indent=2); h.write('\n'); h.flush(); os.fsync(h.fileno())
    os.replace(tmp,path)
finally:
    try: os.unlink(tmp)
    except FileNotFoundError: pass
PY

systemctl restart srv-control.service
for _ in $(seq 1 30); do
    curl -fsS --max-time 5 http://127.0.0.1:8876/api/v1/health >/dev/null 2>&1 && break
    sleep 1
done
curl -fsS --max-time 10 http://127.0.0.1:8876/api/v1/health >/dev/null \
    || fail "Control Center did not become healthy after Minecraft status UI activation"

/usr/local/sbin/srv-control-minecraft status > "$BACKUP_DIR/state/post-2.1.2-status.json" \
    || { cat "$BACKUP_DIR/state/post-2.1.2-status.json" >&2 || true; fail "canonical status helper failed"; }

log "APPLY 2.1.2 PASS: canonical status is independent of running PID; explicit command results and live UI status installed; source=$ORIGINAL_SOURCE"
