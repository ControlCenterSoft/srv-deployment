from __future__ import annotations

import json
from pathlib import Path
import subprocess

from fastapi import APIRouter, HTTPException, Query, Request

from app.core.rbac import has_permission, is_full_admin, require_permission
from app.core.system_auth import Identity, require_csrf, require_session


router = APIRouter(prefix="/api/v1/minecraft/legacy", tags=["minecraft-legacy"])

HELPERS = {
    "control": Path("/usr/local/sbin/srv-control-minecraft"),
    "players": Path("/usr/local/sbin/srv-control-minecraft-players"),
    "worlds": Path("/usr/local/sbin/srv-control-minecraft-worlds"),
    "restore": Path("/usr/local/sbin/srv-control-minecraft-restore"),
    "live": Path("/usr/local/sbin/srv-control-minecraft-live"),
}


def _identity(request: Request, *, csrf: bool = False) -> Identity:
    session = require_session(request)
    if csrf:
        require_csrf(request, session)
    identity = session.get("identity")
    if not isinstance(identity, Identity):
        raise HTTPException(status_code=401, detail="authentication required")
    return identity


def _read_access(request: Request) -> Identity:
    identity = _identity(request)
    require_permission(identity, "minecraft", "read")
    return identity


def _write_access(request: Request) -> Identity:
    identity = _identity(request, csrf=True)
    require_permission(identity, "minecraft", "write")
    return identity


async def _payload(request: Request) -> dict:
    try:
        value = await request.json()
    except Exception:
        value = {}
    return value if isinstance(value, dict) else {}


def _normalize(result: dict, identity: Identity | None = None) -> dict:
    data = dict(result)
    data.pop("ok", None)
    if identity is not None:
        data["can_write"] = identity.is_admin or has_permission(identity, "minecraft", "write")
        data["full_admin"] = is_full_admin(identity)
    return {"ok": True, "data": data, "error": None}


def _helper(kind: str) -> Path:
    helper = HELPERS[kind]
    if not helper.is_file():
        raise HTTPException(
            status_code=503,
            detail=(
                f"legacy Minecraft helper is unavailable: {helper}. "
                "SRV Control Center 1.3.2 intentionally uses the proven legacy backend."
            ),
        )
    return helper


def _run_args(kind: str, *args: str, payload: dict | None = None, timeout: int = 90) -> dict:
    helper = _helper(kind)
    try:
        process = subprocess.run(
            ["/usr/bin/sudo", "-n", str(helper), *args],
            input=(json.dumps(payload, ensure_ascii=False) if payload is not None else ""),
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            timeout=timeout,
            check=False,
        )
    except subprocess.TimeoutExpired as exc:
        raise HTTPException(status_code=504, detail=f"Minecraft operation timed out after {timeout}s") from exc
    except Exception as exc:
        raise HTTPException(status_code=500, detail=f"Minecraft helper execution failed: {exc}") from exc

    output = (process.stdout or "").strip()
    try:
        result = json.loads(output)
    except Exception as exc:
        raise HTTPException(
            status_code=502,
            detail=output[-2000:] or "invalid Minecraft helper response",
        ) from exc
    if process.returncode != 0 or not isinstance(result, dict) or not result.get("ok"):
        message = result.get("error") if isinstance(result, dict) else None
        raise HTTPException(status_code=400, detail=str(message or output or "Minecraft operation failed"))
    return result


def _run_json(kind: str, action: str, payload: dict | None = None, timeout: int = 90) -> dict:
    request = {"action": action}
    if payload:
        request.update(payload)
    return _run_args(kind, payload=request, timeout=timeout)


@router.get("/status")
def status(request: Request):
    identity = _read_access(request)
    return _normalize(_run_args("control", "status", timeout=30), identity)


@router.get("/overview")
def overview(request: Request):
    identity = _read_access(request)
    result: dict = {"backend": "legacy", "backend_contract": "2026-08-16"}
    errors: dict[str, str] = {}
    calls = {
        "status": lambda: _run_args("control", "status", timeout=30),
        "updater": lambda: _run_args("control", "updater", timeout=30),
        "players": lambda: _run_json("players", "list", timeout=30),
        "worlds": lambda: _run_args("worlds", "list", timeout=30),
        "backups": lambda: _run_args("restore", "list", timeout=60),
        "live": lambda: _run_json("live", "status", timeout=15),
    }
    for name, call in calls.items():
        try:
            value = call()
            value.pop("ok", None)
            result[name] = value
        except HTTPException as exc:
            errors[name] = str(exc.detail)
    result["errors"] = errors
    return _normalize(result, identity)


@router.get("/properties")
def properties(request: Request):
    identity = _read_access(request)
    return _normalize(_run_args("control", "properties-get", timeout=30), identity)


@router.put("/properties")
async def properties_save(request: Request):
    identity = _write_access(request)
    body = await _payload(request)
    changes = body.get("changes")
    if not isinstance(changes, dict) or not changes:
        raise HTTPException(status_code=400, detail="changes object is required")
    allowed = {
        "server-name", "gamemode", "force-gamemode", "difficulty", "allow-cheats",
        "max-players", "online-mode", "allow-list", "server-port", "server-portv6",
        "enable-lan-visibility", "view-distance", "tick-distance", "player-idle-timeout",
        "max-threads", "level-name", "level-seed", "default-player-permission-level",
        "texturepack-required", "content-log-file-enabled", "content-log-console-output-enabled",
    }
    clean: dict[str, str | int | bool] = {}
    for key, value in changes.items():
        if key not in allowed:
            raise HTTPException(status_code=400, detail=f"unsupported Minecraft property: {key}")
        if isinstance(value, (str, int, bool)):
            clean[key] = value
        else:
            raise HTTPException(status_code=400, detail=f"invalid value for {key}")
    return _normalize(_run_args("control", "properties-set", payload={"changes": clean}, timeout=90), identity)


@router.post("/service/{action}")
def service(action: str, request: Request):
    identity = _write_access(request)
    if action not in {"start", "stop", "restart"}:
        raise HTTPException(status_code=404, detail="operation not found")
    return _normalize(_run_args("control", "service", action, timeout=240), identity)


@router.get("/updater")
def updater(request: Request):
    identity = _read_access(request)
    return _normalize(_run_args("control", "updater", timeout=30), identity)


@router.post("/update")
def update(request: Request):
    identity = _write_access(request)
    return _normalize(_run_args("control", "update", timeout=1250), identity)


@router.get("/logs")
def logs(request: Request, limit: int = Query(150, ge=20, le=500)):
    identity = _read_access(request)
    return _normalize(_run_args("control", "logs", str(limit), timeout=30), identity)


@router.post("/backup")
def backup(request: Request):
    identity = _write_access(request)
    return _normalize(_run_args("control", "backup", timeout=1000), identity)


@router.get("/backups")
def backups(request: Request):
    identity = _read_access(request)
    return _normalize(_run_args("restore", "list", timeout=60), identity)


@router.get("/backups/{name}")
def backup_inspect(name: str, request: Request):
    identity = _read_access(request)
    return _normalize(_run_args("restore", "inspect", name, timeout=60), identity)


@router.post("/backups/{name}/restore")
def backup_restore(name: str, request: Request):
    identity = _write_access(request)
    return _normalize(_run_args("restore", "restore", name, timeout=1800), identity)


@router.delete("/backups/{name}")
async def backup_delete(name: str, request: Request):
    identity = _write_access(request)
    body = await _payload(request)
    confirm = str(body.get("confirm") or "")
    return _normalize(_run_args("restore", "delete", name, confirm, timeout=90), identity)


@router.get("/worlds")
def worlds(request: Request):
    identity = _read_access(request)
    return _normalize(_run_args("worlds", "list", timeout=60), identity)


@router.post("/worlds/{name}/activate")
def world_activate(name: str, request: Request):
    identity = _write_access(request)
    return _normalize(_run_args("worlds", "activate", name, timeout=300), identity)


@router.post("/worlds/{name}/clone")
async def world_clone(name: str, request: Request):
    identity = _write_access(request)
    body = await _payload(request)
    new_name = str(body.get("new_name") or "").strip()
    if not new_name:
        raise HTTPException(status_code=400, detail="new_name is required")
    return _normalize(_run_args("worlds", "clone", name, new_name, timeout=1800), identity)


@router.post("/worlds/{name}/rename")
async def world_rename(name: str, request: Request):
    identity = _write_access(request)
    body = await _payload(request)
    new_name = str(body.get("new_name") or "").strip()
    if not new_name:
        raise HTTPException(status_code=400, detail="new_name is required")
    return _normalize(_run_args("worlds", "rename", name, new_name, timeout=1800), identity)


@router.delete("/worlds/{name}")
async def world_delete(name: str, request: Request):
    identity = _write_access(request)
    body = await _payload(request)
    confirm = str(body.get("confirm") or "")
    return _normalize(_run_args("worlds", "delete", name, confirm, timeout=1800), identity)


@router.get("/players")
def players(request: Request):
    identity = _read_access(request)
    return _normalize(_run_json("players", "list", timeout=30), identity)


@router.put("/players/settings")
async def player_settings(request: Request):
    identity = _write_access(request)
    body = await _payload(request)
    payload = {
        "allow_list_enabled": bool(body.get("allow_list_enabled")),
        "default_permission": str(body.get("default_permission") or "member"),
    }
    return _normalize(_run_json("players", "settings-set", payload, timeout=60), identity)


@router.post("/players/allowlist")
async def allowlist_add(request: Request):
    identity = _write_access(request)
    body = await _payload(request)
    name = str(body.get("name") or "").strip()
    if not name:
        raise HTTPException(status_code=400, detail="player name is required")
    payload = {
        "name": name,
        "xuid": str(body.get("xuid") or "").strip(),
        "ignores_player_limit": bool(body.get("ignores_player_limit")),
    }
    return _normalize(_run_json("players", "allow-add", payload, timeout=60), identity)


@router.delete("/players/allowlist/{key}")
def allowlist_remove(key: str, request: Request):
    identity = _write_access(request)
    return _normalize(_run_json("players", "allow-remove", {"key": key}, timeout=60), identity)


@router.put("/players/{xuid}/permission")
async def permission_set(xuid: str, request: Request):
    identity = _write_access(request)
    body = await _payload(request)
    permission = str(body.get("permission") or "member")
    if permission not in {"visitor", "member", "operator"}:
        raise HTTPException(status_code=400, detail="invalid permission")
    return _normalize(
        _run_json("players", "permission-set", {"xuid": xuid, "permission": permission}, timeout=60),
        identity,
    )


@router.delete("/players/{xuid}/permission")
def permission_remove(xuid: str, request: Request):
    identity = _write_access(request)
    return _normalize(_run_json("players", "permission-remove", {"xuid": xuid}, timeout=60), identity)


@router.get("/live/status")
def live_status(request: Request):
    identity = _read_access(request)
    return _normalize(_run_json("live", "status", timeout=15), identity)


@router.post("/live/{action}")
async def live_action(action: str, request: Request):
    identity = _write_access(request)
    if action not in {"list", "say", "kick", "op", "deop"}:
        raise HTTPException(status_code=404, detail="operation not found")
    body = await _payload(request)
    payload: dict = {}
    if action == "say":
        message = str(body.get("message") or "").strip()
        if not message:
            raise HTTPException(status_code=400, detail="message is required")
        payload = {"message": message}
    elif action in {"kick", "op", "deop"}:
        username = str(body.get("username") or "").strip()
        if not username:
            raise HTTPException(status_code=400, detail="username is required")
        payload = {"username": username}
        if action == "kick":
            payload["reason"] = str(body.get("reason") or "Отключён администратором")
    return _normalize(_run_json("live", action, payload, timeout=30), identity)
