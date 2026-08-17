#!/usr/bin/env bash
set -Eeuo pipefail

PROJECT="${1:-/opt/srv-control}"
REMOTE_SHA="${2:-unknown}"
RELEASE_ID="0009-system-action-history"
RELEASE_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_ROOT="$(cd -- "${RELEASE_DIR}/../.." && pwd -P)"
PAYLOAD="${REPO_ROOT}/installer/payload"

fail() {
    printf 'PREFLIGHT FAIL: %s\n' "$*" >&2
    exit 1
}

[[ "$(id -u)" -eq 0 ]] || fail "must run as root"
[[ -d "$PROJECT" ]] || fail "project directory missing: $PROJECT"
[[ -x "$PROJECT/venv/bin/python" ]] || fail "project virtualenv is missing"
[[ -x "$REPO_ROOT/deploy/reload-srv-control.sh" ]] || fail "graceful reload helper missing"

for path in \
    app/core/system_admin.py \
    templates/system.html \
    static/js/system.js \
    static/css/system-admin.css
do
    [[ -s "$PAYLOAD/$path" ]] || fail "payload file missing: $path"
done

python3 - "$PAYLOAD/app/core/system_admin.py" <<'PY'
import pathlib
import sys
path = pathlib.Path(sys.argv[1])
compile(path.read_text(encoding="utf-8"), str(path), "exec")
PY

grep -Fq 'def action_history' "$PAYLOAD/app/core/system_admin.py" \
    || fail "action history backend missing"
grep -Fq '"actions": {' "$PAYLOAD/app/core/system_admin.py" \
    || fail "action status payload missing"
grep -Fq 'id="systemActionHistory"' "$PAYLOAD/templates/system.html" \
    || fail "action history UI missing"
grep -Fq 'renderActionHistory' "$PAYLOAD/static/js/system.js" \
    || fail "action history renderer missing"

systemctl is-active --quiet srv-control.service \
    || fail "srv-control.service is not active before deployment"

exec_start="$(systemctl show srv-control.service -p ExecStart --value 2>/dev/null || true)"
[[ "$exec_start" == *"--workers 2"* ]] \
    || fail "release requires multi-worker service from 0.4.0"

printf 'PREFLIGHT PASS: release=%s sha=%s\n' "$RELEASE_ID" "$REMOTE_SHA"
