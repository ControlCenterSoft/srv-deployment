#!/usr/bin/env bash
set -Eeuo pipefail

PROJECT="${1:-/opt/srv-control}"
REMOTE_SHA="${2:-unknown}"
RELEASE_ID="0007-network-planner"
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
[[ -s "$PROJECT/app/core/network_diagnostics.py" ]] \
    || fail "network diagnostics from 0.6.0 are missing"
command -v systemctl >/dev/null 2>&1 || fail "systemctl is required"

for path in \
    app/core/network.py \
    app/core/network_plan.py \
    app/routers/api.py \
    templates/internet.html \
    static/js/internet.js \
    static/css/network.css
do
    [[ -s "$PAYLOAD/$path" ]] || fail "payload file missing: $path"
done

python3 - \
    "$PAYLOAD/app/core/network.py" \
    "$PAYLOAD/app/core/network_plan.py" \
    "$PAYLOAD/app/routers/api.py" <<'PY'
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

grep -Fq '@router.get("/network/diagnostics")' "$PAYLOAD/app/routers/api.py" \
    || fail "network diagnostics endpoint was not preserved"
grep -Fq '@router.post("/network/plan")' "$PAYLOAD/app/routers/api.py" \
    || fail "network plan endpoint missing"
grep -Fq 'apply_enabled": False' "$PAYLOAD/app/core/network_plan.py" \
    || fail "dry-run safety flag missing"
grep -Fq 'networkPlanForm' "$PAYLOAD/templates/internet.html" \
    || fail "network planner form missing"
grep -Fq 'diagnosticsGrid' "$PAYLOAD/templates/internet.html" \
    || fail "network diagnostics UI was not preserved"
grep -Fq '/api/v1/network/plan' "$PAYLOAD/static/js/internet.js" \
    || fail "network planner client missing"
grep -Fq '/api/v1/network/diagnostics' "$PAYLOAD/static/js/internet.js" \
    || fail "network diagnostics client was not preserved"
grep -Fq 'Заблокировано в 0.7.0' "$PAYLOAD/templates/internet.html" \
    || fail "apply-disabled notice missing"

systemctl is-active --quiet srv-control.service \
    || fail "srv-control.service is not active before deployment"

exec_start="$(systemctl show srv-control.service -p ExecStart --value 2>/dev/null || true)"
[[ "$exec_start" == *"--workers 2"* ]] \
    || fail "release requires multi-worker service from 0.4.0"

printf 'PREFLIGHT PASS: release=%s sha=%s\n' "$RELEASE_ID" "$REMOTE_SHA"
