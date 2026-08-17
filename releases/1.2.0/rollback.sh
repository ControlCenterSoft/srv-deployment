#!/usr/bin/env bash
set -Eeuo pipefail

PROJECT="${1:-/opt/srv-control}"
REMOTE_SHA="${2:-unknown}"
RELEASE_ID="1.2.0"
RELEASE_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
LEGACY_ROLLBACK="${RELEASE_DIR}/../1.1.0/rollback.sh"
BACKUP_ROOT="/var/lib/srv-deployment/backups"
CURRENT_BACKUP="${BACKUP_ROOT}/${REMOTE_SHA}-${RELEASE_ID}"
COMPAT_BACKUP="${BACKUP_ROOT}/${REMOTE_SHA}-1.1.0"

fail() {
    printf 'ROLLBACK FAIL: %s\n' "$*" >&2
    exit 1
}

[[ -x "$LEGACY_ROLLBACK" || -s "$LEGACY_ROLLBACK" ]] \
    || fail "validated 1.1.0 rollback implementation missing"
[[ -d "$CURRENT_BACKUP" ]] || fail "deployment backup missing: $CURRENT_BACKUP"

# The 1.1 rollback contract still knows two legacy private-auth files that are
# intentionally absent from 1.2. Mark them as absent so the validated restore
# routine removes/keeps them absent instead of treating the backup as corrupt.
for key in \
    var/lib/srv-control/auth.json \
    var/lib/srv-control/admin-bootstrap.txt
do
    if [[ ! -e "$CURRENT_BACKUP/system/$key" && ! -e "$CURRENT_BACKUP/system/${key}.absent" ]]; then
        install -d -m 0750 "$CURRENT_BACKUP/system/$(dirname -- "$key")"
        : > "$CURRENT_BACKUP/system/${key}.absent"
    fi
done

created_compat=0
if [[ ! -e "$COMPAT_BACKUP" ]]; then
    ln -s "$CURRENT_BACKUP" "$COMPAT_BACKUP"
    created_compat=1
fi

cleanup() {
    if (( created_compat )) && [[ -L "$COMPAT_BACKUP" ]]; then
        unlink "$COMPAT_BACKUP" || true
    fi
}
trap cleanup EXIT

bash "$LEGACY_ROLLBACK" "$PROJECT" "$REMOTE_SHA"
printf 'ROLLBACK PASS: release=%s sha=%s\n' "$RELEASE_ID" "$REMOTE_SHA"
