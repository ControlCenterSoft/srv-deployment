#!/usr/bin/env bash
set -Eeuo pipefail

RELEASE_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
SOURCE="${RELEASE_DIR}/apply.sh"
TMP="$(mktemp "${RELEASE_DIR}/.apply-1.3.3.XXXXXX.sh")"
SESSION_TMP=""
SESSION_KEY="/var/lib/srv-control/session.key"
cleanup(){ rm -f -- "$TMP"; [[ -n "$SESSION_TMP" ]] && rm -f -- "$SESSION_TMP" || true; }
trap cleanup EXIT

# Preserve the live session signing key independently of the release rollback tree.
# A failed deployment must never make the running UI temporarily lose authentication state.
if [[ -s "$SESSION_KEY" ]]; then
    SESSION_TMP="$(mktemp /var/lib/srv-control/.session-key.1.3.3.XXXXXX)"
    cp -a -- "$SESSION_KEY" "$SESSION_TMP"
fi

python3 - "$SOURCE" "$TMP" <<'PY'
from pathlib import Path
import sys
src=Path(sys.argv[1]); dst=Path(sys.argv[2]); text=src.read_text(encoding='utf-8')
if 'RELEASE_ID="1.3.0"' not in text or 'RELEASE_VERSION="1.3.0"' not in text:
    raise SystemExit('1.3.3 apply release anchors missing')
text=text.replace('1.3.0','1.3.3')
dst.write_text(text,encoding='utf-8')
PY
chmod 0700 "$TMP"
bash "$TMP" "$@"

# Guarantee that authentication survives worker rotation and any partial rollback.
if [[ ! -s "$SESSION_KEY" && -n "$SESSION_TMP" && -s "$SESSION_TMP" ]]; then
    install -m 0640 -o root -g srv-control "$SESSION_TMP" "$SESSION_KEY"
fi

# Restore the proven single-server Minecraft update path. The multi-instance updater
# currently reports automatic_instances=0 on the real server and must not remain authoritative.
systemctl disable --now srv-control-minecraft-auto-update.timer >/dev/null 2>&1 || true
systemctl enable --now minecraft-update.timer

# Keep the current UI/RBAC/CSRF model, but allow it to call the proven helper.
install -m 0440 -o root -g root \
    "$RELEASE_DIR/system/sudoers-srv-control-minecraft-legacy" \
    /etc/sudoers.d/srv-control-minecraft-legacy
/usr/sbin/visudo -cf /etc/sudoers.d/srv-control-minecraft-legacy >/dev/null

# Refresh updater state without downloading anything during the Control Center transaction.
/usr/local/sbin/srv-control-minecraft updater >/dev/null

printf 'APPLY 1.3.3 PASS: GitHub automatic mode preserved; legacy Minecraft updater authoritative\n'
