#!/usr/bin/env bash
set -Eeuo pipefail

PROJECT="${1:-/opt/srv-control}"
REMOTE_SHA="${2:-unknown}"
RELEASE_VERSION="0.5.0"

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
        with urllib.request.urlopen(
            "http://127.0.0.1:8876/api/v1/health",
            timeout=5,
        ) as response:
            health = json.load(response)

        with urllib.request.urlopen(
            "http://127.0.0.1:8876/api/v1/network/overview",
            timeout=5,
        ) as response:
            network = json.load(response)

        with urllib.request.urlopen(
            "http://127.0.0.1:8876/ui/module/internet",
            timeout=5,
        ) as response:
            page = response.read().decode(
                "utf-8",
                "replace",
            )

        release = health.get(
            "data",
            {},
        ).get(
            "release",
            {},
        )
        data = network.get(
            "data",
            {},
        )

        checks = {
            "health": health.get("ok") is True,
            "network_ok": network.get("ok") is True,
            "version": release.get("version") == version,
            "sha": release.get("git_sha") == sha,
            "sync": bool(release.get("synced_at")),
            "interfaces": isinstance(data.get("interfaces"), list),
            "dns": isinstance(data.get("dns_servers"), list),
            "lan_candidates": isinstance(data.get("lan_candidates"), list),
            "vpn_interfaces": isinstance(data.get("vpn_interfaces"), list),
            "page": "Интернет / VPN" in page,
            "client": "/static/js/internet.js" in page,
        }

        if all(checks.values()):
            print(
                "network overview acceptance:",
                json.dumps(
                    {
                        "release": release,
                        "wan_candidate": data.get("wan_candidate"),
                        "interface_count": len(data.get("interfaces", [])),
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
    f"network overview did not converge: {last_error}"
)
PY

printf 'ACCEPTANCE PASS: release=%s sha=%s\n' "$RELEASE_VERSION" "$REMOTE_SHA"
