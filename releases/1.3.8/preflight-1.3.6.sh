#!/usr/bin/env bash
set -Eeuo pipefail

SOURCE_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
SOURCE="${SOURCE_DIR}/preflight.sh"
TMP="$(mktemp "${SOURCE_DIR}/.preflight-1.3.6.XXXXXX.sh")"
cleanup(){ rm -f -- "$TMP"; }
trap cleanup EXIT
fail(){ printf 'PREFLIGHT 1.3.6 FAIL: %s\n' "$*" >&2; exit 1; }

python3 - "$SOURCE" "$TMP" <<'PY'
from pathlib import Path
import re, sys
src=Path(sys.argv[1]); dst=Path(sys.argv[2])
text=src.read_text(encoding='utf-8')
for old,new in [
    ('RELEASE_ID="1.3.0"','RELEASE_ID="1.3.6"'),
    ('RELEASE_VERSION="1.3.0"','RELEASE_VERSION="1.3.6"'),
    ('required 1.3.0 payload file missing','required 1.3.6 payload file missing'),
]:
    if old not in text:
        raise SystemExit(f'1.3.6 preflight patch anchor missing: {old}')
    text=text.replace(old,new,1)

pattern=r'if current < \(1,\s*2,\s*0\) or current > \(1,\s*3,\s*0\):'
replacement='if current < (1, 2, 0) or current > (1, 3, 6):'
text,count=re.subn(pattern,replacement,text,count=1)
if count != 1:
    raise SystemExit('1.3.6 preflight version-range anchor missing')

old='release 1.3.0 supports upgrade from 1.2.0 and revalidation of 1.3.0'
new='release 1.3.6 supports upgrade from 1.2.0 through 1.3.5 and revalidation of 1.3.6'
if old not in text:
    raise SystemExit(f'1.3.6 preflight message anchor missing: {old}')
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

grep -Fq 'current < (1, 2, 0) or current > (1, 3, 6)' "$TMP" \
  || fail "version-range patch was not applied"

chmod 0700 "$TMP"
bash "$TMP" "$@"
printf 'PREFLIGHT 1.3.6 PASS: core repair payload validated; optional Minecraft runtime cannot block apply\n'
