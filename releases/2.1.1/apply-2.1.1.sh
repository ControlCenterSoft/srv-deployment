#!/usr/bin/env bash
set -Eeuo pipefail
umask 027

PROJECT="${1:-/opt/srv-control}"
REMOTE_SHA="${2:-unknown}"
RELEASE_ID="2.1.1"
RELEASE_VERSION="2.1.1"
RELEASE_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_ROOT="$(cd -- "${RELEASE_DIR}/../.." && pwd -P)"
BASE_RELEASE="${REPO_ROOT}/releases/2.1.0"
SYSTEM="${RELEASE_DIR}/system"
PAYLOAD="${RELEASE_DIR}/payload"
STATE_DIR="/var/lib/srv-control"
RELEASE_META="${STATE_DIR}/release.json"
BACKUP_DIR="/var/lib/srv-deployment/backups/${REMOTE_SHA}-${RELEASE_ID}"
CANONICAL_UNIT="srv-control-minecraft-bedrock.service"
PERMISSIONS_UNIT="srv-control-minecraft-permissions.service"
UPDATE_SERVICE="srv-control-minecraft-bedrock-update.service"
UPDATE_TIMER="srv-control-minecraft-bedrock-update.timer"
TARGET_USER="minecraft"
TARGET_GROUP="minecraft"
ROLES=(srv-control-minecraft srv-control-minecraft-worlds srv-control-minecraft-players srv-control-minecraft-restore srv-control-minecraft-live)

log(){ printf '%s %s\n' "$(date -Is)" "$*"; }
fail(){ printf 'APPLY 2.1.1 FAIL: %s\n' "$*" >&2; exit 1; }

release_version(){
    python3 - "$RELEASE_META" <<'PY'
import json,pathlib,sys
try: p=json.loads(pathlib.Path(sys.argv[1]).read_text(encoding='utf-8'))
except Exception: p={}
print(str(p.get('version') or ''))
PY
}

ORIGINAL_SOURCE="$(release_version)"
[[ "$ORIGINAL_SOURCE" == "1.3.8" || "$ORIGINAL_SOURCE" == "2.0.0" || "$ORIGINAL_SOURCE" == "2.1.0" ]] \
    || fail "unsupported source version: $ORIGINAL_SOURCE"

install -d -m 0750 "$BACKUP_DIR/system" "$BACKUP_DIR/state"
printf '%s\n' "$ORIGINAL_SOURCE" > "$BACKUP_DIR/state/original-source-version"

# A server that skipped 2.1.0 first receives the exact frozen 2.1.0 transaction.
# Its own rollback snapshot is separate (${REMOTE_SHA}-2.1.0), so a later 2.1.1
# rollback can unwind the patch and then the base transition without editing 2.1.0.
if [[ "$ORIGINAL_SOURCE" != "2.1.0" ]]; then
    log "Applying frozen 2.1.0 baseline before 2.1.1 hardening"
    bash "$BASE_RELEASE/apply-2.1.0.sh" "$PROJECT" "$REMOTE_SHA"
fi
[[ "$(release_version)" == "2.1.0" ]] || fail "2.1.0 baseline was not established"

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
backup_path "/etc/systemd/system/$PERMISSIONS_UNIT"
backup_path "/etc/systemd/system/$UPDATE_SERVICE"
backup_path "/etc/systemd/system/$UPDATE_TIMER"
backup_path "/usr/local/libexec/srv-control-minecraft-permissions"
backup_path "/usr/local/libexec/srv-control-minecraft-bedrock-update"
backup_path "/usr/local/libexec/srv-control-minecraft-dispatch"
backup_path "/usr/local/libexec/srv-control-minecraft-2.1.0"
backup_path "/usr/local/libexec/srv-control-minecraft-agent"
backup_path "$PROJECT/app/core/minecraft_privileged.py"
backup_path "$PROJECT/app/routers/minecraft_legacy.py"
for role in "${ROLES[@]}"; do backup_path "/usr/local/sbin/$role"; done

for unit in \
    "$CANONICAL_UNIT" \
    minecraft-update.timer \
    srv-control-minecraft-auto-update.timer \
    "$UPDATE_TIMER" \
    srv-control-minecraft-agent.path
do
    systemctl is-enabled "$unit" > "$BACKUP_DIR/state/${unit}.enabled" 2>/dev/null || true
    systemctl is-active "$unit" > "$BACKUP_DIR/state/${unit}.active" 2>/dev/null || true
done

if getent passwd "$TARGET_USER" >/dev/null 2>&1; then echo yes > "$BACKUP_DIR/state/target-user-existed"; else echo no > "$BACKUP_DIR/state/target-user-existed"; fi
if getent group "$TARGET_GROUP" >/dev/null 2>&1; then echo yes > "$BACKUP_DIR/state/target-group-existed"; else echo no > "$BACKUP_DIR/state/target-group-existed"; fi

RUNTIME="$(systemctl show "$CANONICAL_UNIT" -p WorkingDirectory --value)"
[[ -d "$RUNTIME" && -f "$RUNTIME/bedrock_server" ]] || fail "canonical runtime is invalid: $RUNTIME"
printf '%s\n' "$RUNTIME" > "$BACKUP_DIR/state/runtime-path"

# Record ownership and mode metadata only. No world content is rewritten by this
# snapshot, and rollback can restore the exact pre-2.1.1 metadata without replacing
# world files that may legitimately change while the server is in use.
python3 - "$RUNTIME" "$BACKUP_DIR/state/runtime-metadata.jsonl" <<'PY'
import json,os,pathlib,stat,sys
root=pathlib.Path(sys.argv[1]).resolve(); out=pathlib.Path(sys.argv[2])
with out.open('w',encoding='utf-8') as h:
    paths=[root]
    for base,dirs,files in os.walk(root,topdown=True,followlinks=False):
        b=pathlib.Path(base)
        paths.extend(b/name for name in dirs)
        paths.extend(b/name for name in files)
    seen=set()
    for path in paths:
        try: info=path.lstat()
        except FileNotFoundError: continue
        rel='.' if path == root else str(path.relative_to(root))
        if rel in seen: continue
        seen.add(rel)
        h.write(json.dumps({'path':rel,'uid':info.st_uid,'gid':info.st_gid,'mode':stat.S_IMODE(info.st_mode),'symlink':stat.S_ISLNK(info.st_mode)},ensure_ascii=False)+'\n')
print('RUNTIME METADATA SNAPSHOT PASS:',len(seen))
PY
chmod 0600 "$BACKUP_DIR/state/runtime-metadata.jsonl"

install -d -m 0755 /usr/local/libexec /usr/local/sbin "$PROJECT/app/core"
install -m 0755 -o root -g root "$SYSTEM/srv-control-minecraft-permissions" /usr/local/libexec/srv-control-minecraft-permissions
install -m 0755 -o root -g root "$SYSTEM/srv-control-minecraft-bedrock-update" /usr/local/libexec/srv-control-minecraft-bedrock-update
install -m 0755 -o root -g root "$SYSTEM/srv-control-minecraft-agent" /usr/local/libexec/srv-control-minecraft-agent
install -m 0644 -o root -g root "$SYSTEM/$PERMISSIONS_UNIT" "/etc/systemd/system/$PERMISSIONS_UNIT"
install -m 0644 -o root -g root "$SYSTEM/$UPDATE_SERVICE" "/etc/systemd/system/$UPDATE_SERVICE"
install -m 0644 -o root -g root "$SYSTEM/$UPDATE_TIMER" "/etc/systemd/system/$UPDATE_TIMER"
install -m 0644 -o root -g root "$PAYLOAD/app/core/minecraft_privileged.py" "$PROJECT/app/core/minecraft_privileged.py"

# The web service intentionally keeps NoNewPrivileges=true. Legacy Minecraft UI
# code from 2.0/2.1.0 tried sudo from that sandbox, which can never elevate and
# produces the exact "no new privileges" error. Patch only the known helper launch
# function so all privileged operations cross the already-existing root agent.
python3 "$SYSTEM/srv-control-minecraft-router-bridge-patch" "$PROJECT/app/routers/minecraft_legacy.py"
python3 -m py_compile "$PROJECT/app/core/minecraft_privileged.py" "$PROJECT/app/routers/minecraft_legacy.py"
! grep -Fq '["/usr/bin/sudo", "-n", str(helper), *args]' "$PROJECT/app/routers/minecraft_legacy.py" \
    || fail "sudo remains in the installed Minecraft legacy router"

install -d -m 0770 -o root -g srv-control /var/lib/srv-control/minecraft-actions
install -d -m 0755 -o root -g srv-control /var/lib/srv-control/system-results
systemctl daemon-reload
systemctl enable --now srv-control-minecraft-agent.path

# Preserve the frozen 2.1.0 public dispatcher under role-correct basenames so the
# 2.1.1 wrapper can delegate every established operation without forking its logic.
rm -rf /usr/local/libexec/srv-control-minecraft-2.1.0
install -d -m 0755 -o root -g root /usr/local/libexec/srv-control-minecraft-2.1.0
for role in "${ROLES[@]}"; do
    [[ -x "/usr/local/sbin/$role" ]] || fail "2.1.0 public Minecraft helper is missing: $role"
    install -m 0755 -o root -g root "/usr/local/sbin/$role" "/usr/local/libexec/srv-control-minecraft-2.1.0/$role"
    install -m 0755 -o root -g root "$SYSTEM/srv-control-minecraft-dispatch" "/usr/local/sbin/$role"
done
install -m 0755 -o root -g root "$SYSTEM/srv-control-minecraft-dispatch" /usr/local/libexec/srv-control-minecraft-dispatch

/usr/local/libexec/srv-control-minecraft-permissions prepare-user > "$BACKUP_DIR/state/identity-result.json" \
    || { cat "$BACKUP_DIR/state/identity-result.json" >&2 || true; fail "dedicated Minecraft identity could not be prepared"; }

log "Stopping canonical Bedrock service for ownership transition"
systemctl stop "$CANONICAL_UNIT"

# Harden only the service identity/dependency lines; preserve the proven 2.1.0
# runtime path, binary, stop signal, restart policy and sandbox directives exactly.
python3 - "/etc/systemd/system/$CANONICAL_UNIT" "$PERMISSIONS_UNIT" <<'PY'
import pathlib,sys,tempfile,os
path=pathlib.Path(sys.argv[1]); permissions=sys.argv[2]
lines=path.read_text(encoding='utf-8').splitlines()
out=[]; section=''; have_requires=False; have_user=False; have_group=False
for line in lines:
    stripped=line.strip()
    if stripped.startswith('[') and stripped.endswith(']'):
        if section == 'Unit' and not have_requires:
            out.append(f'Requires={permissions}')
            have_requires=True
        section=stripped[1:-1]
        out.append(line); continue
    if section == 'Unit' and stripped.startswith('Requires='):
        values=stripped.split('=',1)[1].split()
        if permissions not in values: values.append(permissions)
        out.append('Requires='+' '.join(values)); have_requires=True; continue
    if section == 'Unit' and stripped.startswith('After='):
        values=stripped.split('=',1)[1].split()
        if permissions not in values: values.append(permissions)
        out.append('After='+' '.join(values)); continue
    if section == 'Service' and stripped.startswith('User='):
        out.append('User=minecraft'); have_user=True; continue
    if section == 'Service' and stripped.startswith('Group='):
        out.append('Group=minecraft'); have_group=True; continue
    if section == 'Service' and stripped.startswith('ExecStart='):
        if not have_user: out.append('User=minecraft'); have_user=True
        if not have_group: out.append('Group=minecraft'); have_group=True
    out.append(line)
if section == 'Unit' and not have_requires: out.append(f'Requires={permissions}')
text='\n'.join(out).rstrip()+'\n'
fd,tmp=tempfile.mkstemp(prefix='.'+path.name+'.',dir=str(path.parent))
try:
    with os.fdopen(fd,'w',encoding='utf-8') as h:
        h.write(text); h.flush(); os.fsync(h.fileno())
    os.chmod(tmp,0o644); os.replace(tmp,path)
finally:
    try: os.unlink(tmp)
    except FileNotFoundError: pass
PY

systemctl daemon-reload
/usr/local/libexec/srv-control-minecraft-permissions ensure > "$BACKUP_DIR/state/permissions-ensure.json" \
    || { cat "$BACKUP_DIR/state/permissions-ensure.json" >&2 || true; fail "runtime ownership transition failed"; }
systemctl reset-failed "$CANONICAL_UNIT" >/dev/null 2>&1 || true
systemctl enable --now "$CANONICAL_UNIT"

healthy=0
for _ in $(seq 1 30); do
    if "$BASE_RELEASE/system/srv-control-minecraft-normalize" audit > "$BACKUP_DIR/state/post-hardening-audit.json" 2>/dev/null \
       && python3 - "$BACKUP_DIR/state/post-hardening-audit.json" <<'PY'
import json,sys
p=json.load(open(sys.argv[1],encoding='utf-8'))
raise SystemExit(0 if p.get('canonical') and not p.get('needs_normalization') and p.get('port_listening') and p.get('world_exists') and len(p.get('pids') or [])==1 else 1)
PY
    then healthy=1; break; fi
    sleep 2
done
[[ "$healthy" == "1" ]] || { cat "$BACKUP_DIR/state/post-hardening-audit.json" >&2 || true; fail "Minecraft did not become healthy as the dedicated user"; }

# Replace both historical scheduler choices with one managed single-server timer.
systemctl disable --now srv-control-minecraft-auto-update.timer >/dev/null 2>&1 || true
systemctl disable --now minecraft-update.timer >/dev/null 2>&1 || true
systemctl enable --now "$UPDATE_TIMER"

# The updater check must be safe even when the installed version cannot yet be
# derived. It records decision_ready=false rather than blindly replacing runtime.
/usr/local/libexec/srv-control-minecraft-bedrock-update check > "$BACKUP_DIR/state/update-check.json" \
    || { cat "$BACKUP_DIR/state/update-check.json" >&2 || true; fail "canonical Minecraft updater check failed"; }

sync_time="$(date -Is)"
python3 - "$RELEASE_META" "$RELEASE_VERSION" "$RELEASE_ID" "$sync_time" "$REMOTE_SHA" <<'PY'
import grp,json,os,pathlib,sys,tempfile
path=pathlib.Path(sys.argv[1]); path.parent.mkdir(parents=True,exist_ok=True)
payload={'version':sys.argv[2],'release_id':sys.argv[3],'synced_at':sys.argv[4],'git_sha':sys.argv[5]}
try: gid=grp.getgrnam('srv-control').gr_gid
except KeyError: gid=0
fd,tmp=tempfile.mkstemp(prefix='.release-2.1.1.',dir=str(path.parent))
try:
    os.fchown(fd,0,gid); os.fchmod(fd,0o640)
    with os.fdopen(fd,'w',encoding='utf-8') as h:
        json.dump(payload,h,ensure_ascii=False,indent=2); h.write('\n'); h.flush(); os.fsync(h.fileno())
    os.replace(tmp,path)
finally:
    try: os.unlink(tmp)
    except FileNotFoundError: pass
PY

# Reload the web workers only after all app/runtime changes and release metadata are
# complete. NoNewPrivileges remains enabled; the UI now reaches root only via the
# audited file-backed privileged Minecraft agent.
systemctl restart srv-control.service
for _ in $(seq 1 30); do
    curl -fsS --max-time 5 http://127.0.0.1:8876/api/v1/health >/dev/null 2>&1 && break
    sleep 1
done
curl -fsS --max-time 10 http://127.0.0.1:8876/api/v1/health >/dev/null \
    || fail "Control Center did not become healthy after Minecraft UI bridge activation"

log "APPLY 2.1.1 PASS: Bedrock runs as minecraft; UI privileged bridge avoids sudo/NoNewPrivileges conflict; runtime ownership guarded; canonical update timer enabled; source=$ORIGINAL_SOURCE"
