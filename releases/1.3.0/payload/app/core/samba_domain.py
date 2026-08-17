from __future__ import annotations

import json
from pathlib import Path
from typing import Any


STATUS_PATH = Path("/var/lib/srv-control/samba-domain-status.json")
BACKUP_DIR = Path("/var/lib/srv-control/domain-backups")


def _read_json(path: Path) -> dict[str, Any] | None:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except Exception:
        return None
    return value if isinstance(value, dict) else None


def snapshot() -> dict[str, Any]:
    value = _read_json(STATUS_PATH)
    if value is None:
        return {
            "schema_version": 1,
            "installed": False,
            "state": "unknown",
            "checked_at": None,
            "domain": {},
            "password_policy": {},
            "users": [],
            "groups": [],
            "replication": {},
            "error": "Samba domain monitor has not produced a snapshot yet",
        }
    return value


def backup_items() -> list[dict[str, Any]]:
    items: list[dict[str, Any]] = []
    if not BACKUP_DIR.is_dir():
        return items
    for metadata_path in sorted(
        BACKUP_DIR.glob("*.json"),
        key=lambda item: item.stat().st_mtime,
        reverse=True,
    ):
        metadata = _read_json(metadata_path)
        if not metadata:
            continue
        archive_name = str(metadata.get("archive") or "")
        archive = BACKUP_DIR / archive_name
        if not archive.is_file():
            continue
        item = dict(metadata)
        item["size"] = archive.stat().st_size
        item["download_url"] = f"/api/v1/samba/backups/{metadata_path.stem}/download"
        items.append(item)
    return items


def backup_archive(backup_id: str) -> Path | None:
    if not backup_id or any(
        ch not in "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_"
        for ch in backup_id
    ):
        return None
    metadata = _read_json(BACKUP_DIR / f"{backup_id}.json")
    if not metadata:
        return None
    archive = BACKUP_DIR / str(metadata.get("archive") or "")
    try:
        archive = archive.resolve(strict=True)
        root = BACKUP_DIR.resolve(strict=True)
    except Exception:
        return None
    if root not in archive.parents or not archive.is_file():
        return None
    return archive
