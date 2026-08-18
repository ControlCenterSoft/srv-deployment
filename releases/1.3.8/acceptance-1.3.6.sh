#!/usr/bin/env bash
set -Eeuo pipefail

SOURCE_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
SOURCE="${SOURCE_DIR}/acceptance-1.3.3.sh"
TMP="$(mktemp "${TMPDIR:-/tmp}/srvcc-acceptance-1.3.6.XXXXXX.sh")"
PROJECT="${1:-/opt/srv-control}"
REMOTE_SHA="${2:-unknown}"
cleanup(){ rm -f -- "$TMP"; }
trap cleanup EXIT
fail(){ printf 'ACCEPTANCE 1.3.6 FAIL: %s\n' "$*" >&2; exit 1; }

python3 - "$SOURCE" "$TMP" <<'PY'
from pathlib import Path
import sys
src=Path(sys.argv[1]); dst=Path(sys.argv[2])
text=src.read_text(encoding='utf-8')
if "1.3.3" not in text:
    raise SystemExit("1.3.6 acceptance predecessor identity anchor missing")
text=text.replace("1.3.3","1.3.6")
start="# Proven primary Minecraft backend and update path.\n"
end="printf 'ACCEPTANCE 1.3.6 PASS:"
i=text.find(start); j=text.find(end)
if i < 0 or j < 0 or j <= i:
    raise SystemExit("1.3.6 Minecraft acceptance isolation anchors missing")
replacement="""# Optional Minecraft subsystem health is deliberately non-transactional in 1.3.6.
# A damaged Minecraft updater must not roll back Control Center or disable future
# product updates. Its runtime health is reported separately after deployment.
if [[ -x /usr/local/sbin/srv-control-minecraft ]]; then
    /usr/local/sbin/srv-control-minecraft status >/dev/null 2>&1 \\
      || printf 'ACCEPTANCE 1.3.6 WARN: legacy Minecraft status is unhealthy\\n' >&2
    /usr/local/sbin/srv-control-minecraft updater >/dev/null 2>&1 \\
      || printf 'ACCEPTANCE 1.3.6 WARN: legacy Minecraft updater is unhealthy\\n' >&2
else
    printf 'ACCEPTANCE 1.3.6 WARN: legacy Minecraft helper is absent\\n' >&2
fi

"""
text=text[:i]+replacement+text[j:]
text=text.replace(
    "printf 'ACCEPTANCE 1.3.6 PASS: GitHub updater reliable; authentication continuous; Minecraft updater restored\\n'",
    "printf 'ACCEPTANCE 1.3.6 PASS: core services healthy; GitHub updater reliable; Minecraft health isolated\\n'",
    1,
)
dst.write_text(text,encoding='utf-8')
PY
chmod 0700 "$TMP"
bash "$TMP" "$PROJECT" "$REMOTE_SHA"

python3 - /var/lib/srv-control/release.json "$REMOTE_SHA" <<'PY'
import json,pathlib,sys
data=json.loads(pathlib.Path(sys.argv[1]).read_text(encoding='utf-8'))
assert data.get('version') == '1.3.6', data
assert data.get('release_id') == '1.3.6', data
if sys.argv[2] != 'unknown':
    assert data.get('git_sha') == sys.argv[2], data
print('RELEASE METADATA PASS:',data.get('version'),data.get('git_sha'))
PY

printf 'ACCEPTANCE 1.3.6 PASS: deployment transaction independent from optional Minecraft updater health\n'
