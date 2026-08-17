from __future__ import annotations

import json
import os
from pathlib import Path
import shutil
import subprocess
import uuid


ACTION_DIR = Path("/var/lib/srv-control/system-actions")
RESULT_DIR = Path("/var/lib/srv-control/system-results")
GITHUB_CONFIG = Path("/var/lib/srv-control/github-update-config.json")
GITHUB_STATUS = Path("/var/lib/srv-control/github-update-status.json")
OS_UPDATE_CONFIG = Path("/var/lib/srv-control/os-update-config.json")
OS_UPDATE_STATUS = Path("/var/lib/srv-control/os-update-status.json")
BACKUP_CONFIG = Path("/var/lib/srv-control/backup-config.json")
BACKUP_DIR = Path("/var/lib/srv-control/backups")
ADGUARD_STATUS = Path("/var/lib/srv-control/adguard-vpn-status.json")

ALLOWED_ACTIONS = {
    "reboot",
    "github-update-config",
    "github-check",
    "github-update",
    "os-update-config",
    "os-update",
    "backup-config",
    "backup-create",
    "backup-delete",
    "backup-restore",
    "service-install-adguard-vpn",
    "service-remove-adguard-vpn",
    "service-refresh-adguard-vpn",
    "service-connect-adguard-vpn-socks",
    "service-disconnect-adguard-vpn",
    "service-update-adguard-vpn",
    "service-install-pxe",
    "service-remove-pxe",
}


def _read_json(path: Path) -> dict | None:
    try:
        payload = json.loads(path.read_text(encoding="utf-8"))
        if isinstance(payload, dict):
            return payload
    except Exception:
        pass
    return None


def _unit_state(name: str) -> str:
    try:
        result = subprocess.run(
            ["systemctl", "is-active", name],
            capture_output=True,
            text=True,
            timeout=3,
            check=False,
        )
        return result.stdout.strip() or "inactive"
    except Exception:
        return "unknown"


def _package_installed(name: str) -> bool:
    try:
        result = subprocess.run(
            ["dpkg-query", "-W", "-f=${Status}", name],
            capture_output=True,
            text=True,
            timeout=4,
            check=False,
        )
        return result.returncode == 0 and result.stdout.strip() == "install ok installed"
    except Exception:
        return False


def _adguard_binary() -> str | None:
    binary = shutil.which("adguardvpn-cli")
    if binary:
        return binary
    path = Path("/opt/adguardvpn_cli/adguardvpn-cli")
    return str(path) if path.exists() else None


def service_catalog(*, include_detail: bool = False) -> list[dict]:
    binary = _adguard_binary()
    monitor = _read_json(ADGUARD_STATUS) or {}
    adguard_installed = bool(binary)
    adguard_status = {
        "state": monitor.get("state") if adguard_installed else "not-installed",
        "version": monitor.get("version") if adguard_installed else None,
        "mode": monitor.get("mode") if adguard_installed else None,
        "socks_host": monitor.get("socks_host") if adguard_installed else None,
        "socks_port": monitor.get("socks_port") if adguard_installed else None,
        "checked_at": monitor.get("checked_at") if adguard_installed else None,
    }
    if include_detail and adguard_installed:
        adguard_status["detail"] = monitor.get("detail")

    pxe_installed = _package_installed("tftpd-hpa") or shutil.which("in.tftpd") is not None
    return [
        {
            "id": "adguard-vpn",
            "name": "AdGuard VPN",
            "installed": adguard_installed,
            "description": "AdGuard VPN CLI",
            "permission_module": "network",
            "status": adguard_status,
        },
        {
            "id": "pxe-server",
            "name": "PXE Server",
            "installed": pxe_installed,
            "description": "TFTP/iPXE network boot service",
            "permission_module": "pxe",
            "status": {
                "state": _unit_state("tftpd-hpa.service") if pxe_installed else "not-installed",
                "tftp_root": "/srv/tftp" if Path("/srv/tftp").exists() else None,
            },
        },
    ]


def backups() -> list[dict]:
    items: list[dict] = []
    if not BACKUP_DIR.is_dir():
        return items
    for metadata_path in sorted(BACKUP_DIR.glob("*.json"), key=lambda path: path.stat().st_mtime, reverse=True):
        payload = _read_json(metadata_path)
        if not payload:
            continue
        archive_name = str(payload.get("archive") or "")
        archive = BACKUP_DIR / archive_name
        if not archive.is_file():
            continue
        item = dict(payload)
        item["size"] = archive.stat().st_size
        item["download_url"] = f"/api/v1/system/backups/{payload.get('id')}/download"
        items.append(item)
    return items


def action_queue(limit: int = 20) -> list[dict]:
    items: list[dict] = []
    try:
        paths = sorted(ACTION_DIR.glob("*.json"), key=lambda item: item.stat().st_mtime)
        for path in paths[: max(0, min(limit, 50))]:
            payload = _read_json(path)
            if payload:
                items.append({
                    "request_id": payload.get("request_id") or path.stem,
                    "action": payload.get("action"),
                    "actor": payload.get("actor"),
                    "queued": True,
                })
    except Exception:
        pass
    return items


def action_history(limit: int = 30) -> list[dict]:
    items: list[dict] = []
    try:
        paths = sorted(RESULT_DIR.glob("*.json"), key=lambda item: item.stat().st_mtime, reverse=True)
        for path in paths[: max(0, min(limit, 50))]:
            payload = _read_json(path)
            if not payload:
                continue
            items.append({
                "request_id": payload.get("request_id") or path.stem,
                "action": payload.get("action"),
                "actor": payload.get("actor"),
                "started_at": payload.get("started_at"),
                "finished_at": payload.get("finished_at"),
                "result": payload.get("result"),
                "detail": str(payload.get("detail") or "")[-1600:] or None,
            })
    except Exception:
        pass
    return items


def status(*, include_actions: bool = False, include_service_detail: bool = False) -> dict:
    queued = action_queue() if include_actions else []
    history = action_history() if include_actions else []
    github_config = _read_json(GITHUB_CONFIG) or {
        "source": "https://github.com/filosoff31/srv-deployment.git",
        "mode": "automatic",
        "interval_minutes": 5,
    }
    os_config = _read_json(OS_UPDATE_CONFIG) or {"mode": "manual", "interval_hours": 24}
    backup_config = _read_json(BACKUP_CONFIG) or {
        "scheduled": False,
        "daily_time": "03:00",
        "backup_before_update": True,
    }
    return {
        "github_updates": {"config": github_config, "status": _read_json(GITHUB_STATUS)},
        "os_updates": {
            "config": os_config,
            "unit_state": _unit_state("srv-control-os-update.service"),
            "timer_state": _unit_state("srv-control-os-auto-update.timer"),
            "status": _read_json(OS_UPDATE_STATUS),
        },
        "backup": {"config": backup_config, "items": backups()},
        "services": service_catalog(include_detail=include_service_detail),
        "latest_action": history[0] if history else None,
        "actions": {
            "visible": include_actions,
            "queued_count": len(queued),
            "queued": queued,
            "history": history,
        },
    }


def backup_archive(backup_id: str) -> Path | None:
    if not backup_id or any(ch not in "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_" for ch in backup_id):
        return None
    metadata = _read_json(BACKUP_DIR / f"{backup_id}.json")
    if not metadata:
        return None
    archive = BACKUP_DIR / str(metadata.get("archive") or "")
    return archive if archive.is_file() else None


def enqueue(action: str, actor: str, client_ip: str | None, payload: dict | None = None) -> dict:
    if action not in ALLOWED_ACTIONS:
        raise ValueError("unsupported system action")
    ACTION_DIR.mkdir(parents=True, exist_ok=True)
    request_id = uuid.uuid4().hex
    body = {
        "schema_version": 2,
        "request_id": request_id,
        "action": action,
        "actor": actor,
        "client_ip": client_ip,
        "payload": payload if isinstance(payload, dict) else {},
    }
    tmp = ACTION_DIR / f".{request_id}.tmp"
    target = ACTION_DIR / f"{request_id}.json"
    tmp.write_text(json.dumps(body, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    os.chmod(tmp, 0o640)
    os.replace(tmp, target)
    return {"request_id": request_id, "action": action, "queued": True}
