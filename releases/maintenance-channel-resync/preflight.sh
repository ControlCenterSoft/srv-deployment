#!/usr/bin/env bash
set -Eeuo pipefail

PROJECT="${1:-/opt/srv-control}"
REMOTE_SHA="${2:-unknown}"
RELEASE_ID="maintenance-channel-resync"
RELEASE_META="/var/lib/srv-control/release.json"

fail() {
    printf 'PREFLIGHT FAIL: %s\n' "$*" >&2
    exit 1
}

[[ "$(id -u)" -eq 0 ]] || fail "must run as root"
[[ -d "$PROJECT" ]] || fail "project directory missing: $PROJECT"
systemctl is-active --quiet srv-control.service || fail "srv-control.service is not active"
[[ -s "$RELEASE_META" ]] || fail "current release metadata is missing"

python3 - "$RELEASE_META" <<'PY'
import json
import pathlib
import sys

path = pathlib.Path(sys.argv[1])
payload = json.loads(path.read_text(encoding="utf-8"))
if not isinstance(payload, dict):
    raise SystemExit("release metadata must be an object")
if not payload.get("version"):
    raise SystemExit("release version is missing")
if not payload.get("release_id"):
    raise SystemExit("release_id is missing")
PY

printf 'PREFLIGHT PASS: release=%s sha=%s\n' "$RELEASE_ID" "$REMOTE_SHA"
