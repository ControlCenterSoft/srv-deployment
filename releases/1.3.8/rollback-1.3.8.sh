#!/usr/bin/env bash
set -Eeuo pipefail

RELEASE_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
SOURCE="${RELEASE_DIR}/rollback-1.3.7.sh"
TMP="$(mktemp "${RELEASE_DIR}/.rollback-1.3.8.XXXXXX.sh")"
RELEASE_FILE="/var/lib/srv-control/release.json"

cleanup(){ rm -f -- "$TMP"; }
trap cleanup EXIT
fail(){ printf 'ROLLBACK 1.3.8 FAIL: %s\n' "$*" >&2; exit 1; }

python3 - "$SOURCE" "$TMP" <<'PY'
from pathlib import Path
import sys
src=Path(sys.argv[1]); dst=Path(sys.argv[2])
text=src.read_text(encoding='utf-8')
if '1.3.7' not in text:
    raise SystemExit('1.3.8 rollback predecessor identity anchor missing')
text=text.replace('1.3.7','1.3.8')
dst.write_text(text,encoding='utf-8')
PY

[[ "$(dirname -- "$TMP")" == "$RELEASE_DIR" ]] \
  || fail "adapted rollback escaped release directory"
chmod 0700 "$TMP"
bash "$TMP" "$@"

# Older 1.3.6/1.3.7 pre-state may contain root:root 0640 release metadata.
# Preserve its content but repair readability for the srv-control API identity.
if [[ -f "$RELEASE_FILE" ]]; then
    chown root:srv-control "$RELEASE_FILE"
    chmod 0640 "$RELEASE_FILE"
fi

# Keep the privileged UI action path available even after a failed transaction.
systemctl daemon-reload
systemctl reset-failed srv-control-system-agent.service >/dev/null 2>&1 || true
systemctl enable srv-control-system-agent.path >/dev/null 2>&1 || true
if ! systemctl is-active --quiet srv-control-system-agent.path; then
    systemctl start srv-control-system-agent.path >/dev/null 2>&1 || true
fi

printf 'ROLLBACK 1.3.8 PASS: pre-release state restored; release metadata readability normalized\n'
