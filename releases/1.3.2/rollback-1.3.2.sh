#!/usr/bin/env bash
set -Eeuo pipefail

PROJECT="${1:-/opt/srv-control}"
REMOTE_SHA="${2:-unknown}"
RELEASE_ID="1.3.2"
RELEASE_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
PREVIOUS_ROLLBACK="${RELEASE_DIR}/../1.3.1/rollback-1.3.1.sh"
BACKUP_ROOT="/var/lib/srv-deployment/backups"
CURRENT_BACKUP="${BACKUP_ROOT}/${REMOTE_SHA}-${RELEASE_ID}"
COMPAT_BACKUP="${BACKUP_ROOT}/${REMOTE_SHA}-1.3.1"

fail() { printf 'ROLLBACK FAIL: %s\n' "$*" >&2; exit 1; }
[[ -s "$PREVIOUS_ROLLBACK" ]] || fail "validated 1.3.1 rollback implementation missing"
[[ -d "$CURRENT_BACKUP" ]] || fail "deployment backup missing: $CURRENT_BACKUP"

read_state() { local f="$1"; [[ -r "$f" ]] && head -n1 "$f" || true; }
legacy_enabled="$(read_state "$CURRENT_BACKUP/state/minecraft-update.timer.enabled.before-1.3.2")"
legacy_active="$(read_state "$CURRENT_BACKUP/state/minecraft-update.timer.active.before-1.3.2")"
modern_enabled="$(read_state "$CURRENT_BACKUP/state/srv-control-minecraft-auto-update.timer.enabled.before-1.3.2")"
modern_active="$(read_state "$CURRENT_BACKUP/state/srv-control-minecraft-auto-update.timer.active.before-1.3.2")"

created_compat=0
if [[ ! -e "$COMPAT_BACKUP" ]]; then ln -s "$CURRENT_BACKUP" "$COMPAT_BACKUP"; created_compat=1; fi
cleanup() { if (( created_compat )) && [[ -L "$COMPAT_BACKUP" ]]; then unlink "$COMPAT_BACKUP" || true; fi; }
trap cleanup EXIT

bash "$PREVIOUS_ROLLBACK" "$PROJECT" "$REMOTE_SHA"

rm -f /etc/sudoers.d/srv-control-minecraft-legacy

restore_unit_state() {
    local unit="$1" enabled="$2" active="$3"
    case "$enabled" in
        enabled|enabled-runtime|static|indirect) systemctl enable "$unit" >/dev/null 2>&1 || true ;;
        disabled) systemctl disable "$unit" >/dev/null 2>&1 || true ;;
    esac
    case "$active" in
        active|activating) systemctl start "$unit" >/dev/null 2>&1 || true ;;
        inactive|failed|deactivating) systemctl stop "$unit" >/dev/null 2>&1 || true ;;
    esac
}
restore_unit_state minecraft-update.timer "$legacy_enabled" "$legacy_active"
restore_unit_state srv-control-minecraft-auto-update.timer "$modern_enabled" "$modern_active"

printf 'ROLLBACK PASS: release=%s sha=%s\n' "$RELEASE_ID" "$REMOTE_SHA"
