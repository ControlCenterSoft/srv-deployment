from __future__ import annotations

import json
from pathlib import Path
from typing import Any


STATUS_PATH = Path("/var/lib/srv-control/minecraft-instances-status.json")


def snapshot() -> dict[str, Any]:
    try:
        value = json.loads(STATUS_PATH.read_text(encoding="utf-8"))
    except Exception:
        value = None
    if isinstance(value, dict):
        return value
    return {
        "schema_version": 1,
        "checked_at": None,
        "instances": [],
        "available_ports": {"ipv4_start": 19132, "ipv6_start": 19133},
        "error": "Minecraft instance monitor has not produced a snapshot yet",
    }
