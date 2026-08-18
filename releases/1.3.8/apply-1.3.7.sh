#!/usr/bin/env bash
set -Eeuo pipefail

SOURCE_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
SOURCE="${SOURCE_DIR}/apply-1.3.3.sh"
TMP="$(mktemp "${SOURCE_DIR}/.apply-1.3.7.XXXXXX.sh")"
PROJECT="${1:-/opt/srv-control}"
REMOTE_SHA="${2:-unknown}"
RELEASE_FILE="/var/lib/srv-control/release.json"
UPDATE_CONFIG="/var/lib/srv-control/github-update-config.json"

cleanup(){ rm -f -- "$TMP"; }
trap cleanup EXIT
fail(){ printf 'APPLY 1.3.7 FAIL: %s\n' "$*" >&2; exit 1; }
warn(){ printf 'APPLY 1.3.7 WARN: %s\n' "$*" >&2; }

python3 - "$SOURCE" "$TMP" <<'PY'
from pathlib import Path
import sys
src=Path(sys.argv[1]); dst=Path(sys.argv[2])
text=src.read_text(encoding='utf-8')
if "1.3.3" not in text:
    raise SystemExit("1.3.7 inherited apply identity anchor missing")
text=text.replace("1.3.3","1.3.7")
old='systemctl enable --now minecraft-update.timer\n'
new='systemctl enable --now minecraft-update.timer >/dev/null 2>&1 || true\n'
if old not in text:
    raise SystemExit("1.3.7 legacy timer hard-gate anchor missing")
text=text.replace(old,new,1)
old='/usr/local/sbin/srv-control-minecraft updater >/dev/null\n'
new='/usr/local/sbin/srv-control-minecraft updater >/dev/null 2>&1 || true\n'
if old not in text:
    raise SystemExit("1.3.7 legacy updater hard-gate anchor missing")
text=text.replace(old,new,1)
dst.write_text(text,encoding='utf-8')
PY
chmod 0700 "$TMP"
bash "$TMP" "$PROJECT" "$REMOTE_SHA"

systemctl disable --now srv-control-minecraft-auto-update.timer >/dev/null 2>&1 || true
if systemctl cat minecraft-update.timer >/dev/null 2>&1; then
    systemctl enable --now minecraft-update.timer >/dev/null 2>&1 \
      || warn "legacy minecraft-update.timer could not be activated"
else
    warn "legacy minecraft-update.timer is absent; Control Center update continues"
fi
if [[ -x /usr/local/sbin/srv-control-minecraft ]]; then
    /usr/local/sbin/srv-control-minecraft status >/dev/null 2>&1 \
      || warn "legacy Minecraft status is unhealthy after core apply"
    /usr/local/sbin/srv-control-minecraft updater >/dev/null 2>&1 \
      || warn "legacy Minecraft updater is unhealthy after core apply"
else
    warn "legacy Minecraft helper is absent after core apply"
fi

mode="$(python3 - "$UPDATE_CONFIG" <<'PY'
import json,pathlib,sys
try:
    data=json.loads(pathlib.Path(sys.argv[1]).read_text(encoding='utf-8'))
except Exception:
    data={}
print(str(data.get('mode') or 'automatic').strip().lower())
PY
)"
if [[ "$mode" == "automatic" ]]; then
    systemctl enable --now srvcc-github-agent.timer \
      || fail "automatic GitHub updater timer could not be restored"
else
    systemctl disable --now srvcc-github-agent.timer >/dev/null 2>&1 || true
fi

python3 - "$RELEASE_FILE" "$REMOTE_SHA" <<'PY'
import json, pathlib, sys, tempfile, os
path=pathlib.Path(sys.argv[1])
data=json.loads(path.read_text(encoding='utf-8'))
data['version']='1.3.7'
data['release_id']='1.3.7'
if sys.argv[2] and sys.argv[2] != 'unknown':
    data['git_sha']=sys.argv[2]
fd,tmp=tempfile.mkstemp(prefix='.release-1.3.7.',dir=str(path.parent))
try:
    with os.fdopen(fd,'w',encoding='utf-8') as handle:
        json.dump(data,handle,ensure_ascii=False,indent=2)
        handle.write('\n')
    os.chmod(tmp,0o640)
    os.replace(tmp,path)
finally:
    if os.path.exists(tmp):
        os.unlink(tmp)
PY

printf 'APPLY 1.3.7 PASS: core deployment completed; GitHub schedule restored; Minecraft health isolated\n'
