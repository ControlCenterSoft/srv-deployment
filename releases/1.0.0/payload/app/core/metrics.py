from __future__ import annotations

from datetime import datetime, timezone
from pathlib import Path
import os
import platform
import shutil
import socket
import subprocess
import time

import psutil


SERVICES = {
    "srv-control": "srv-control.service",
    "PostgreSQL": "postgresql.service",
    "Apache": "apache2.service",
    "Samba AD": "samba-ad-dc.service",
    "DHCP": "isc-dhcp-server.service",
    "TFTP": "tftpd-hpa.service",
    "Docker": "docker.service",
}


def service_state(unit: str) -> str:
    try:
        result = subprocess.run(
            [
                "systemctl",
                "is-active",
                unit,
            ],
            capture_output=True,
            text=True,
            timeout=2,
            check=False,
        )

        value = result.stdout.strip()

        if value:
            return value

        return "unknown"

    except Exception:
        return "unknown"


def disk_info(path: str) -> dict:
    try:
        usage = shutil.disk_usage(
            path
        )

        percent = (
            usage.used
            / usage.total
            * 100.0
            if usage.total
            else 0.0
        )

        return {
            "path": path,
            "total": usage.total,
            "used": usage.used,
            "free": usage.free,
            "percent": round(
                percent,
                1,
            ),
        }

    except Exception:
        return {
            "path": path,
            "total": 0,
            "used": 0,
            "free": 0,
            "percent": 0.0,
        }


def database_health() -> dict:
    try:
        from sqlalchemy import text

        from app.database import engine

        with engine.connect() as connection:
            value = connection.execute(
                text(
                    "SELECT 1"
                )
            ).scalar_one()

        return {
            "state": (
                "active"
                if value == 1
                else "unknown"
            )
        }

    except Exception as exc:
        return {
            "state": "error",
            "error": str(exc)[:300],
        }


def operating_system_name() -> str:
    os_release = Path("/etc/os-release")

    try:
        if os_release.exists():
            for line in os_release.read_text(
                encoding="utf-8"
            ).splitlines():
                if line.startswith("PRETTY_NAME="):
                    return line.split(
                        "=",
                        1,
                    )[1].strip().strip('"')
    except Exception:
        pass

    return platform.system()


def snapshot() -> dict:
    memory = psutil.virtual_memory()

    network = psutil.net_io_counters()

    boot_time = psutil.boot_time()

    now = time.time()

    load1 = 0.0
    load5 = 0.0
    load15 = 0.0

    try:
        load1, load5, load15 = os.getloadavg()

    except Exception:
        pass

    service_states = {
        name: service_state(
            unit
        )
        for name, unit in SERVICES.items()
    }

    return {
        "timestamp": datetime.now(
            timezone.utc
        ).isoformat(),

        "system": {
            "hostname": (
                socket.getfqdn()
                or socket.gethostname()
            ),
            "os": operating_system_name(),
            "kernel": platform.release(),
            "architecture": platform.machine(),
            "python": platform.python_version(),
        },

        "cpu": {
            "percent": round(
                psutil.cpu_percent(
                    interval=None
                ),
                1,
            ),
            "logical_count": (
                psutil.cpu_count(
                    logical=True
                )
                or 0
            ),
            "physical_count": (
                psutil.cpu_count(
                    logical=False
                )
                or 0
            ),
            "load1": round(
                load1,
                2,
            ),
            "load5": round(
                load5,
                2,
            ),
            "load15": round(
                load15,
                2,
            ),
        },

        "memory": {
            "total": memory.total,
            "used": memory.used,
            "available": memory.available,
            "percent": round(
                memory.percent,
                1,
            ),
        },

        "network": {
            "bytes_sent": network.bytes_sent,
            "bytes_recv": network.bytes_recv,
            "packets_sent": network.packets_sent,
            "packets_recv": network.packets_recv,
            "errin": network.errin,
            "errout": network.errout,
            "dropin": network.dropin,
            "dropout": network.dropout,
        },

        "uptime": {
            "boot_time": boot_time,
            "seconds": max(
                0,
                int(
                    now
                    -
                    boot_time
                ),
            ),
        },

        "storage": [
            disk_info("/"),
            disk_info("/home"),
        ],

        "services": service_states,

        "database": database_health(),
    }
