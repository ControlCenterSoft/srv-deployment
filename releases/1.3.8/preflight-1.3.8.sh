#!/usr/bin/env bash
set -Eeuo pipefail

SOURCE_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
SOURCE="${SOURCE_DIR}/preflight.sh"
TMP="$(mktemp "${SOURCE_DIR}/.preflight-1.3.8.XXXXXX.sh")"
cleanup(){ rm -f -- "$TMP"; }
trap cleanup EXIT
fail(){ printf 'PREFLIGHT 1.3.8 FAIL: %s\n' "$*" >&2; exit 1; }

python3 - "$SOURCE" "$TMP" <<'PY'
from pathlib import Path
import re, sys
src=Path(sys.argv[1]); dst=Path(sys.argv[2])
text=src.read_text(encoding='utf-8')
for old,new in [
    ('RELEASE_ID="1.3.0"','RELEASE_ID="1.3.8"'),
    ('RELEASE_VERSION="1.3.0"','RELEASE_VERSION="1.3.8"'),
    ('required 1.3.0 payload file missing','required 1.3.8 payload file missing'),
]:
    if old not in text:
        raise SystemExit(f'1.3.8 preflight patch anchor missing: {old}')
    text=text.replace(old,new,1)

pattern=r'if current < \(1,\s*2,\s*0\) or current > \(1,\s*3,\s*0\):'
replacement='if current < (1, 2, 0) or current > (1, 3, 8):'
text,count=re.subn(pattern,replacement,text,count=1)
if count != 1:
    raise SystemExit('1.3.8 preflight version-range anchor missing')

old='release 1.3.0 supports upgrade from 1.2.0 and revalidation of 1.3.0'
new='release 1.3.8 supports upgrade from 1.2.0 through 1.3.7 and revalidation of 1.3.8'
if old not in text:
    raise SystemExit(f'1.3.8 preflight message anchor missing: {old}')
text=text.replace(old,new,1)
dst.write_text(text,encoding='utf-8')
PY

for f in \
 "$SOURCE_DIR/apply-1.3.7.sh" \
 "$SOURCE_DIR/acceptance-1.3.7.sh" \
 "$SOURCE_DIR/rollback-1.3.7.sh" \
 "$SOURCE_DIR/system/srv-control-system-agent.path" \
 "$SOURCE_DIR/payload/app/routers/api.py"
do
  [[ -s "$f" ]] || fail "required repair payload missing: $f"
done

getent group srv-control >/dev/null || fail "srv-control group is missing"
grep -Fq 'current < (1, 2, 0) or current > (1, 3, 8)' "$TMP" \
  || fail "version-range patch was not applied"

chmod 0700 "$TMP"
bash "$TMP" "$@"
printf 'PREFLIGHT 1.3.8 PASS: metadata ownership and system-agent recovery payload validated\n'
