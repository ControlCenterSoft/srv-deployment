#!/usr/bin/env bash
set -Eeuo pipefail

PROJECT="${1:-/opt/srv-control}"
REMOTE_SHA="${2:-unknown}"
RELEASE_ID="1.0.0"
RELEASE_VERSION="1.0.0"
RELEASE_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_ROOT="$(cd -- "${RELEASE_DIR}/../.." && pwd -P)"
PAYLOAD="${RELEASE_DIR}/payload"
SYSTEM="${RELEASE_DIR}/system"
UPDATER_CONFIG="${REPO_ROOT}/bootstrap/configure-auto-updates.sh"

fail() {
    printf 'PREFLIGHT FAIL: %s\n' "$*" >&2
    exit 1
}

[[ "$(id -u)" -eq 0 ]] || fail "must run as root"
[[ -d "$PROJECT" ]] || fail "project directory missing: $PROJECT"
[[ -x "$PROJECT/venv/bin/python" ]] || fail "project virtualenv missing"
[[ -d "$PAYLOAD/app" ]] || fail "consolidated application payload missing"
[[ -d "$PAYLOAD/templates" ]] || fail "templates payload missing"
[[ -d "$PAYLOAD/static" ]] || fail "static payload missing"
[[ -d "$PAYLOAD/migrations" ]] || fail "migrations payload missing"
[[ -s "$PAYLOAD/requirements.lock" ]] || fail "requirements.lock missing"
[[ -x "$UPDATER_CONFIG" ]] || fail "0.8+ updater configurator missing"

for name in \
    srv-control-system-agent \
    srv-control-system-agent.service \
    srv-control-system-agent.path \
    srv-control-os-update \
    srv-control-os-update.service \
    srv-control-adguard-monitor \
    srv-control-adguard-monitor.service \
    srv-control-adguard-monitor.timer
do
    [[ -s "$SYSTEM/$name" ]] || fail "system payload missing: $name"
done

for command in python3 systemctl sha256sum git flock; do
    command -v "$command" >/dev/null 2>&1 || fail "required command missing: $command"
done

systemctl is-active --quiet srv-control.service \
    || fail "srv-control.service is not active"

python3 - "$PROJECT" <<'PY'
import json
import pathlib
import re
import sys

meta = pathlib.Path("/var/lib/srv-control/release.json")
if not meta.is_file():
    raise SystemExit("installed release metadata is missing")
payload = json.loads(meta.read_text(encoding="utf-8"))
version = str(payload.get("version") or "")
m = re.match(r"^(\d+)\.(\d+)\.(\d+)(?:[-+].*)?$", version)
if not m:
    raise SystemExit(f"unsupported installed release version: {version!r}")
if tuple(map(int, m.groups())) < (0, 8, 0):
    raise SystemExit(
        f"release 1.0.0 supports in-place upgrade from 0.8.0 and newer; installed={version}"
    )

project = pathlib.Path(sys.argv[1])
for rel in (
    "app",
    "templates",
    "static",
    "migrations",
    "requirements.lock",
    "alembic.ini",
):
    if not (project / rel).exists():
        raise SystemExit(f"installed project component missing: {rel}")
PY

python3 -m compileall -q "$PAYLOAD/app"
bash -n "$UPDATER_CONFIG"

for script in \
    "$SYSTEM/srv-control-system-agent" \
    "$SYSTEM/srv-control-os-update" \
    "$SYSTEM/srv-control-adguard-monitor"
do
    bash -n "$script"
done

exec_start="$(systemctl show srv-control.service -p ExecStart --value 2>/dev/null || true)"
[[ "$exec_start" == *"--workers 2"* ]] \
    || fail "release 1.0.0 requires the multi-worker service introduced before 0.8.0"

printf 'PREFLIGHT PASS: release=%s sha=%s\n' "$RELEASE_VERSION" "$REMOTE_SHA"
