#!/usr/bin/env bash
set -Eeuo pipefail

SOURCE_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
SOURCE="${SOURCE_DIR}/rollback-1.3.3.sh"
TMP="$(mktemp "${SOURCE_DIR}/.rollback-1.3.7.XXXXXX.sh")"
cleanup(){ rm -f -- "$TMP"; }
trap cleanup EXIT
fail(){ printf 'ROLLBACK 1.3.7 FAIL: %s\n' "$*" >&2; exit 1; }

python3 - "$SOURCE" "$TMP" <<'PY'
from pathlib import Path
import sys
src=Path(sys.argv[1]); dst=Path(sys.argv[2])
text=src.read_text(encoding='utf-8')
if "1.3.3" not in text:
    raise SystemExit("1.3.7 rollback predecessor identity anchor missing")
text=text.replace("1.3.3","1.3.7")

# rollback-1.3.3.sh creates a second adapted rollback.sh. rollback.sh resolves
# ../1.2.0/rollback.sh relative to BASH_SOURCE, so that inner temporary script
# must also stay inside the release directory instead of /tmp.
old='TMP="$(mktemp "${TMPDIR:-/tmp}/srvcc-rollback-1.3.7.XXXXXX.sh")"'
new='TMP="$(mktemp "${RELEASE_DIR}/.srvcc-rollback-1.3.7.XXXXXX.sh")"'
if old not in text:
    raise SystemExit("1.3.7 inner rollback temp-path anchor missing")
text=text.replace(old,new,1)
dst.write_text(text,encoding='utf-8')
PY

[[ "$(dirname -- "$TMP")" == "$SOURCE_DIR" ]] || fail "adapted rollback escaped release directory"
chmod 0700 "$TMP"
bash "$TMP" "$@"
printf 'ROLLBACK 1.3.7 PASS: release-relative rollback chain preserved and pre-release state restored\n'
