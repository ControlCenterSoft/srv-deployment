#!/usr/bin/env bash
set -Eeuo pipefail

PROJECT="${1:-/opt/srv-control}"
REMOTE_SHA="${2:-unknown}"
RELEASE_VERSION="0.7.0"

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


def read_json(url, method="GET", payload=None, timeout=7):
    data = None
    headers = {}

    if payload is not None:
        data = json.dumps(payload).encode("utf-8")
        headers["Content-Type"] = "application/json"

    request = urllib.request.Request(
        url,
        data=data,
        headers=headers,
        method=method,
    )

    with urllib.request.urlopen(
        request,
        timeout=timeout,
    ) as response:
        return json.load(response)


for _ in range(30):
    try:
        health = read_json(
            "http://127.0.0.1:8876/api/v1/health"
        )
        overview = read_json(
            "http://127.0.0.1:8876/api/v1/network/overview"
        )
        diagnostics = read_json(
            "http://127.0.0.1:8876/api/v1/network/diagnostics",
            timeout=20,
        )
        capabilities = read_json(
            "http://127.0.0.1:8876/api/v1/network/capabilities"
        )

        current = overview.get("data", {})
        interfaces = current.get("interfaces", [])
        wan = current.get("wan_candidate")

        lan = next(
            (
                item.get("name")
                for item in interfaces
                if item.get("name")
                and item.get("name") != "lo"
                and item.get("name") != wan
            ),
            None,
        )

        if not wan or not lan:
            raise RuntimeError(
                "acceptance requires distinct WAN/LAN candidate interfaces"
            )

        plan_request = {
            "wan_mode": "dhcp",
            "wan_interface": wan,
            "lan_interface": lan,
            "lan_address": "192.168.10.1/24",
            "dhcp_enabled": True,
            "dhcp_start": "192.168.10.100",
            "dhcp_end": "192.168.10.200",
            "dns_mode": "automatic",
            "dns_servers": [],
        }

        plan = read_json(
            "http://127.0.0.1:8876/api/v1/network/plan",
            method="POST",
            payload=plan_request,
        )

        release = health.get(
            "data",
            {},
        ).get(
            "release",
            {},
        )
        plan_data = plan.get(
            "data",
            {},
        ).get(
            "plan",
            {},
        )
        capability_data = capabilities.get(
            "data",
            {},
        )
        diagnostic_data = diagnostics.get(
            "data",
            {},
        )

        with urllib.request.urlopen(
            "http://127.0.0.1:8876/ui/module/internet",
            timeout=5,
        ) as response:
            page = response.read().decode(
                "utf-8",
                "replace",
            )

        checks = {
            "health": health.get("ok") is True,
            "overview": overview.get("ok") is True,
            "diagnostics_endpoint": diagnostics.get("ok") is True,
            "diagnostics_preserved": isinstance(
                diagnostic_data.get("checks"),
                dict,
            ),
            "capabilities": capabilities.get("ok") is True,
            "version": release.get("version") == version,
            "sha": release.get("git_sha") == sha,
            "plan_valid": plan_data.get("valid") is True,
            "apply_blocked": plan_data.get("apply_enabled") is False,
            "capability_apply_blocked": capability_data.get("apply_enabled") is False,
            "secrets_blocked": capability_data.get("secrets_enabled") is False,
            "planner_page": "Планировщик WAN / LAN" in page,
            "diagnostics_page": "Диагностика соединения" in page,
            "dry_run_notice": "Заблокировано в 0.7.0" in page,
        }

        if all(checks.values()):
            print(
                "network planner acceptance:",
                json.dumps(
                    {
                        "release": release,
                        "wan": wan,
                        "lan": lan,
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
    f"network planner did not converge: {last_error}"
)
PY

printf 'ACCEPTANCE PASS: release=%s sha=%s\n' "$RELEASE_VERSION" "$REMOTE_SHA"
