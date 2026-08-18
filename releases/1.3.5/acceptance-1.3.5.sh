#!/usr/bin/env bash
set -Eeuo pipefail

SOURCE_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
PROJECT="${1:-/opt/srv-control}"
REMOTE_SHA="${2:-unknown}"
TMP="$(mktemp "${TMPDIR:-/tmp}/srvcc-acceptance-1.3.5.XXXXXX.sh")"
cleanup(){ rm -f -- "$TMP"; }
trap cleanup EXIT
fail(){ printf 'ACCEPTANCE 1.3.5 FAIL: %s\n' "$*" >&2; exit 1; }

python3 - "${SOURCE_DIR}/acceptance-1.3.3.sh" "$TMP" <<'PY'
from pathlib import Path
import sys
src=Path(sys.argv[1]); dst=Path(sys.argv[2])
text=src.read_text(encoding='utf-8')
text=text.replace('1.3.3','1.3.5')
text=text.replace(
    'RELEASE_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"',
    f'RELEASE_DIR="{src.parent}"',
    1,
)
dst.write_text(text,encoding='utf-8')
PY
chmod 0700 "$TMP"
bash "$TMP" "$PROJECT" "$REMOTE_SHA"

[[ -x /usr/local/sbin/srv-control-minecraft ]] || fail "legacy Minecraft helper missing after apply"
systemctl is-enabled --quiet minecraft-update.timer || fail "minecraft-update.timer is not enabled"
systemctl is-active --quiet minecraft-update.timer || fail "minecraft-update.timer is not active"

/usr/local/sbin/srv-control-minecraft status >/dev/null || fail "legacy Minecraft status failed after repair"
/usr/local/sbin/srv-control-minecraft updater >/dev/null || fail "legacy Minecraft updater status failed after repair"

mode="$(python3 - /var/lib/srv-control/github-update-config.json <<'PY'
import json,pathlib
try: data=json.loads(pathlib.Path('/var/lib/srv-control/github-update-config.json').read_text(encoding='utf-8'))
except Exception: data={}
print(str(data.get('mode') or 'automatic').strip().lower())
PY
)"
if [[ "$mode" == "automatic" ]]; then
  systemctl is-enabled --quiet srvcc-github-agent.timer || fail "automatic updater timer is not enabled"
  systemctl is-active --quiet srvcc-github-agent.timer || fail "automatic updater timer is not active"
fi

python3 - /var/lib/srv-control/release.json "$REMOTE_SHA" <<'PY'
import json,pathlib,sys
data=json.loads(pathlib.Path(sys.argv[1]).read_text(encoding='utf-8'))
assert data.get('version') == '1.3.5', data
assert data.get('release_id') in {None,'1.3.5'}, data
if sys.argv[2] != 'unknown':
    assert data.get('git_sha') == sys.argv[2], data
print('RELEASE METADATA PASS:',data.get('version'),data.get('git_sha'))
PY

printf 'ACCEPTANCE 1.3.5 PASS: repair release healthy and updater schedule preserved\n'
