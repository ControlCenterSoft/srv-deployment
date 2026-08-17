#!/usr/bin/env bash
set -Eeuo pipefail

RELEASE_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
SOURCE="${RELEASE_DIR}/preflight.sh"
TMP="$(mktemp "${RELEASE_DIR}/.preflight-1.3.2.XXXXXX.sh")"
cleanup() { rm -f -- "$TMP"; }
trap cleanup EXIT

python3 - "$SOURCE" "$TMP" <<'PY'
from pathlib import Path
import sys

source = Path(sys.argv[1])
target = Path(sys.argv[2])
text = source.read_text(encoding="utf-8")
replacements = [
    ('RELEASE_ID="1.3.0"', 'RELEASE_ID="1.3.2"'),
    ('RELEASE_VERSION="1.3.0"', 'RELEASE_VERSION="1.3.2"'),
    ('required 1.3.0 payload file missing', 'required 1.3.2 payload file missing'),
    ('current < (1,2,0) or current > (1,3,0)', 'current < (1,2,0) or current > (1,3,2)'),
    ('release 1.3.0 supports upgrade from 1.2.0 and revalidation of 1.3.0',
     'release 1.3.2 supports upgrade from 1.2.0 through 1.3.1 and revalidation of 1.3.2'),
]
for old, new in replacements:
    if old not in text:
        raise SystemExit(f"preflight 1.3.2 patch anchor missing: {old}")
    text = text.replace(old, new, 1)
target.write_text(text, encoding="utf-8")
PY

for required in \
    "$RELEASE_DIR/payload/app/routers/minecraft_legacy.py" \
    "$RELEASE_DIR/payload/static/js/minecraft.js" \
    "$RELEASE_DIR/payload/static/css/minecraft-1.3.2.css" \
    "$RELEASE_DIR/payload/templates/minecraft.html" \
    "$RELEASE_DIR/system/sudoers-srv-control-minecraft-legacy"
do
    [[ -s "$required" ]] || { echo "PREFLIGHT FAIL: required 1.3.2 Minecraft file missing: $required" >&2; exit 1; }
done

python3 -m py_compile "$RELEASE_DIR/payload/app/main.py" "$RELEASE_DIR/payload/app/routers/minecraft_legacy.py"

chmod 0700 "$TMP"
bash "$TMP" "$@"
