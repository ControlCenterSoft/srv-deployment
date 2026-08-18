#!/usr/bin/env bash
set -Eeuo pipefail

SOURCE_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../1.3.3" && pwd -P)"
PROJECT="${1:-/opt/srv-control}"
REMOTE_SHA="${2:-unknown}"
TMP="$(mktemp "${TMPDIR:-/tmp}/srvcc-acceptance-1.3.4.XXXXXX.sh")"
cleanup(){ rm -f -- "$TMP"; }
trap cleanup EXIT
fail(){ printf 'ACCEPTANCE 1.3.4 FAIL: %s\n' "$*" >&2; exit 1; }

python3 - "${SOURCE_DIR}/acceptance-1.3.3.sh" "$TMP" <<'PY'
from pathlib import Path
import sys
src=Path(sys.argv[1]); dst=Path(sys.argv[2])
text=src.read_text(encoding='utf-8')
# Base 1.3.3 acceptance expects its own installed version. 1.3.4 intentionally
# carries the identical payload, so only the release identity changes here.
text=text.replace('1.3.3','1.3.4')
# Keep all file references anchored to the frozen 1.3.3 payload/system tree.
text=text.replace(
    'RELEASE_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"',
    f'RELEASE_DIR="{src.parent}"',
    1,
)
dst.write_text(text,encoding='utf-8')
PY
chmod 0700 "$TMP"
bash "$TMP" "$PROJECT" "$REMOTE_SHA"

python3 - /var/lib/srv-control/release.json "$REMOTE_SHA" <<'PY'
import json,pathlib,sys
data=json.loads(pathlib.Path(sys.argv[1]).read_text(encoding='utf-8'))
assert data.get('version') == '1.3.4', data
assert data.get('release_id') in {None,'1.3.4'}, data
if sys.argv[2] != 'unknown':
    assert data.get('git_sha') == sys.argv[2], data
print('RELEASE METADATA PASS:',data.get('version'),data.get('git_sha'))
PY

printf 'ACCEPTANCE 1.3.4 PASS: preflight hotfix installed without payload regression\n'
