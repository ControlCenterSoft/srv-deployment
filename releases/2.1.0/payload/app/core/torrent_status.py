from __future__ import annotations

import shutil
import subprocess


SERVICES = (
    ("qbittorrent-nox", "qBittorrent", "qbittorrent-nox.service"),
    ("deluged", "Deluge", "deluged.service"),
    ("torrserver", "TorrServer", "torrserver.service"),
)


def _unit_state(unit: str) -> str:
    try:
        result = subprocess.run(
            ["systemctl", "is-active", unit],
            capture_output=True,
            text=True,
            timeout=3,
            check=False,
        )
        return result.stdout.strip() or "inactive"
    except Exception:
        return "unknown"


def snapshot() -> dict:
    items = []
    for binary, name, unit in SERVICES:
        path = shutil.which(binary)
        state = _unit_state(unit)
        installed = bool(path) or state not in {"inactive", "unknown"}
        if installed:
            items.append(
                {
                    "id": binary,
                    "name": name,
                    "installed": True,
                    "unit": unit,
                    "state": state,
                    "binary": path,
                }
            )
    return {"services": items}
