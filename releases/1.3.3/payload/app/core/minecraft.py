from __future__ import annotations

from pathlib import Path
import subprocess


PROPERTY_CANDIDATES = (
    Path("/opt/minecraft-bedrock/server.properties"),
    Path("/opt/minecraft/server.properties"),
    Path("/srv/minecraft/server.properties"),
    Path("/var/lib/minecraft/server.properties"),
)
SERVICE_CANDIDATES = (
    "minecraft-bedrock.service",
    "minecraft.service",
    "bedrock-server.service",
)
EDITABLE_KEYS = (
    "server-name",
    "gamemode",
    "difficulty",
    "allow-cheats",
    "max-players",
    "server-port",
    "server-portv6",
    "online-mode",
    "allow-list",
    "view-distance",
    "tick-distance",
    "player-idle-timeout",
    "level-name",
)


def _systemctl(*args: str) -> tuple[int, str]:
    try:
        result = subprocess.run(
            ["systemctl", *args],
            capture_output=True,
            text=True,
            timeout=4,
            check=False,
        )
        return result.returncode, (result.stdout or "").strip()
    except Exception:
        return 1, ""


def discover_service() -> str | None:
    for unit in SERVICE_CANDIDATES:
        code, loaded = _systemctl("show", unit, "-p", "LoadState", "--value")
        if code == 0 and loaded and loaded != "not-found":
            return unit
    return None


def discover_properties() -> Path | None:
    for path in PROPERTY_CANDIDATES:
        if path.is_file():
            return path
    service = discover_service()
    if service:
        code, working_directory = _systemctl(
            "show", service, "-p", "WorkingDirectory", "--value"
        )
        if code == 0 and working_directory:
            candidate = Path(working_directory) / "server.properties"
            if candidate.is_file():
                return candidate
    return None


def read_properties(path: Path | None = None) -> dict[str, str]:
    target = path or discover_properties()
    if target is None:
        return {}
    values: dict[str, str] = {}
    try:
        lines = target.read_text(encoding="utf-8", errors="replace").splitlines()
    except Exception:
        return values
    for line in lines:
        stripped = line.strip()
        if not stripped or stripped.startswith("#") or "=" not in stripped:
            continue
        key, value = stripped.split("=", 1)
        key = key.strip()
        if key in EDITABLE_KEYS:
            values[key] = value.strip()
    return values


def snapshot() -> dict:
    service = discover_service()
    properties_path = discover_properties()
    state = "not-installed"
    enabled = False
    if service:
        _, state_value = _systemctl("is-active", service)
        state = state_value or "inactive"
        code, enabled_value = _systemctl("is-enabled", service)
        enabled = code == 0 and enabled_value in {"enabled", "static"}
    return {
        "installed": bool(service or properties_path),
        "service": service,
        "state": state,
        "enabled": enabled,
        "properties_path": str(properties_path) if properties_path else None,
        "properties": read_properties(properties_path),
        "editable_keys": list(EDITABLE_KEYS),
    }
