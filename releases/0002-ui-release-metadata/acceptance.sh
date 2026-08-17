#!/usr/bin/env bash
set -Eeuo pipefail

PROJECT="${1:-/opt/srv-control}"
REMOTE_SHA="${2:-unknown}"
RELEASE_VERSION="0.2.0"
RELEASE_META="/var/lib/srv-control/release.json"

fail() {
    printf 'ACCEPTANCE FAIL: %s\n' "$*" >&2
    exit 1
}

systemctl is-active --quiet srv-control.service \
    || fail "srv-control.service is not active"

python3 - "$RELEASE_VERSION" "$REMOTE_SHA" <<'PY'
import json
import sys
import time
import urllib.request

version = sys.argv[1]
sha = sys.argv[2]
last_error = None

for _ in range(20):
    try:
        with urllib.request.urlopen(
            "http://127.0.0.1:8876/api/v1/health",
            timeout=2,
        ) as response:
            payload = json.load(response)

        release = payload.get("data", {}).get("release", {})

        if (
            payload.get("ok") is True
            and release.get("version") == version
            and release.get("git_sha") == sha
            and release.get("synced_at")
        ):
            print(
                "health release metadata:",
                json.dumps(release, ensure_ascii=False),
            )
            raise SystemExit(0)

        last_error = f"unexpected payload: {payload!r}"

    except Exception as exc:
        last_error = repr(exc)

    time.sleep(1)

raise SystemExit(
    f"health metadata did not converge: {last_error}"
)
PY

grep -Fq 'id="releaseVersion"' "$PROJECT/templates/shell.html" \
    || fail "release version UI missing"
grep -Fq 'id="githubSync"' "$PROJECT/templates/shell.html" \
    || fail "GitHub sync UI missing"
grep -Fq 'GitHub:' "$PROJECT/static/js/shell.js" \
    || fail "GitHub sync JavaScript missing"

python3 - "$RELEASE_META" "$RELEASE_VERSION" "$REMOTE_SHA" <<'PY'
import json
import pathlib
import sys

payload = json.loads(
    pathlib.Path(sys.argv[1]).read_text(encoding="utf-8")
)

if payload.get("version") != sys.argv[2]:
    raise SystemExit("release metadata version mismatch")

if payload.get("git_sha") != sys.argv[3]:
    raise SystemExit("release metadata SHA mismatch")

if not payload.get("synced_at"):
    raise SystemExit("release metadata sync timestamp missing")
PY

printf 'ACCEPTANCE PASS: release=%s sha=%s\n' "$RELEASE_VERSION" "$REMOTE_SHA"
