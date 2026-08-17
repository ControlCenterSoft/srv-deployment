#!/usr/bin/env bash
set -Eeuo pipefail

PROJECT="${1:-/opt/srv-control}"
REMOTE_SHA="${2:-unknown}"
STATE_ROOT="/var/lib/srv-deployment"
STATUS_FILE="${STATE_ROOT}/last-result.env"
RELEASE_META="/var/lib/srv-control/release.json"
PUBLIC_STATUS="/var/lib/srv-control/deployment-status.json"

fail() {
    printf 'HEALTHCHECK FAIL: %s\n' "$*" >&2
    exit 1
}

status_value() {
    local key="$1"
    awk -F= -v key="$key" '$1 == key { sub(/^[^=]*=/, ""); print; exit }' "$STATUS_FILE"
}

systemctl is-active --quiet srv-control.service \
    || fail "srv-control.service is not active"

[[ -s "$STATUS_FILE" ]] \
    || fail "deployment status is missing: $STATUS_FILE"

result="$(status_value result)"
stage="$(status_value stage)"
release_id="$(status_value release_id)"
status_sha="$(status_value remote_sha)"
finished_at="$(status_value finished_at)"

[[ "$result" == "success" ]] \
    || fail "deployment status result is ${result:-missing}"
[[ "$stage" == "acceptance" ]] \
    || fail "deployment status stage is ${stage:-missing}"
[[ -n "$release_id" ]] \
    || fail "deployment release_id is missing"

if [[ "$REMOTE_SHA" != "unknown" ]]; then
    [[ "$status_sha" == "$REMOTE_SHA" ]] \
        || fail "deployment status SHA mismatch: status=${status_sha:-missing} expected=${REMOTE_SHA}"
fi

python3 - "$REMOTE_SHA" "$RELEASE_META" "$PUBLIC_STATUS" "$release_id" "$finished_at" <<'PY'
import json
import pathlib
import sys
import tempfile
import urllib.request
from datetime import datetime, timezone

remote_sha = sys.argv[1]
release_meta_path = pathlib.Path(sys.argv[2])
public_status_path = pathlib.Path(sys.argv[3])
release_id = sys.argv[4]
finished_at = sys.argv[5]

with urllib.request.urlopen(
    "http://127.0.0.1:8876/api/v1/health",
    timeout=5,
) as response:
    health = json.load(response)

if health.get("ok") is not True:
    raise SystemExit("application health endpoint is not OK")

release = health.get("data", {}).get("release", {})
health_sha = release.get("git_sha")

if remote_sha != "unknown" and health_sha != remote_sha:
    raise SystemExit(
        f"application release SHA mismatch: health={health_sha!r} expected={remote_sha!r}"
    )

if not release.get("version"):
    raise SystemExit("application release version is missing")
if not release.get("synced_at"):
    raise SystemExit("application release sync timestamp is missing")

if not release_meta_path.is_file():
    raise SystemExit(f"release metadata is missing: {release_meta_path}")

stored = json.loads(release_meta_path.read_text(encoding="utf-8"))
if remote_sha != "unknown" and stored.get("git_sha") != remote_sha:
    raise SystemExit("stored release metadata SHA mismatch")

payload = {
    "result": "success",
    "stage": "healthcheck",
    "release_id": release_id,
    "version": release.get("version"),
    "remote_sha": health_sha,
    "release_synced_at": release.get("synced_at"),
    "deployment_finished_at": finished_at or None,
    "healthchecked_at": datetime.now(timezone.utc).isoformat(),
}

public_status_path.parent.mkdir(parents=True, exist_ok=True)
with tempfile.NamedTemporaryFile(
    mode="w",
    encoding="utf-8",
    dir=public_status_path.parent,
    prefix=public_status_path.name + ".tmp.",
    delete=False,
) as handle:
    json.dump(payload, handle, ensure_ascii=False, indent=2)
    handle.write("\n")
    tmp_path = pathlib.Path(handle.name)

tmp_path.chmod(0o644)
tmp_path.replace(public_status_path)
PY

printf 'HEALTHCHECK PASS: release=%s sha=%s\n' "$release_id" "$REMOTE_SHA"
