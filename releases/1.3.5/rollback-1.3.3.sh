#!/usr/bin/env bash
set -Eeuo pipefail

PROJECT="${1:-/opt/srv-control}"
REMOTE_SHA="${2:-unknown}"
RELEASE_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
SOURCE="${RELEASE_DIR}/rollback.sh"
TMP="$(mktemp "${TMPDIR:-/tmp}/srvcc-rollback-1.3.3.XXXXXX.sh")"
PRESTATE="/var/lib/srv-deployment/prestate/${REMOTE_SHA}-1.3.3"
BACKUP_STATE="/var/lib/srv-deployment/backups/${REMOTE_SHA}-1.3.3/state"
SESSION_KEY="/var/lib/srv-control/session.key"
cleanup(){ rm -f -- "$TMP"; }
trap cleanup EXIT

state_file(){ local name="$1"; if [[ -r "$BACKUP_STATE/$name" ]]; then echo "$BACKUP_STATE/$name"; else echo "$PRESTATE/$name"; fi; }
read_state(){ local f; f="$(state_file "$1")"; [[ -r "$f" ]] && head -n1 "$f" || true; }

python3 - "$SOURCE" "$TMP" <<'PY'
from pathlib import Path
import sys
src=Path(sys.argv[1]); dst=Path(sys.argv[2]); text=src.read_text(encoding='utf-8')
if 'RELEASE_ID="1.3.0"' not in text: raise SystemExit('1.3.3 rollback release anchor missing')
text=text.replace('RELEASE_ID="1.3.0"','RELEASE_ID="1.3.3"',1)
dst.write_text(text,encoding='utf-8')
PY
chmod 0700 "$TMP"
bash "$TMP" "$@"

# Remove the 1.3.3-only sudo grant after the previous application is restored.
rm -f /etc/sudoers.d/srv-control-minecraft-legacy

restore_unit_state(){
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
for unit in minecraft-update.timer srv-control-minecraft-auto-update.timer srvcc-github-agent.timer; do
    restore_unit_state "$unit" "$(read_state "$unit.enabled")" "$(read_state "$unit.active")"
done

# Authentication must remain available even if the generic rollback snapshot was
# taken during an earlier broken update transaction.
if [[ ! -s "$SESSION_KEY" ]]; then
    src="$(state_file session.key)"
    [[ -s "$src" ]] && install -m 0640 -o root -g srv-control "$src" "$SESSION_KEY" || true
fi

rm -rf -- "$PRESTATE" || true
printf 'ROLLBACK 1.3.3 PASS: release=1.3.3 sha=%s\n' "$REMOTE_SHA"
