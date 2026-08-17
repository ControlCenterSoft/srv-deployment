#!/usr/bin/env bash
set -Eeuo pipefail

PROJECT="${1:-/opt/srv-control}"
REMOTE_SHA="${2:-unknown}"
RELEASE_VERSION="0.3.0"

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
            health = json.load(response)

        with urllib.request.urlopen(
            "http://127.0.0.1:8876/api/v1/dashboard/metrics",
            timeout=4,
        ) as response:
            metrics = json.load(response)

        with urllib.request.urlopen(
            "http://127.0.0.1:8876/ui/module/system",
            timeout=2,
        ) as response:
            page = response.read().decode("utf-8", "replace")

        release = health.get("data", {}).get("release", {})
        system = metrics.get("data", {}).get("system", {})

        if (
            health.get("ok") is True
            and metrics.get("ok") is True
            and release.get("version") == version
            and release.get("git_sha") == sha
            and release.get("synced_at")
            and system.get("hostname")
            and system.get("kernel")
            and isinstance(metrics.get("data", {}).get("services"), dict)
            and isinstance(metrics.get("data", {}).get("storage"), list)
            and "Система" in page
            and "/static/js/system.js" in page
        ):
            print(
                "system overview acceptance:",
                json.dumps(
                    {
                        "release": release,
                        "system": system,
                    },
                    ensure_ascii=False,
                ),
            )
            raise SystemExit(0)

        last_error = (
            f"unexpected health={health!r} metrics={metrics!r}"
        )

    except Exception as exc:
        last_error = repr(exc)

    time.sleep(1)

raise SystemExit(
    f"system overview did not converge: {last_error}"
)
PY

printf 'ACCEPTANCE PASS: release=%s sha=%s\n' \
    "$RELEASE_VERSION" "$REMOTE_SHA"
