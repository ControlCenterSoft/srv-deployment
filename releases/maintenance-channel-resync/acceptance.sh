#!/usr/bin/env bash
set -Eeuo pipefail

PROJECT="${1:-/opt/srv-control}"
REMOTE_SHA="${2:-unknown}"
RELEASE_ID="maintenance-channel-resync"

fail() {
    printf 'ACCEPTANCE FAIL: %s\n' "$*" >&2
    exit 1
}

systemctl is-active --quiet srv-control.service || fail "srv-control.service is not active"

python3 - "$REMOTE_SHA" <<'PY'
import json
import sys
import urllib.request

expected_sha = sys.argv[1]
with urllib.request.urlopen(
    "http://127.0.0.1:8876/api/v1/health",
    timeout=8,
) as response:
    health = json.load(response)

if health.get("ok") is not True:
    raise SystemExit("health endpoint is not OK")

release = health.get("data", {}).get("release", {})
if release.get("git_sha") != expected_sha:
    raise SystemExit(
        f"release SHA mismatch: {release.get('git_sha')!r} != {expected_sha!r}"
    )
if not release.get("version"):
    raise SystemExit("release version is missing")
if not release.get("synced_at"):
    raise SystemExit("release synced_at is missing")
PY

printf 'ACCEPTANCE PASS: maintenance resync sha=%s\n' "$REMOTE_SHA"
