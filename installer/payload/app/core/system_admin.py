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
AUTO_UPDATES_FILE = Path("/etc/apt/apt.conf.d/20auto-upgrades")

ALLOWED_ACTIONS = {
    "reboot",
    "os-update",
    "auto-updates-enable",
    "auto-updates-disable",
    "service-install-adguard-vpn",
    "service-remove-adguard-vpn",
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
        text = AUTO_UPDATES_FILE.read_text(
            encoding="utf-8",
            errors="replace",
        )
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


def service_catalog() -> list[dict]:
    binary = shutil.which("adguardvpn-cli")
    if not binary and Path("/opt/adguardvpn_cli/adguardvpn-cli").exists():
        binary = "/opt/adguardvpn_cli/adguardvpn-cli"

    return [
        {
            "id": "adguard-vpn",
            "name": "AdGuard VPN",
            "installed": bool(binary),
            "binary": binary,
            "description": "AdGuard VPN CLI for Linux",
            "actions": {
                "install": not bool(binary),
                "remove": bool(binary),
            },
        }
    ]


def status() -> dict:
    latest = None
    try:
        results = sorted(
            RESULT_DIR.glob("*.json"),
            key=lambda item: item.stat().st_mtime,
            reverse=True,
        )
        if results:
            latest = _read_json(results[0])
    except Exception:
        pass

    return {
        "automatic_updates": {
            "enabled": automatic_updates_enabled(),
            "unattended_upgrades_installed": shutil.which("unattended-upgrade") is not None,
        },
        "manual_update": {
            "unit_state": _unit_state("srv-control-os-update.service"),
            "status": _read_json(UPDATE_STATUS),
        },
        "services": service_catalog(),
        "latest_action": latest,
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
    tmp.write_text(
        json.dumps(payload, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    os.chmod(tmp, 0o640)
    os.replace(tmp, target)

    return {
        "request_id": request_id,
        "action": action,
        "queued": True,
    }
