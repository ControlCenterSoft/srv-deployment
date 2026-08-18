#!/usr/bin/env bash
set -Eeuo pipefail
umask 027

PROJECT="${1:-/opt/srv-control}"
REMOTE_SHA="${2:-unknown}"
RELEASE_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_ROOT="$(cd -- "${RELEASE_DIR}/../.." && pwd -P)"
BASE_RELEASE="${REPO_ROOT}/releases/2.0.0"
BACKUP_DIR="/var/lib/srv-deployment/backups/${REMOTE_SHA}-2.1.0"
CANONICAL_UNIT="srv-control-minecraft-bedrock.service"
ROLES=(srv-control-minecraft srv-control-minecraft-worlds srv-control-minecraft-players srv-control-minecraft-restore srv-control-minecraft-live)

fail(){ printf 'ROLLBACK 2.1.0 FAIL: %s\n' "$*" >&2; exit 1; }
warn(){ printf 'ROLLBACK 2.1.0 WARN: %s\n' "$*" >&2; }

[[ -d "$BACKUP_DIR" ]] || fail "2.1.0 rollback snapshot is missing: $BACKUP_DIR"
SOURCE_VERSION="$(cat "$BACKUP_DIR/state/source-version" 2>/dev/null || true)"
[[ "$SOURCE_VERSION" == "1.3.8" || "$SOURCE_VERSION" == "2.0.0" ]] || fail "rollback source version is invalid: $SOURCE_VERSION"

previous_unit="$(python3 - "$BACKUP_DIR/state/minecraft-normalize.json" <<'PY'
import json,pathlib,sys
try: p=json.loads(pathlib.Path(sys.argv[1]).read_text(encoding='utf-8'))
except Exception: p={}
units=((p.get('before') or {}).get('units') or {}) if isinstance(p,dict) else {}
values=[str(v) for v in units.values() if v]
print(values[0] if len(set(values)) == 1 else '')
PY
)"

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

# Stop the new canonical service before restoring an explicitly known previous
# managed service. If the old process was unmanaged we postpone shutdown until a
# safe fallback is known, preventing rollback from turning a working game server
# into an outage merely to reproduce legacy process ownership.
if [[ -n "$previous_unit" && "$previous_unit" != "$CANONICAL_UNIT" ]]; then
    systemctl stop "$CANONICAL_UNIT" >/dev/null 2>&1 || true
fi

if [[ "$SOURCE_VERSION" == "1.3.8" ]]; then
    bash "$BASE_RELEASE/rollback-2.0.0.sh" "$PROJECT" "$REMOTE_SHA" \
        || fail "published 2.0.0 rollback failed while returning to 1.3.8"
else
    restore_path /var/lib/srv-control/release.json
    restore_path "/etc/systemd/system/$CANONICAL_UNIT"
    restore_path /usr/local/libexec/srv-control-minecraft-normalize
    restore_path /usr/local/libexec/srv-control-minecraft-dispatch
    for role in "${ROLES[@]}"; do
        restore_path "/usr/local/sbin/$role"
        restore_path "/usr/local/libexec/$role"
    done
    systemctl daemon-reload
fi

if [[ -n "$previous_unit" && "$previous_unit" != "$CANONICAL_UNIT" ]]; then
    systemctl reset-failed "$previous_unit" >/dev/null 2>&1 || true
    if ! systemctl start "$previous_unit" >/dev/null 2>&1; then
        warn "previous Minecraft unit $previous_unit could not be restarted"
    fi
fi

bedrock_count="$(pgrep -x bedrock_server 2>/dev/null | wc -l | tr -d ' ')"
if [[ "$bedrock_count" == "0" ]]; then
    # Last-resort availability protection for a source state where Bedrock was
    # an unmanaged process. The canonical unit points to the same preserved
    # runtime/world. Keeping it running is safer than a dead server; the product
    # release metadata is still restored to the previous version.
    if systemctl cat "$CANONICAL_UNIT" >/dev/null 2>&1; then
        warn "no previous managed Bedrock unit was recoverable; starting preserved canonical runtime as availability fallback"
        systemctl enable --now "$CANONICAL_UNIT" >/dev/null 2>&1 || true
    fi
fi

# Restore timer intent captured before 2.1.0.
for unit in minecraft-update.timer srv-control-minecraft-auto-update.timer; do
    enabled="$(cat "$BACKUP_DIR/state/${unit}.enabled" 2>/dev/null || true)"
    active="$(cat "$BACKUP_DIR/state/${unit}.active" 2>/dev/null || true)"
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
done

printf 'ROLLBACK 2.1.0 PASS: restored source version=%s; previous_minecraft_unit=%s\n' "$SOURCE_VERSION" "${previous_unit:-unmanaged}"
