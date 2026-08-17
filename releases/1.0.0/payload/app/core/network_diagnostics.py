from __future__ import annotations

from datetime import datetime, timezone
import socket
import time
import urllib.request

from app.core.network import snapshot as network_snapshot


DIAGNOSTIC_HOST = "github.com"
DIAGNOSTIC_URL = "https://github.com/"


def _timed(callable_):
    started = time.monotonic()

    try:
        detail = callable_()
        elapsed = round(
            (time.monotonic() - started) * 1000,
            1,
        )

        return {
            "ok": True,
            "latency_ms": elapsed,
            "detail": detail,
            "error": None,
        }

    except Exception as exc:
        elapsed = round(
            (time.monotonic() - started) * 1000,
            1,
        )

        return {
            "ok": False,
            "latency_ms": elapsed,
            "detail": None,
            "error": str(exc)[:240],
        }


def _route_check() -> str:
    route = network_snapshot().get(
        "default_route"
    )

    if not route:
        raise RuntimeError(
            "IPv4 default route is absent"
        )

    interface = route.get(
        "interface"
    ) or "unknown"
    gateway = route.get(
        "gateway"
    ) or "unknown"

    return (
        f"{interface} via {gateway}"
    )


def _dns_check() -> str:
    addresses = []

    for item in socket.getaddrinfo(
        DIAGNOSTIC_HOST,
        443,
        type=socket.SOCK_STREAM,
    ):
        value = item[4][0]

        if value not in addresses:
            addresses.append(value)

    if not addresses:
        raise RuntimeError(
            "DNS returned no addresses"
        )

    return ", ".join(
        addresses[:4]
    )


def _https_check() -> str:
    request = urllib.request.Request(
        DIAGNOSTIC_URL,
        method="HEAD",
        headers={
            "User-Agent": (
                "SRV-Control-Center/0.6 network-diagnostics"
            ),
        },
    )

    with urllib.request.urlopen(
        request,
        timeout=6,
    ) as response:
        status = int(
            getattr(
                response,
                "status",
                0,
            )
        )

    if status < 200 or status >= 500:
        raise RuntimeError(
            f"unexpected HTTP status {status}"
        )

    return f"HTTP {status}"


def run() -> dict:
    checks = {
        "route": _timed(
            _route_check
        ),
        "dns": _timed(
            _dns_check
        ),
        "https": _timed(
            _https_check
        ),
    }

    passed = sum(
        1
        for item in checks.values()
        if item.get("ok") is True
    )

    return {
        "checked_at": datetime.now(
            timezone.utc
        ).isoformat(),
        "target": DIAGNOSTIC_HOST,
        "summary": {
            "passed": passed,
            "total": len(checks),
            "ok": passed == len(checks),
        },
        "checks": checks,
    }
