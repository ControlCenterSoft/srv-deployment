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

# If the source did not already use the 2.1 canonical service, stop it before
# restoring the previous platform. This prevents an old unit or process restored
# by rollback from racing the canonical service for UDP/19132.
if [[ "$previous_unit" != "$CANONICAL_UNIT" ]]; then
    systemctl stop "$CANONICAL_UNIT" >/dev/null 2>&1 || true
fi

if [[ "$SOURCE_VERSION" == "1.3.8" ]]; then
    bash "$BASE_RELEASE/rollback-2.0.0.sh" "$PROJECT" "$REMOTE_SHA" \
        || fail "published 2.0.0 rollback failed while returning to 1.3.8"
else
    restore_path /var/lib/srv-control/release.json
    for role in "${ROLES[@]}"; do
        restore_path "/usr/local/sbin/$role"
        restore_path "/usr/local/libexec/$role"
    done
fi

# These paths are introduced or replaced specifically by 2.1.0 and therefore
# always use the 2.1 snapshot, independent of the source platform version.
restore_path /usr/local/libexec/srv-control-minecraft-normalize
restore_path /usr/local/libexec/srv-control-minecraft-dispatch

# Restore the previous canonical unit when one existed. If the original Bedrock
# process was unmanaged, keep the generated unit available but disabled as a
# last-resort availability fallback; there is no old unit that can be restarted.
if [[ -n "$previous_unit" ]]; then
    restore_path "/etc/systemd/system/$CANONICAL_UNIT"
else
    if [[ -s "$BACKUP_DIR/state/canonical-unit.generated" ]]; then
        install -m 0644 -o root -g root "$BACKUP_DIR/state/canonical-unit.generated" "/etc/systemd/system/$CANONICAL_UNIT"
    else
        restore_path "/etc/systemd/system/$CANONICAL_UNIT"
    fi
fi
systemctl daemon-reload

if [[ -n "$previous_unit" && "$previous_unit" != "$CANONICAL_UNIT" ]]; then
    systemctl reset-failed "$previous_unit" >/dev/null 2>&1 || true
    if ! systemctl start "$previous_unit" >/dev/null 2>&1; then
        warn "previous Minecraft unit $previous_unit could not be restarted"
    fi
fi

bedrock_count="$(pgrep -x bedrock_server 2>/dev/null | wc -l | tr -d ' ')"
if [[ "$bedrock_count" == "0" && -z "$previous_unit" ]]; then
    # availability fallback: the source had no recoverable managed unit. Start
    # the exact preserved runtime through the generated canonical unit rather
    # than leaving the Minecraft world unavailable after rollback.
    if systemctl cat "$CANONICAL_UNIT" >/dev/null 2>&1; then
        warn "source Bedrock was unmanaged; starting preserved runtime through canonical availability fallback"
        systemctl reset-failed "$CANONICAL_UNIT" >/dev/null 2>&1 || true
        systemctl enable --now "$CANONICAL_UNIT" >/dev/null 2>&1 \
            || warn "canonical availability fallback could not be started"
    else
        warn "source Bedrock was unmanaged and no generated fallback unit is available"
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
