from __future__ import annotations

import json
from pathlib import Path
from typing import Any


STATUS_PATH = Path("/var/lib/srv-control/minecraft-instances-status.json")
UPDATE_STATUS_PATH = Path("/var/lib/srv-control/minecraft-update-status.json")


def _read(path: Path) -> Any:
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except Exception:
        return None


def snapshot() -> dict[str, Any]:
    value = _read(STATUS_PATH)
    if not isinstance(value, dict):
        value = {
            "schema_version": 1,
            "checked_at": None,
            "instances": [],
            "available_ports": {"ipv4_start": 19132, "ipv6_start": 19133},
            "error": "Minecraft instance monitor has not produced a snapshot yet",
        }
    updates = _read(UPDATE_STATUS_PATH)
    update_map = updates.get("instances") if isinstance(updates, dict) else None
    if not isinstance(update_map, dict):
        update_map = {}
    instances = value.get("instances")
    if isinstance(instances, list):
        for item in instances:
            if not isinstance(item, dict):
                continue
            instance_id = str(item.get("id") or "")
            update = update_map.get(instance_id)
            item["update_status"] = update if isinstance(update, dict) else None
    return value
