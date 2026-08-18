#!/usr/bin/env bash
set -Eeuo pipefail

SOURCE_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
PROJECT="${1:-/opt/srv-control}"
REMOTE_SHA="${2:-unknown}"
RELEASE_FILE="/var/lib/srv-control/release.json"
UPDATE_CONFIG="/var/lib/srv-control/github-update-config.json"

bash "${SOURCE_DIR}/apply-1.3.4.sh" "$PROJECT" "$REMOTE_SHA"

systemctl daemon-reload

[[ -x /usr/local/sbin/srv-control-minecraft ]] || {
  printf 'APPLY 1.3.5 FAIL: legacy Minecraft helper was not restored\n' >&2
  exit 1
}
systemctl cat minecraft-update.service >/dev/null 2>&1 || {
  printf 'APPLY 1.3.5 FAIL: minecraft-update.service was not restored\n' >&2
  exit 1
}
systemctl cat minecraft-update.timer >/dev/null 2>&1 || {
  printf 'APPLY 1.3.5 FAIL: minecraft-update.timer was not restored\n' >&2
  exit 1
}
systemctl enable --now minecraft-update.timer
systemctl disable --now srv-control-minecraft-auto-update.timer >/dev/null 2>&1 || true

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
  systemctl enable --now srvcc-github-agent.timer
fi

python3 - "$RELEASE_FILE" "$REMOTE_SHA" <<'PY'
import json, pathlib, sys, tempfile, os
path=pathlib.Path(sys.argv[1])
data=json.loads(path.read_text(encoding='utf-8'))
data['version']='1.3.5'
data['release_id']='1.3.5'
if sys.argv[2] and sys.argv[2] != 'unknown':
    data['git_sha']=sys.argv[2]
fd,tmp=tempfile.mkstemp(prefix='.release-1.3.5.',dir=str(path.parent))
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

printf 'APPLY 1.3.5 PASS: legacy updater repaired and automatic GitHub timer restored when configured\n'
