#!/usr/bin/env bash
set -Eeuo pipefail

RELEASE_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
SOURCE="${RELEASE_DIR}/preflight.sh"
TMP="$(mktemp "${RELEASE_DIR}/.preflight-1.3.3.XXXXXX.sh")"
cleanup(){ rm -f -- "$TMP"; }
trap cleanup EXIT
fail(){ printf 'PREFLIGHT 1.3.3 FAIL: %s\n' "$*" >&2; exit 1; }

python3 - "$SOURCE" "$TMP" <<'PY'
from pathlib import Path
import sys
src=Path(sys.argv[1]); dst=Path(sys.argv[2]); text=src.read_text(encoding='utf-8')
repls=[
 ('RELEASE_ID="1.3.0"','RELEASE_ID="1.3.3"'),
 ('RELEASE_VERSION="1.3.0"','RELEASE_VERSION="1.3.3"'),
 ('required 1.3.0 payload file missing','required 1.3.3 payload file missing'),
 ('current < (1,2,0) or current > (1,3,0)','current < (1,2,0) or current > (1,3,3)'),
 ('release 1.3.0 supports upgrade from 1.2.0 and revalidation of 1.3.0',
  'release 1.3.3 supports upgrade from 1.2.0 through 1.3.2 and revalidation of 1.3.3'),
]
for old,new in repls:
    if old not in text: raise SystemExit(f'1.3.3 preflight patch anchor missing: {old}')
    text=text.replace(old,new,1)
dst.write_text(text,encoding='utf-8')
PY

for f in \
 "$RELEASE_DIR/payload/app/routers/minecraft_legacy.py" \
 "$RELEASE_DIR/payload/static/js/minecraft.js" \
 "$RELEASE_DIR/payload/templates/minecraft.html" \
 "$RELEASE_DIR/system/sudoers-srv-control-minecraft-legacy"
do [[ -s "$f" ]] || fail "required file missing: $f"; done

python3 -m py_compile "$RELEASE_DIR/payload/app/main.py" "$RELEASE_DIR/payload/app/routers/minecraft_legacy.py"

# 1.3.3 deliberately returns the primary Bedrock server to the proven pre-1.3 path.
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
