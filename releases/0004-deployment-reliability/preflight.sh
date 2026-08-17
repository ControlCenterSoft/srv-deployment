#!/usr/bin/env bash
set -Eeuo pipefail

PROJECT="${1:-/opt/srv-control}"
REMOTE_SHA="${2:-unknown}"
RELEASE_ID="0004-deployment-reliability"
RELEASE_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
PAYLOAD="${RELEASE_DIR}/payload"

fail() {
    printf 'PREFLIGHT FAIL: %s\n' "$*" >&2
    exit 1
}

[[ "$(id -u)" -eq 0 ]] || fail "must run as root"
[[ -d "$PROJECT" ]] || fail "project directory missing: $PROJECT"
[[ -x "$PROJECT/venv/bin/python" ]] || fail "project virtualenv is missing"
command -v systemctl >/dev/null 2>&1 || fail "systemctl is required"

for path in \
    app/routers/api.py \
    templates/system.html \
    static/js/system.js \
    systemd/srv-control.service
do
    [[ -s "$PAYLOAD/$path" ]] || fail "payload file missing: $path"
done

python3 - "$PAYLOAD/app/routers/api.py" <<'PY'
import pathlib
import sys

path = pathlib.Path(sys.argv[1])
compile(path.read_text(encoding="utf-8"), str(path), "exec")
PY

grep -Fq 'id="deploymentResult"' "$PAYLOAD/templates/system.html" \
    || fail "deploymentResult UI element missing"
grep -Fq 'healthData.deployment' "$PAYLOAD/static/js/system.js" \
    || fail "deployment status renderer missing"
grep -Fq -- '--workers 2' "$PAYLOAD/systemd/srv-control.service" \
    || fail "multi-worker systemd unit is missing"

"$PROJECT/venv/bin/python" -m uvicorn --help 2>&1 \
    | grep -Fq -- '--workers' \
    || fail "installed Uvicorn does not support workers"

systemctl is-active --quiet srv-control.service \
    || fail "srv-control.service is not active before deployment"

printf 'PREFLIGHT PASS: release=%s sha=%s\n' "$RELEASE_ID" "$REMOTE_SHA"
