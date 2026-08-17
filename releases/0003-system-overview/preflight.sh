#!/usr/bin/env bash
set -Eeuo pipefail

PROJECT="${1:-/opt/srv-control}"
RELEASE_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
PAYLOAD="${RELEASE_DIR}/payload"

fail() {
    printf 'PREFLIGHT FAIL: %s\n' "$*" >&2
    exit 1
}

[[ "$(id -u)" -eq 0 ]] || fail "must run as root"
[[ -d "$PROJECT" ]] || fail "project directory missing: $PROJECT"
systemctl is-active --quiet srv-control.service \
    || fail "srv-control.service is not active"

for rel in \
    app/core/metrics.py \
    app/routers/ui.py
do
    [[ -f "$PROJECT/$rel" ]] || fail "current file missing: $rel"
    [[ -f "$PAYLOAD/$rel" ]] || fail "payload file missing: $rel"
done

for rel in \
    templates/system.html \
    static/js/system.js
do
    [[ -f "$PAYLOAD/$rel" ]] || fail "payload file missing: $rel"
done

python3 -m py_compile \
    "$PAYLOAD/app/core/metrics.py" \
    "$PAYLOAD/app/routers/ui.py" \
    || fail "python syntax validation failed"

if command -v node >/dev/null 2>&1; then
    node --check "$PAYLOAD/static/js/system.js" \
        || fail "JavaScript syntax validation failed"
fi

grep -Fq '/ui/module/system' "$PAYLOAD/app/routers/ui.py" \
    || fail "system UI route is missing"
grep -Fq 'id="systemServices"' "$PAYLOAD/templates/system.html" \
    || fail "system services container is missing"

printf 'PREFLIGHT PASS: system module payload validated\n'
