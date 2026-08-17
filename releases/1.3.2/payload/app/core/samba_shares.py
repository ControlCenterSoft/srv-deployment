from __future__ import annotations

import json
from pathlib import Path
from typing import Any


STATUS_PATH = Path("/var/lib/srv-control/samba-shares-status.json")


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
        "installed": False,
        "shares": [],
        "quota_backends": {},
        "error": "Samba shares monitor has not produced a snapshot yet",
    }
