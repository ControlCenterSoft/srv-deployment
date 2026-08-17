#!/usr/bin/env bash
set -Eeuo pipefail

PROJECT="${1:-/opt/srv-control}"
REMOTE_SHA="${2:-unknown}"
RELEASE_VERSION="0.3.0"
DIAGNOSTIC="${PROJECT}/DEPLOY_DIAGNOSTIC.txt"

fail() {
    printf 'ACCEPTANCE FAIL: %s\n' "$*" >&2
    exit 1
}

systemctl is-active --quiet srv-control.service \
    || fail "srv-control.service is not active"

if python3 - "$RELEASE_VERSION" "$REMOTE_SHA" "$DIAGNOSTIC" <<'PY'
import json
import pathlib
import sys
import time
import urllib.error
import urllib.request

version = sys.argv[1]
sha = sys.argv[2]
diagnostic = pathlib.Path(sys.argv[3])
last = {}

def get_json(url: str, timeout: int) -> dict:
    with urllib.request.urlopen(
        url,
        timeout=timeout,
    ) as response:
        return json.load(response)

def get_text(url: str, timeout: int) -> str:
    with urllib.request.urlopen(
        url,
        timeout=timeout,
    ) as response:
        return response.read().decode(
            "utf-8",
            "replace",
        )

for attempt in range(1, 31):
    try:
        health = get_json(
            "http://127.0.0.1:8876/api/v1/health",
            5,
        )
        metrics = get_json(
            "http://127.0.0.1:8876/api/v1/dashboard/metrics",
            10,
        )
        page = get_text(
            "http://127.0.0.1:8876/ui/module/system",
            5,
        )

        release = health.get("data", {}).get("release", {})
        data = metrics.get("data", {})
        system = data.get("system", {})

        checks = {
            "health_ok": health.get("ok") is True,
            "metrics_ok": metrics.get("ok") is True,
            "version": release.get("version") == version,
            "sha": release.get("git_sha") == sha,
            "synced_at": bool(release.get("synced_at")),
            "hostname": bool(system.get("hostname")),
            "kernel": bool(system.get("kernel")),
            "services": isinstance(data.get("services"), dict),
            "storage": isinstance(data.get("storage"), list),
            "page_title": "Система" in page,
            "system_js": "/static/js/system.js" in page,
        }

        last = {
            "attempt": attempt,
            "checks": checks,
            "release": release,
            "system": system,
            "page_excerpt": page[:500],
        }

        if all(checks.values()):
            diagnostic.unlink(
                missing_ok=True
            )
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

    except Exception as exc:
        last = {
            "attempt": attempt,
            "exception": repr(exc),
        }

    time.sleep(1)

diagnostic.write_text(
    json.dumps(
        last,
        ensure_ascii=False,
        indent=2,
    ) + "\n",
    encoding="utf-8",
)
raise SystemExit(
    f"system overview did not converge; diagnostic={diagnostic}"
)
PY
then
    printf 'ACCEPTANCE PASS: release=%s sha=%s\n' \
        "$RELEASE_VERSION" "$REMOTE_SHA"
    exit 0
fi

fail "system overview validation failed; see $DIAGNOSTIC"
