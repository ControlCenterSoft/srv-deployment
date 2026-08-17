#!/usr/bin/env bash
set -Eeuo pipefail

PROJECT="${1:-/opt/srv-control}"
REMOTE_SHA="${2:-unknown}"
RELEASE_ID="0002-ui-release-metadata"
RELEASE_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
PAYLOAD="${RELEASE_DIR}/payload"

fail() {
    printf 'PREFLIGHT FAIL: %s\n' "$*" >&2
    exit 1
}

[[ "$(id -u)" -eq 0 ]] || fail "must run as root"
[[ -d "$PROJECT" ]] || fail "project directory missing: $PROJECT"
[[ -d "$PROJECT/app/routers" ]] || fail "app/routers missing"
[[ -d "$PROJECT/templates" ]] || fail "templates missing"
[[ -d "$PROJECT/static/js" ]] || fail "static/js missing"
[[ -d "$PROJECT/static/css" ]] || fail "static/css missing"

for path in \
    app/routers/api.py \
    templates/shell.html \
    static/js/shell.js \
    static/css/shell.css
do
    [[ -s "$PAYLOAD/$path" ]] || fail "payload file missing: $path"
done

python3 - "$PAYLOAD/app/routers/api.py" <<'PY'
import pathlib
import sys

path = pathlib.Path(sys.argv[1])
compile(path.read_text(encoding="utf-8"), str(path), "exec")
PY

grep -Fq 'id="releaseVersion"' "$PAYLOAD/templates/shell.html" \
    || fail "releaseVersion element missing"
grep -Fq 'id="githubSync"' "$PAYLOAD/templates/shell.html" \
    || fail "githubSync element missing"
grep -Fq 'release.synced_at' "$PAYLOAD/static/js/shell.js" \
    || fail "GitHub sync renderer missing"

systemctl is-active --quiet srv-control.service \
    || fail "srv-control.service is not active before deployment"

printf 'PREFLIGHT PASS: release=%s sha=%s\n' "$RELEASE_ID" "$REMOTE_SHA"
