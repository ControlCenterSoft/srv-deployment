#!/usr/bin/env bash
set -Eeuo pipefail
umask 027

PROJECT="${1:-/opt/srv-control}"
REMOTE_SHA="${2:-unknown}"
RELEASE_ID="2.1.2"
RELEASE_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_ROOT="$(cd -- "${RELEASE_DIR}/../.." && pwd -P)"
BASE_RELEASE="${REPO_ROOT}/releases/2.1.1"
BACKUP_DIR="/var/lib/srv-deployment/backups/${REMOTE_SHA}-${RELEASE_ID}"
RELEASE_META="/var/lib/srv-control/release.json"
DELEGATE_ROOT="/usr/local/libexec/srv-control-minecraft-2.1.1"
ROLES=(srv-control-minecraft srv-control-minecraft-worlds srv-control-minecraft-players srv-control-minecraft-restore srv-control-minecraft-live)

log(){ printf '%s %s\n' "$(date -Is)" "$*"; }
fail(){ printf 'ROLLBACK 2.1.2 FAIL: %s\n' "$*" >&2; exit 1; }

[[ -d "$BACKUP_DIR" ]] || fail "rollback backup is missing: $BACKUP_DIR"
ORIGINAL_SOURCE="$(cat "$BACKUP_DIR/state/original-source-version" 2>/dev/null || true)"
case "$ORIGINAL_SOURCE" in
    1.3.8|2.0.0|2.1.0|2.1.1) ;;
    *) fail "original source version is missing or unsupported: ${ORIGINAL_SOURCE:-missing}" ;;
esac

restore_path(){
    local path="$1" key="${1#/}" saved="$BACKUP_DIR/system/${1#/}"
    if [[ -e "$saved" || -L "$saved" ]]; then
        rm -rf -- "$path"
        install -d -m 0755 "$(dirname -- "$path")"
        cp -a -- "$saved" "$path"
    elif [[ -f "${saved}.absent" ]]; then
        rm -rf -- "$path"
    else
        fail "rollback metadata missing for $path"
    fi
}

restore_path "$PROJECT/templates/minecraft.html"
restore_path "$PROJECT/static/js/minecraft-status-2.1.2.js"
restore_path "$DELEGATE_ROOT"
for role in "${ROLES[@]}"; do
    restore_path "/usr/local/sbin/$role"
done
restore_path "$RELEASE_META"

systemctl daemon-reload
systemctl restart srv-control.service
for _ in $(seq 1 30); do
    curl -fsS --max-time 5 http://127.0.0.1:8876/api/v1/health >/dev/null 2>&1 && break
    sleep 1
done

if [[ "$ORIGINAL_SOURCE" != "2.1.1" ]]; then
    log "Unwinding frozen 2.1.1 baseline to original source $ORIGINAL_SOURCE"
    bash "$BASE_RELEASE/rollback-2.1.1.sh" "$PROJECT" "$REMOTE_SHA"
fi

log "ROLLBACK 2.1.2 PASS: restored source=$ORIGINAL_SOURCE"
