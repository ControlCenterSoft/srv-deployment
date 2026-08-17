#!/usr/bin/env bash
set -Eeuo pipefail

PROJECT="${1:-/opt/srv-control}"
REMOTE_SHA="${2:-unknown}"
RELEASE_ID="0005-network-overview"
RELEASE_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
PAYLOAD="${RELEASE_DIR}/payload"
REPO_ROOT="$(cd -- "${RELEASE_DIR}/../.." && pwd -P)"
RELOAD_HELPER="${REPO_ROOT}/deploy/reload-srv-control.sh"

fail() {
    printf 'PREFLIGHT FAIL: %s\n' "$*" >&2
    exit 1
}

[[ "$(id -u)" -eq 0 ]] || fail "must run as root"
[[ -d "$PROJECT" ]] || fail "project directory missing: $PROJECT"
[[ -x "$PROJECT/venv/bin/python" ]] || fail "project virtualenv is missing"
[[ -x "$RELOAD_HELPER" ]] || fail "graceful reload helper is missing"
command -v systemctl >/dev/null 2>&1 || fail "systemctl is required"

for path in \
    app/core/network.py \
    app/routers/api.py \
    app/routers/ui.py \
    templates/internet.html \
    static/js/internet.js
do
    [[ -s "$PAYLOAD/$path" ]] || fail "payload file missing: $path"
done

python3 - \
    "$PAYLOAD/app/core/network.py" \
    "$PAYLOAD/app/routers/api.py" \
    "$PAYLOAD/app/routers/ui.py" <<'PY'
import pathlib
import sys

for value in sys.argv[1:]:
    path = pathlib.Path(value)
    compile(
        path.read_text(encoding="utf-8"),
        str(path),
        "exec",
    )
PY

grep -Fq '@router.get("/network/overview")' "$PAYLOAD/app/routers/api.py" \
    || fail "network overview endpoint missing"
grep -Fq 'name="internet.html"' "$PAYLOAD/app/routers/ui.py" \
    || fail "internet module route missing"
grep -Fq 'id="networkInterfaces"' "$PAYLOAD/templates/internet.html" \
    || fail "network interface UI missing"
grep -Fq '/api/v1/network/overview' "$PAYLOAD/static/js/internet.js" \
    || fail "network overview client missing"

"$PROJECT/venv/bin/python" - <<'PY'
import psutil
assert psutil.net_if_addrs()
PY

systemctl is-active --quiet srv-control.service \
    || fail "srv-control.service is not active before deployment"

exec_start="$(systemctl show srv-control.service -p ExecStart --value 2>/dev/null || true)"
[[ "$exec_start" == *"--workers 2"* ]] \
    || fail "release requires the multi-worker service from 0.4.0"

printf 'PREFLIGHT PASS: release=%s sha=%s\n' "$RELEASE_ID" "$REMOTE_SHA"
