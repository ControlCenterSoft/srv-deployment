#!/usr/bin/env bash
set -Eeuo pipefail

SOURCE_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
SOURCE="${SOURCE_DIR}/rollback-1.3.3.sh"
TMP="$(mktemp "${SOURCE_DIR}/.rollback-1.3.6.XXXXXX.sh")"
cleanup(){ rm -f -- "$TMP"; }
trap cleanup EXIT

python3 - "$SOURCE" "$TMP" <<'PY'
from pathlib import Path
import sys
src=Path(sys.argv[1]); dst=Path(sys.argv[2])
text=src.read_text(encoding='utf-8')
if "1.3.3" not in text:
    raise SystemExit("1.3.6 rollback predecessor identity anchor missing")
text=text.replace("1.3.3","1.3.6")
dst.write_text(text,encoding='utf-8')
PY
chmod 0700 "$TMP"
bash "$TMP" "$@"
printf 'ROLLBACK 1.3.6 PASS: pre-release state restored\n'
