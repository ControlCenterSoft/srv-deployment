#!/usr/bin/env bash
set -Eeuo pipefail

PROJECT="${1:-/opt/srv-control}"
REMOTE_SHA="${2:-unknown}"
RELEASE_VERSION="0.4.0"

fail() {
    printf 'ACCEPTANCE FAIL: %s\n' "$*" >&2
    exit 1
}

systemctl is-active --quiet srv-control.service \
    || fail "srv-control.service is not active"

exec_start="$(systemctl show srv-control.service -p ExecStart --value 2>/dev/null || true)"
[[ "$exec_start" == *"--workers 2"* ]] \
    || fail "srv-control.service is not running with two Uvicorn workers"

python3 - "$RELEASE_VERSION" "$REMOTE_SHA" <<'PY'
import json
import sys
import time
import urllib.request

version = sys.argv[1]
sha = sys.argv[2]
last_error = None

for _ in range(30):
    try:
        with urllib.request.urlopen(
            "http://127.0.0.1:8876/api/v1/health",
            timeout=5,
        ) as response:
            health = json.load(response)

        with urllib.request.urlopen(
            "http://127.0.0.1:8876/api/v1/dashboard/metrics",
            timeout=10,
        ) as response:
            metrics = json.load(response)

        with urllib.request.urlopen(
            "http://127.0.0.1:8876/ui/module/system",
            timeout=5,
        ) as response:
            page = response.read().decode("utf-8", "replace")

        release = health.get("data", {}).get("release", {})
        deployment = health.get("data", {}).get("deployment", {})

        checks = {
            "health": health.get("ok") is True,
            "metrics": metrics.get("ok") is True,
            "version": release.get("version") == version,
            "sha": release.get("git_sha") == sha,
            "sync": bool(release.get("synced_at")),
            "deployment_dict": isinstance(deployment, dict),
            "system_page": "Канал обновлений" in page,
            "deployment_ui": 'id="deploymentResult"' in page,
        }

        if all(checks.values()):
            print(
                "deployment reliability acceptance:",
                json.dumps(
                    {
                        "release": release,
                        "checks": checks,
                    },
                    ensure_ascii=False,
                ),
            )
            raise SystemExit(0)

        last_error = repr(checks)

    except Exception as exc:
        last_error = repr(exc)

    time.sleep(1)

raise SystemExit(
    f"deployment reliability did not converge: {last_error}"
)
PY

printf 'ACCEPTANCE PASS: release=%s sha=%s\n' "$RELEASE_VERSION" "$REMOTE_SHA"
