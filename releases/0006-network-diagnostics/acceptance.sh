#!/usr/bin/env bash
set -Eeuo pipefail

REMOTE_SHA="${2:-unknown}"
RELEASE_VERSION="0.6.0"

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

for _ in range(30):
    try:
        with urllib.request.urlopen("http://127.0.0.1:8876/api/v1/health", timeout=5) as response:
            health = json.load(response)
        with urllib.request.urlopen("http://127.0.0.1:8876/api/v1/network/diagnostics", timeout=12) as response:
            diagnostics = json.load(response)
        with urllib.request.urlopen("http://127.0.0.1:8876/ui/module/internet", timeout=5) as response:
            page = response.read().decode("utf-8", "replace")

        release = health.get("data", {}).get("release", {})
        data = diagnostics.get("data", {})
        checks = data.get("checks", {})

        required_checks = {"route", "dns", "https"}
        checks_shape = isinstance(checks, dict) and required_checks.issubset(checks)

        assertions = {
            "health": health.get("ok") is True,
            "diagnostics_ok": diagnostics.get("ok") is True,
            "version": release.get("version") == version,
            "sha": release.get("git_sha") == sha,
            "checks_shape": checks_shape,
            "timestamp": bool(data.get("checked_at")),
            "page": "Диагностика соединения" in page,
            "grid": 'id="diagnosticsGrid"' in page,
        }

        if all(assertions.values()):
            print("network diagnostics acceptance:", json.dumps({
                "release": release,
                "summary": data.get("summary"),
                "checks": checks,
                "assertions": assertions,
            }, ensure_ascii=False))
            raise SystemExit(0)

        last_error = repr(assertions)

    except Exception as exc:
        last_error = repr(exc)

    time.sleep(1)

raise SystemExit(f"network diagnostics did not converge: {last_error}")
PY

printf 'ACCEPTANCE PASS: release=%s sha=%s\n' "$RELEASE_VERSION" "$REMOTE_SHA"
