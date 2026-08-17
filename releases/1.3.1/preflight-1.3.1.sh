#!/usr/bin/env bash
set -Eeuo pipefail

RELEASE_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
SOURCE="${RELEASE_DIR}/preflight.sh"
TMP="$(mktemp "${RELEASE_DIR}/.preflight-1.3.1.XXXXXX.sh")"
cleanup() { rm -f -- "$TMP"; }
trap cleanup EXIT

python3 - "$SOURCE" "$TMP" <<'PY'
from pathlib import Path
import sys

source = Path(sys.argv[1])
target = Path(sys.argv[2])
text = source.read_text(encoding="utf-8")
replacements = [
    ('RELEASE_ID="1.3.0"', 'RELEASE_ID="1.3.1"'),
    ('RELEASE_VERSION="1.3.0"', 'RELEASE_VERSION="1.3.1"'),
    ('required 1.3.0 payload file missing', 'required 1.3.1 payload file missing'),
    ('current < (1,2,0) or current > (1,3,0)', 'current < (1,2,0) or current > (1,3,1)'),
    ('release 1.3.0 supports upgrade from 1.2.0 and revalidation of 1.3.0',
     'release 1.3.1 supports upgrade from 1.2.0 through 1.3.0 and revalidation of 1.3.1'),
]
for old, new in replacements:
    if old not in text:
        raise SystemExit(f"preflight 1.3.1 patch anchor missing: {old}")
    text = text.replace(old, new, 1)
target.write_text(text, encoding="utf-8")
PY

chmod 0700 "$TMP"
bash "$TMP" "$@"
