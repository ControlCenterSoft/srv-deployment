#!/usr/bin/env bash
set -Eeuo pipefail

RELEASE_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
SOURCE="${RELEASE_DIR}/apply-1.3.7.sh"
TMP="$(mktemp "${RELEASE_DIR}/.apply-1.3.8.XXXXXX.sh")"
PROJECT="${1:-/opt/srv-control}"
REMOTE_SHA="${2:-unknown}"
RELEASE_FILE="/var/lib/srv-control/release.json"

cleanup(){ rm -f -- "$TMP"; }
trap cleanup EXIT
fail(){ printf 'APPLY 1.3.8 FAIL: %s\n' "$*" >&2; exit 1; }

# Preserve the complete proven 1.3.7 transaction, but make its backup and
# metadata identity 1.3.8 so rollback resolves the matching pre-release state.
python3 - "$SOURCE" "$TMP" <<'PY'
from pathlib import Path
import sys
src=Path(sys.argv[1]); dst=Path(sys.argv[2])
text=src.read_text(encoding='utf-8')
if '1.3.7' not in text:
    raise SystemExit('1.3.8 inherited apply identity anchor missing')
text=text.replace('1.3.7','1.3.8')
dst.write_text(text,encoding='utf-8')
PY
chmod 0700 "$TMP"
bash "$TMP" "$PROJECT" "$REMOTE_SHA"

# 1.3.6/1.3.7 recreated release.json as root:root 0640. The API runs as
# srv-control, so release_metadata() caught PermissionError and returned nulls.
# Recreate the file atomically with the canonical root:srv-control 0640 owner.
python3 - "$RELEASE_FILE" "$REMOTE_SHA" <<'PY'
import grp, json, os, pathlib, sys, tempfile
path=pathlib.Path(sys.argv[1])
data=json.loads(path.read_text(encoding='utf-8'))
data['version']='1.3.8'
data['release_id']='1.3.8'
if sys.argv[2] and sys.argv[2] != 'unknown':
    data['git_sha']=sys.argv[2]
gid=grp.getgrnam('srv-control').gr_gid
fd,tmp=tempfile.mkstemp(prefix='.release-1.3.8.',dir=str(path.parent))
try:
    os.fchown(fd,0,gid)
    os.fchmod(fd,0o640)
    with os.fdopen(fd,'w',encoding='utf-8') as handle:
        json.dump(data,handle,ensure_ascii=False,indent=2)
        handle.write('\n')
        handle.flush()
        os.fsync(handle.fileno())
    os.replace(tmp,path)
finally:
    if os.path.exists(tmp):
        os.unlink(tmp)
PY

# Prove the web-service identity can read exactly the metadata acceptance uses.
runuser -u srv-control -- python3 - "$RELEASE_FILE" "$REMOTE_SHA" <<'PY'
import json,pathlib,sys
data=json.loads(pathlib.Path(sys.argv[1]).read_text(encoding='utf-8'))
assert data.get('version') == '1.3.8', data
assert data.get('release_id') == '1.3.8', data
if sys.argv[2] != 'unknown':
    assert data.get('git_sha') == sys.argv[2], data
print('APP RELEASE METADATA READ PASS:',data.get('version'),data.get('git_sha'))
PY

# The real 1.3.7 automatic transaction reached acceptance with this path unit
# inactive. Re-arm the privileged action watcher after all inherited apply work.
systemctl daemon-reload
systemctl reset-failed srv-control-system-agent.service >/dev/null 2>&1 || true
systemctl enable srv-control-system-agent.path >/dev/null
if ! systemctl is-active --quiet srv-control-system-agent.path; then
    systemctl start srv-control-system-agent.path
fi
systemctl is-enabled --quiet srv-control-system-agent.path \
  || fail "srv-control-system-agent.path is not enabled after repair"
systemctl is-active --quiet srv-control-system-agent.path \
  || fail "srv-control-system-agent.path is not active after repair"

printf 'APPLY 1.3.8 PASS: release metadata readable by srv-control; system action watcher active\n'
