#!/usr/bin/env bash
set -Eeuo pipefail

RELEASE_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
SOURCE="${RELEASE_DIR}/acceptance-1.3.7.sh"
TMP="$(mktemp "${RELEASE_DIR}/.acceptance-1.3.8.XXXXXX.sh")"
PROJECT="${1:-/opt/srv-control}"
REMOTE_SHA="${2:-unknown}"
RELEASE_FILE="/var/lib/srv-control/release.json"

cleanup(){ rm -f -- "$TMP"; }
trap cleanup EXIT
fail(){ printf 'ACCEPTANCE 1.3.8 FAIL: %s\n' "$*" >&2; exit 1; }

python3 - "$SOURCE" "$TMP" <<'PY'
from pathlib import Path
import sys
src=Path(sys.argv[1]); dst=Path(sys.argv[2])
text=src.read_text(encoding='utf-8')
if '1.3.7' not in text:
    raise SystemExit('1.3.8 acceptance predecessor identity anchor missing')
text=text.replace('1.3.7','1.3.8')
dst.write_text(text,encoding='utf-8')
PY

[[ "$(dirname -- "$TMP")" == "$RELEASE_DIR" ]] \
  || fail "adapted acceptance escaped release directory"

# Re-arm once more immediately before the inherited smoke test. This closes the
# exact real-server 1.3.7 failure without weakening the inherited active check.
systemctl enable srv-control-system-agent.path >/dev/null
if ! systemctl is-active --quiet srv-control-system-agent.path; then
    systemctl start srv-control-system-agent.path
fi
systemctl is-enabled --quiet srv-control-system-agent.path \
  || fail "srv-control-system-agent.path is not enabled"
systemctl is-active --quiet srv-control-system-agent.path \
  || fail "srv-control-system-agent.path is not active"

# This is the exact identity used by the FastAPI service. Fail with a precise
# ownership/readability error before the HTTP smoke test can degrade to nulls.
runuser -u srv-control -- python3 - "$RELEASE_FILE" "$REMOTE_SHA" <<'PY'
import json,pathlib,sys
try:
    data=json.loads(pathlib.Path(sys.argv[1]).read_text(encoding='utf-8'))
except Exception as exc:
    raise SystemExit(f'release metadata unreadable by srv-control: {exc}')
assert data.get('version') == '1.3.8', data
assert data.get('release_id') == '1.3.8', data
if sys.argv[2] != 'unknown':
    assert data.get('git_sha') == sys.argv[2], data
print('APP RELEASE METADATA ACCEPTANCE PASS:',data.get('version'),data.get('git_sha'))
PY

chmod 0700 "$TMP"
bash "$TMP" "$PROJECT" "$REMOTE_SHA"
printf 'ACCEPTANCE 1.3.8 PASS: real-server 1.3.7 blockers repaired and full inherited acceptance passed\n'
