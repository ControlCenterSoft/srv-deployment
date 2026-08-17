#!/usr/bin/env bash
set -Eeuo pipefail

PROJECT="${1:-/opt/srv-control}"
REMOTE_SHA="${2:-unknown}"
RELEASE_ID="0008-system-security-admin"
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
[[ -x "$REPO_ROOT/installer/install-system-admin.sh" ]] || fail "system admin installer missing"

for command in systemctl apt-get python3; do
    command -v "$command" >/dev/null 2>&1 || fail "$command is required"
done

for path in \
    app/core/auth.py \
    app/core/system_admin.py \
    app/routers/api.py \
    templates/system.html \
    static/js/system.js \
    static/css/system-admin.css
do
    [[ -s "$PAYLOAD/$path" ]] || fail "payload file missing: $path"
done

python3 - \
    "$PAYLOAD/app/core/auth.py" \
    "$PAYLOAD/app/core/system_admin.py" \
    "$PAYLOAD/app/routers/api.py" <<'PY'
import pathlib
import sys

for value in sys.argv[1:]:
    path = pathlib.Path(value)
    compile(path.read_text(encoding="utf-8"), str(path), "exec")
PY

grep -Fq '/system/actions/{action}' "$PAYLOAD/app/routers/api.py" \
    || fail "system action API missing"
grep -Fq '/auth/login' "$PAYLOAD/app/routers/api.py" \
    || fail "administrator login API missing"
grep -Fq 'id="rebootButton"' "$PAYLOAD/templates/system.html" \
    || fail "reboot control missing"
grep -Fq 'id="manualUpdateButton"' "$PAYLOAD/templates/system.html" \
    || fail "manual update control missing"
grep -Fq 'managedServices' "$PAYLOAD/templates/system.html" \
    || fail "managed service UI missing"

systemctl is-active --quiet srv-control.service \
    || fail "srv-control.service is not active before deployment"

exec_start="$(systemctl show srv-control.service -p ExecStart --value 2>/dev/null || true)"
[[ "$exec_start" == *"--workers 2"* ]] \
    || fail "release requires multi-worker service from 0.4.0"

printf 'PREFLIGHT PASS: release=%s sha=%s\n' "$RELEASE_ID" "$REMOTE_SHA"
