#!/usr/bin/env bash
set -Eeuo pipefail

SOURCE_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
SOURCE="${SOURCE_DIR}/preflight.sh"
TMP="$(mktemp "${SOURCE_DIR}/.preflight-1.3.7.XXXXXX.sh")"
cleanup(){ rm -f -- "$TMP"; }
trap cleanup EXIT
fail(){ printf 'PREFLIGHT 1.3.7 FAIL: %s\n' "$*" >&2; exit 1; }

python3 - "$SOURCE" "$TMP" <<'PY'
from pathlib import Path
import re, sys
src=Path(sys.argv[1]); dst=Path(sys.argv[2])
text=src.read_text(encoding='utf-8')
for old,new in [
    ('RELEASE_ID="1.3.0"','RELEASE_ID="1.3.7"'),
    ('RELEASE_VERSION="1.3.0"','RELEASE_VERSION="1.3.7"'),
    ('required 1.3.0 payload file missing','required 1.3.7 payload file missing'),
]:
    if old not in text:
        raise SystemExit(f'1.3.7 preflight patch anchor missing: {old}')
    text=text.replace(old,new,1)

pattern=r'if current < \(1,\s*2,\s*0\) or current > \(1,\s*3,\s*0\):'
replacement='if current < (1, 2, 0) or current > (1, 3, 7):'
text,count=re.subn(pattern,replacement,text,count=1)
if count != 1:
    raise SystemExit('1.3.7 preflight version-range anchor missing')

old='release 1.3.0 supports upgrade from 1.2.0 and revalidation of 1.3.0'
new='release 1.3.7 supports upgrade from 1.2.0 through 1.3.6 and revalidation of 1.3.7'
if old not in text:
    raise SystemExit(f'1.3.7 preflight message anchor missing: {old}')
text=text.replace(old,new,1)
dst.write_text(text,encoding='utf-8')
PY

for f in \
 "$SOURCE_DIR/system/srvcc-configure-auto-updates" \
 "$SOURCE_DIR/system/sudoers-srv-control-minecraft-legacy" \
 "$SOURCE_DIR/payload/app/routers/minecraft_legacy.py"
do
  [[ -s "$f" ]] || fail "required repair payload missing: $f"
done

grep -Fq 'current < (1, 2, 0) or current > (1, 3, 7)' "$TMP" \
  || fail "version-range patch was not applied"

chmod 0700 "$TMP"
bash "$TMP" "$@"
printf 'PREFLIGHT 1.3.7 PASS: core payload validated; acceptance/rollback path repair ready\n'
