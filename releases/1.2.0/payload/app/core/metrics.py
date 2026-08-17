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

_process_cpu_times: dict[int, float] = {}
_process_sample_at: float | None = None


def service_state(unit: str) -> str:
    try:
        result = subprocess.run(
            ["systemctl", "is-active", unit],
            capture_output=True,
            text=True,
            timeout=2,
            check=False,
        )
        return result.stdout.strip() or "unknown"
    except Exception:
        return "unknown"


def disk_info(path: str) -> dict:
    try:
        usage = shutil.disk_usage(path)
        percent = usage.used / usage.total * 100.0 if usage.total else 0.0
        return {
            "path": path,
            "total": usage.total,
            "used": usage.used,
            "free": usage.free,
            "percent": round(percent, 1),
        }
    except Exception:
        return {"path": path, "total": 0, "used": 0, "free": 0, "percent": 0.0}


def database_health() -> dict:
    try:
        from sqlalchemy import text
        from app.database import engine

        with engine.connect() as connection:
            value = connection.execute(text("SELECT 1")).scalar_one()
        return {"state": "active" if value == 1 else "unknown"}
    except Exception as exc:
        return {"state": "error", "error": str(exc)[:300]}


def operating_system_name() -> str:
    os_release = Path("/etc/os-release")
    try:
        if os_release.exists():
            for line in os_release.read_text(encoding="utf-8").splitlines():
                if line.startswith("PRETTY_NAME="):
                    return line.split("=", 1)[1].strip().strip('"')
    except Exception:
        pass
    return platform.system()


def _top_processes(memory_total: int, logical_count: int) -> dict:
    global _process_cpu_times, _process_sample_at

    now = time.monotonic()
    elapsed = None if _process_sample_at is None else max(0.001, now - _process_sample_at)
    current_cpu: dict[int, float] = {}
    rows: list[dict] = []

    for process in psutil.process_iter(
        ["pid", "name", "username", "memory_info", "cpu_times"]
    ):
        try:
            info = process.info
            pid = int(info.get("pid") or 0)
            cpu_times = info.get("cpu_times")
            memory_info = info.get("memory_info")
            cpu_total = float(cpu_times.user + cpu_times.system) if cpu_times else 0.0
            current_cpu[pid] = cpu_total

            cpu_percent = 0.0
            previous = _process_cpu_times.get(pid)
            if elapsed is not None and previous is not None:
                cpu_percent = max(
                    0.0,
                    (cpu_total - previous) / elapsed * 100.0 / max(1, logical_count),
                )

            rss = int(memory_info.rss) if memory_info else 0
            memory_percent = rss / memory_total * 100.0 if memory_total else 0.0
            rows.append(
                {
                    "pid": pid,
                    "name": str(info.get("name") or f"PID {pid}")[:80],
                    "user": str(info.get("username") or "")[:80] or None,
                    "cpu_percent": round(min(cpu_percent, 100.0), 1),
                    "memory_percent": round(max(0.0, memory_percent), 1),
                    "memory_rss": rss,
                }
            )
        except (psutil.NoSuchProcess, psutil.AccessDenied, psutil.ZombieProcess, OSError):
            continue

    _process_cpu_times = current_cpu
    _process_sample_at = now

    cpu_top = sorted(rows, key=lambda item: (item["cpu_percent"], item["memory_rss"]), reverse=True)[:3]
    memory_top = sorted(rows, key=lambda item: item["memory_rss"], reverse=True)[:3]
    return {"cpu_top": cpu_top, "memory_top": memory_top}


def snapshot() -> dict:
    memory = psutil.virtual_memory()
    network = psutil.net_io_counters()
    boot_time = psutil.boot_time()
    now = time.time()
    logical_count = psutil.cpu_count(logical=True) or 0
    physical_count = psutil.cpu_count(logical=False) or 0

    try:
        load1, load5, load15 = os.getloadavg()
    except Exception:
        load1 = load5 = load15 = 0.0

    service_states = {name: service_state(unit) for name, unit in SERVICES.items()}
    processes = _top_processes(memory.total, logical_count)

    return {
        "timestamp": datetime.now(timezone.utc).isoformat(),
        "system": {
            "hostname": socket.getfqdn() or socket.gethostname(),
            "os": operating_system_name(),
            "kernel": platform.release(),
            "architecture": platform.machine(),
            "python": platform.python_version(),
        },
        "cpu": {
            "percent": round(psutil.cpu_percent(interval=None), 1),
            "logical_count": logical_count,
            "physical_count": physical_count,
            "load1": round(load1, 2),
            "load5": round(load5, 2),
            "load15": round(load15, 2),
        },
        "memory": {
            "total": memory.total,
            "used": memory.used,
            "available": memory.available,
            "percent": round(memory.percent, 1),
        },
        "processes": processes,
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
            "seconds": max(0, int(now - boot_time)),
        },
        "storage": [disk_info("/"), disk_info("/home")],
        "services": service_states,
        "database": database_health(),
    }
