#!/usr/bin/env bash
set -Eeuo pipefail

SOURCE_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../1.3.3" && pwd -P)"
SOURCE="${SOURCE_DIR}/preflight.sh"
TMP="$(mktemp "${SOURCE_DIR}/.preflight-1.3.4.XXXXXX.sh")"
cleanup(){ rm -f -- "$TMP"; }
trap cleanup EXIT
fail(){ printf 'PREFLIGHT 1.3.4 FAIL: %s\n' "$*" >&2; exit 1; }

python3 - "$SOURCE" "$TMP" <<'PY'
from pathlib import Path
import re, sys
src=Path(sys.argv[1]); dst=Path(sys.argv[2])
text=src.read_text(encoding='utf-8')
for old,new in [
    ('RELEASE_ID="1.3.0"','RELEASE_ID="1.3.4"'),
    ('RELEASE_VERSION="1.3.0"','RELEASE_VERSION="1.3.4"'),
    ('required 1.3.0 payload file missing','required 1.3.4 payload file missing'),
]:
    if old not in text:
        raise SystemExit(f'1.3.4 preflight patch anchor missing: {old}')
    text=text.replace(old,new,1)

pattern=r'if current < \(1,\s*2,\s*0\) or current > \(1,\s*3,\s*0\):'
replacement='if current < (1, 2, 0) or current > (1, 3, 4):'
text,count=re.subn(pattern,replacement,text,count=1)
if count != 1:
    raise SystemExit('1.3.4 preflight version-range anchor missing')

old='release 1.3.0 supports upgrade from 1.2.0 and revalidation of 1.3.0'
new='release 1.3.4 supports upgrade from 1.2.0 through 1.3.3 and revalidation of 1.3.4'
if old not in text:
    raise SystemExit(f'1.3.4 preflight message anchor missing: {old}')
text=text.replace(old,new,1)
dst.write_text(text,encoding='utf-8')
PY

# Regression guard for the exact formatting that broke 1.3.3.
grep -Fq 'current < (1, 2, 0) or current > (1, 3, 4)' "$TMP" \
  || fail "version-range patch was not applied"

for f in \
 "$SOURCE_DIR/payload/app/routers/minecraft_legacy.py" \
 "$SOURCE_DIR/payload/static/js/minecraft.js" \
 "$SOURCE_DIR/payload/templates/minecraft.html" \
 "$SOURCE_DIR/system/sudoers-srv-control-minecraft-legacy"
do [[ -s "$f" ]] || fail "required 1.3.3 payload file missing: $f"; done

python3 -m py_compile \
 "$SOURCE_DIR/payload/app/main.py" \
 "$SOURCE_DIR/payload/app/routers/minecraft_legacy.py"

[[ -x /usr/local/sbin/srv-control-minecraft ]] || fail "proven Minecraft control helper is missing"
systemctl cat minecraft-update.service >/dev/null 2>&1 || fail "legacy minecraft-update.service is missing"
systemctl cat minecraft-update.timer >/dev/null 2>&1 || fail "legacy minecraft-update.timer is missing"

status_json="$(/usr/local/sbin/srv-control-minecraft status)" || fail "legacy Minecraft status command failed"
updater_json="$(/usr/local/sbin/srv-control-minecraft updater)" || fail "legacy Minecraft updater status command failed"
python3 - "$status_json" "$updater_json" <<'PY'
import json,sys
for label,raw in [('status',sys.argv[1]),('updater',sys.argv[2])]:
    data=json.loads(raw)
    if not isinstance(data,dict) or data.get('ok') is not True:
        raise SystemExit(f'legacy Minecraft {label} did not return ok=true: {data!r}')
print('MINECRAFT LEGACY PREFLIGHT PASS')
PY

chmod 0700 "$TMP"
bash "$TMP" "$@"
printf 'PREFLIGHT 1.3.4 PASS: robust version-range patch validated\n'
