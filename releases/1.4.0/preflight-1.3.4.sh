#!/usr/bin/env bash
set -Eeuo pipefail

SOURCE_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
SOURCE="${SOURCE_DIR}/preflight.sh"
TMP="$(mktemp "${SOURCE_DIR}/.preflight-1.3.4.XXXXXX.sh")"
cleanup(){ rm -f -- "$TMP"; }
trap cleanup EXIT
fail(){ printf 'PREFLIGHT 1.3.4 FAIL: %s\n' "$*" >&2; exit 1; }
warn(){ printf 'PREFLIGHT 1.3.4 WARN: %s\n' "$*" >&2; }

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

grep -Fq 'current < (1, 2, 0) or current > (1, 3, 4)' "$TMP" \
  || fail "version-range patch was not applied"

for f in \
 "$SOURCE_DIR/payload/app/routers/minecraft_legacy.py" \
 "$SOURCE_DIR/payload/static/js/minecraft.js" \
 "$SOURCE_DIR/payload/templates/minecraft.html" \
 "$SOURCE_DIR/system/sudoers-srv-control-minecraft-legacy"
do [[ -s "$f" ]] || fail "required 1.3.4 payload file missing: $f"; done

python3 -m py_compile \
 "$SOURCE_DIR/payload/app/main.py" \
 "$SOURCE_DIR/payload/app/routers/minecraft_legacy.py"

[[ -x /usr/local/sbin/srv-control-minecraft ]] || fail "proven Minecraft control helper is missing"
systemctl cat minecraft-update.service >/dev/null 2>&1 || fail "legacy minecraft-update.service is missing"
systemctl cat minecraft-update.timer >/dev/null 2>&1 || fail "legacy minecraft-update.timer is missing"

# The runtime health of the legacy updater is deliberately not a hard preflight
# gate. 1.3.4 installs/restores this exact path, so a broken pre-update status
# must not prevent the repair release from reaching apply. Acceptance remains a
# hard post-apply gate and will roll back if the helper still does not work.
if status_json="$(/usr/local/sbin/srv-control-minecraft status 2>/dev/null)"; then
    python3 - "$status_json" <<'PY' || warn "legacy Minecraft status is unhealthy before apply; continuing repair deployment"
import json,sys
data=json.loads(sys.argv[1])
raise SystemExit(0 if isinstance(data,dict) and data.get('ok') is True else 1)
PY
else
    warn "legacy Minecraft status command failed before apply; continuing repair deployment"
fi
if updater_json="$(/usr/local/sbin/srv-control-minecraft updater 2>/dev/null)"; then
    python3 - "$updater_json" <<'PY' || warn "legacy Minecraft updater status is unhealthy before apply; continuing repair deployment"
import json,sys
data=json.loads(sys.argv[1])
raise SystemExit(0 if isinstance(data,dict) and data.get('ok') is True else 1)
PY
else
    warn "legacy Minecraft updater status command failed before apply; continuing repair deployment"
fi

chmod 0700 "$TMP"
bash "$TMP" "$@"
printf 'PREFLIGHT 1.3.4 PASS: repair deployment may proceed to apply\n'
