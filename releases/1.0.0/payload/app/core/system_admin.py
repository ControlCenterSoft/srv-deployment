from __future__ import annotations

import json
import os
from pathlib import Path
import shutil
import subprocess
import uuid


ACTION_DIR = Path("/var/lib/srv-control/system-actions")
RESULT_DIR = Path("/var/lib/srv-control/system-results")
UPDATE_STATUS = Path("/var/lib/srv-control/os-update-status.json")
ADGUARD_STATUS = Path("/var/lib/srv-control/adguard-vpn-status.json")
AUTO_UPDATES_FILE = Path("/etc/apt/apt.conf.d/20auto-upgrades")

ALLOWED_ACTIONS = {
    "reboot",
    "os-update",
    "auto-updates-enable",
    "auto-updates-disable",
    "service-install-adguard-vpn",
    "service-remove-adguard-vpn",
    "service-refresh-adguard-vpn",
    "service-connect-adguard-vpn-socks",
    "service-disconnect-adguard-vpn",
    "service-update-adguard-vpn",
}


def _read_json(path: Path) -> dict | None:
    try:
        payload = json.loads(path.read_text(encoding="utf-8"))
        if isinstance(payload, dict):
            return payload
    except Exception:
        pass
    return None


def automatic_updates_enabled() -> bool:
    try:
        text = AUTO_UPDATES_FILE.read_text(encoding="utf-8", errors="replace")
    except Exception:
        return False

    return (
        'APT::Periodic::Update-Package-Lists "1";' in text
        and 'APT::Periodic::Unattended-Upgrade "1";' in text
    )


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


def _adguard_binary() -> str | None:
    binary = shutil.which("adguardvpn-cli")
    if binary:
        return binary
    path = Path("/opt/adguardvpn_cli/adguardvpn-cli")
    return str(path) if path.exists() else None


def service_catalog(*, include_detail: bool = False) -> list[dict]:
    binary = _adguard_binary()
    monitor = _read_json(ADGUARD_STATUS) or {}
    installed = bool(binary)
    status = {
        "state": monitor.get("state") if installed else "not-installed",
        "version": monitor.get("version") if installed else None,
        "mode": monitor.get("mode") if installed else None,
        "socks_host": monitor.get("socks_host") if installed else None,
        "socks_port": monitor.get("socks_port") if installed else None,
        "update_channel": monitor.get("update_channel") if installed else None,
        "checked_at": monitor.get("checked_at") if installed else None,
    }
    if include_detail and installed:
        status["detail"] = monitor.get("detail")

    return [
        {
            "id": "adguard-vpn",
            "name": "AdGuard VPN",
            "installed": installed,
            "binary": binary,
            "description": "AdGuard VPN CLI for Linux",
            "status": status,
            "actions": {
                "install": not installed,
                "remove": installed,
                "refresh": installed,
                "safe_connect": installed,
                "disconnect": installed,
                "update": installed,
            },
            "safety": {
                "connect_mode": "SOCKS",
                "socks_endpoint": "127.0.0.1:1080",
                "system_default_route_changed": False,
                "credentials_stored_by_control_center": False,
            },
        }
    ]


def action_queue(limit: int = 20) -> list[dict]:
    items: list[dict] = []
    try:
        paths = sorted(ACTION_DIR.glob("*.json"), key=lambda item: item.stat().st_mtime)
        for path in paths[: max(0, min(limit, 50))]:
            payload = _read_json(path)
            if payload:
                items.append(
                    {
                        "request_id": payload.get("request_id") or path.stem,
                        "action": payload.get("action"),
                        "actor": payload.get("actor"),
                        "queued": True,
                    }
                )
    except Exception:
        pass
    return items


def action_history(limit: int = 20) -> list[dict]:
    items: list[dict] = []
    try:
        paths = sorted(
            RESULT_DIR.glob("*.json"),
            key=lambda item: item.stat().st_mtime,
            reverse=True,
        )
        for path in paths[: max(0, min(limit, 50))]:
            payload = _read_json(path)
            if not payload:
                continue
            items.append(
                {
                    "request_id": payload.get("request_id") or path.stem,
                    "action": payload.get("action"),
                    "actor": payload.get("actor"),
                    "started_at": payload.get("started_at"),
                    "finished_at": payload.get("finished_at"),
                    "result": payload.get("result"),
                    "detail": str(payload.get("detail") or "")[-1600:] or None,
                }
            )
    except Exception:
        pass
    return items


def status(
    *,
    include_actions: bool = False,
    include_service_detail: bool = False,
) -> dict:
    queued = action_queue() if include_actions else []
    history = action_history() if include_actions else []

    return {
        "automatic_updates": {
            "enabled": automatic_updates_enabled(),
            "unattended_upgrades_installed": shutil.which("unattended-upgrade") is not None,
        },
        "manual_update": {
            "unit_state": _unit_state("srv-control-os-update.service"),
            "status": _read_json(UPDATE_STATUS),
        },
        "services": service_catalog(include_detail=include_service_detail),
        "latest_action": history[0] if history else None,
        "actions": {
            "visible": include_actions,
            "queued_count": len(queued),
            "queued": queued,
            "history": history,
        },
    }


def enqueue(action: str, actor: str, client_ip: str | None) -> dict:
    if action not in ALLOWED_ACTIONS:
        raise ValueError("unsupported system action")

    ACTION_DIR.mkdir(parents=True, exist_ok=True)
    request_id = uuid.uuid4().hex
    payload = {
        "schema_version": 1,
        "request_id": request_id,
        "action": action,
        "actor": actor,
        "client_ip": client_ip,
    }

    tmp = ACTION_DIR / f".{request_id}.tmp"
    target = ACTION_DIR / f"{request_id}.json"
    tmp.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    os.chmod(tmp, 0o640)
    os.replace(tmp, target)

    return {"request_id": request_id, "action": action, "queued": True}
