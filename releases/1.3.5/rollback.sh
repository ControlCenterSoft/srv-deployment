#!/usr/bin/env bash
set -Eeuo pipefail

PROJECT="${1:-/opt/srv-control}"
REMOTE_SHA="${2:-unknown}"
RELEASE_ID="1.3.0"
RELEASE_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
PREVIOUS_ROLLBACK="${RELEASE_DIR}/../1.2.0/rollback.sh"
BACKUP_ROOT="/var/lib/srv-deployment/backups"
CURRENT_BACKUP="${BACKUP_ROOT}/${REMOTE_SHA}-${RELEASE_ID}"
COMPAT_BACKUP="${BACKUP_ROOT}/${REMOTE_SHA}-1.2.0"

fail() { printf 'ROLLBACK FAIL: %s\n' "$*" >&2; exit 1; }
[[ -s "$PREVIOUS_ROLLBACK" ]] || fail "validated 1.2.0 rollback implementation missing"
[[ -d "$CURRENT_BACKUP" ]] || fail "deployment backup missing: $CURRENT_BACKUP"

# New 1.3 agents must be quiescent before restoring the 1.2 application.
for unit in \
    srv-control-samba-agent.path \
    srv-control-samba-monitor.timer \
    srv-control-samba-shares-monitor.timer \
    srv-control-minecraft-agent.path \
    srv-control-minecraft-monitor.timer \
    srv-control-minecraft-auto-update.timer \
    srv-control-minecraft-firewall.service
do
    systemctl disable --now "$unit" >/dev/null 2>&1 || true
done

created_compat=0
if [[ ! -e "$COMPAT_BACKUP" ]]; then
    ln -s "$CURRENT_BACKUP" "$COMPAT_BACKUP"
    created_compat=1
fi
cleanup() {
    if (( created_compat )) && [[ -L "$COMPAT_BACKUP" ]]; then unlink "$COMPAT_BACKUP" || true; fi
}
trap cleanup EXIT

bash "$PREVIOUS_ROLLBACK" "$PROJECT" "$REMOTE_SHA"
printf 'ROLLBACK PASS: release=%s sha=%s\n' "$RELEASE_ID" "$REMOTE_SHA"
