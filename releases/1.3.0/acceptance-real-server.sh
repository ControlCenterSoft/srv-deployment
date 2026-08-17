#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
SOURCE="$SCRIPT_DIR/acceptance.sh"
[[ -r "$SOURCE" ]] || { echo "ACCEPTANCE HOTFIX FAIL: source acceptance.sh missing" >&2; exit 1; }

TMP="$(mktemp "${TMPDIR:-/tmp}/srvcc-acceptance-1.3.0.XXXXXX.sh")"
cleanup() { rm -f -- "$TMP"; }
trap cleanup EXIT

python3 - "$SOURCE" "$TMP" <<'PY'
from pathlib import Path
import sys

source = Path(sys.argv[1])
target = Path(sys.argv[2])
text = source.read_text(encoding="utf-8")

needle = '    [[ -s "$restored_conf" && -s "$restored_sam" ]] || fail "isolated restored domain is incomplete"\n'
insert = needle + '    mkdir -p -- "$restored/cache"\n'

if '    mkdir -p -- "$restored/cache"\n' in text:
    patched = text
elif needle in text:
    patched = text.replace(needle, insert, 1)
else:
    raise SystemExit("acceptance hotfix anchor not found; refusing unsafe patch")

target.write_text(patched, encoding="utf-8")
PY

chmod 0700 "$TMP"
set +e
bash "$TMP" "$@"
rc=$?
set -e
exit "$rc"
