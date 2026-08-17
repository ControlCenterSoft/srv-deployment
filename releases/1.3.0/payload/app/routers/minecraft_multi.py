from __future__ import annotations

from fastapi import APIRouter, HTTPException, Request

from app.core.minecraft_instances import snapshot as minecraft_instances_snapshot
from app.core.rbac import has_permission, is_full_admin, require_permission
from app.core.system_admin import enqueue
from app.core.system_auth import Identity, require_csrf, require_session


router = APIRouter(prefix="/api/v1/minecraft", tags=["minecraft"])


def _identity(request: Request, *, csrf: bool = False) -> Identity:
    session = require_session(request)
    if csrf:
        require_csrf(request, session)
    identity = session.get("identity")
    if not isinstance(identity, Identity):
        raise HTTPException(status_code=401, detail="authentication required")
    return identity


def _client_ip(request: Request) -> str | None:
    return request.client.host if request.client else None


async def _payload(request: Request) -> dict:
    try:
        value = await request.json()
    except Exception:
        value = {}
    return value if isinstance(value, dict) else {}


def _queue(action: str, identity: Identity, request: Request, payload: dict) -> dict:
    try:
        return enqueue(action, identity.username, _client_ip(request), payload)
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc


def _instance_id(value: str) -> str:
    raw = str(value or "").strip().lower()
    if not raw or len(raw) > 32 or any(ch not in "abcdefghijklmnopqrstuvwxyz0123456789-_" for ch in raw):
        raise HTTPException(status_code=400, detail="invalid Minecraft instance id")
    return raw


@router.get("/instances")
def instances(request: Request):
    identity = _identity(request)
    require_permission(identity, "minecraft", "read")
    data = minecraft_instances_snapshot()
    data["can_write"] = identity.is_admin or has_permission(identity, "minecraft", "write")
    data["full_admin"] = is_full_admin(identity)
    return {"ok": True, "data": data, "error": None}


@router.post("/instances")
async def instance_create(request: Request):
    identity = _identity(request, csrf=True)
    require_permission(identity, "minecraft", "write")
    payload = await _payload(request)
    payload["id"] = _instance_id(str(payload.get("id") or ""))
    return {
        "ok": True,
        "data": _queue("minecraft-instance-create", identity, request, payload),
        "error": None,
    }


@router.post("/instances/{instance_id}/update")
async def instance_update(instance_id: str, request: Request):
    identity = _identity(request, csrf=True)
    require_permission(identity, "minecraft", "write")
    payload = await _payload(request)
    payload["id"] = _instance_id(instance_id)
    return {
        "ok": True,
        "data": _queue("minecraft-instance-update", identity, request, payload),
        "error": None,
    }


@router.post("/instances/{instance_id}/control/{operation}")
def instance_operation(instance_id: str, operation: str, request: Request):
    identity = _identity(request, csrf=True)
    require_permission(identity, "minecraft", "write")
    actions = {
        "start": "minecraft-instance-start",
        "stop": "minecraft-instance-stop",
        "restart": "minecraft-instance-restart",
    }
    action = actions.get(operation)
    if action is None:
        raise HTTPException(status_code=404, detail="operation not found")
    return {
        "ok": True,
        "data": _queue(action, identity, request, {"id": _instance_id(instance_id)}),
        "error": None,
    }


@router.post("/instances/{instance_id}/delete")
async def instance_delete(instance_id: str, request: Request):
    identity = _identity(request, csrf=True)
    require_permission(identity, "minecraft", "write")
    payload = await _payload(request)
    delete_data = bool(payload.get("delete_data"))
    if delete_data and not is_full_admin(identity):
        raise HTTPException(status_code=403, detail="full administrator required to delete Minecraft data")
    return {
        "ok": True,
        "data": _queue(
            "minecraft-instance-delete",
            identity,
            request,
            {"id": _instance_id(instance_id), "delete_data": delete_data},
        ),
        "error": None,
    }


@router.post("/instances/{instance_id}/players/allow")
async def player_allow(instance_id: str, request: Request):
    identity = _identity(request, csrf=True)
    require_permission(identity, "minecraft", "write")
    payload = await _payload(request)
    payload["id"] = _instance_id(instance_id)
    return {
        "ok": True,
        "data": _queue("minecraft-player-allow", identity, request, payload),
        "error": None,
    }


@router.post("/instances/{instance_id}/players/deny")
async def player_deny(instance_id: str, request: Request):
    identity = _identity(request, csrf=True)
    require_permission(identity, "minecraft", "write")
    payload = await _payload(request)
    payload["id"] = _instance_id(instance_id)
    return {
        "ok": True,
        "data": _queue("minecraft-player-deny", identity, request, payload),
        "error": None,
    }


@router.post("/instances/{instance_id}/players/permission")
async def player_permission(instance_id: str, request: Request):
    identity = _identity(request, csrf=True)
    require_permission(identity, "minecraft", "write")
    payload = await _payload(request)
    payload["id"] = _instance_id(instance_id)
    return {
        "ok": True,
        "data": _queue("minecraft-player-permission", identity, request, payload),
        "error": None,
    }


@router.post("/instances/{instance_id}/players/kick")
async def player_kick(instance_id: str, request: Request):
    identity = _identity(request, csrf=True)
    require_permission(identity, "minecraft", "write")
    payload = await _payload(request)
    payload["id"] = _instance_id(instance_id)
    return {
        "ok": True,
        "data": _queue("minecraft-player-kick", identity, request, payload),
        "error": None,
    }


@router.post("/instances/{instance_id}/update/check")
def update_check(instance_id: str, request: Request):
    identity = _identity(request, csrf=True)
    require_permission(identity, "minecraft", "write")
    return {
        "ok": True,
        "data": _queue("minecraft-update-check", identity, request, {"id": _instance_id(instance_id)}),
        "error": None,
    }


@router.post("/instances/{instance_id}/update/apply")
async def update_apply(instance_id: str, request: Request):
    identity = _identity(request, csrf=True)
    require_permission(identity, "minecraft", "write")
    payload = await _payload(request)
    return {
        "ok": True,
        "data": _queue(
            "minecraft-update-apply",
            identity,
            request,
            {
                "id": _instance_id(instance_id),
                "eula_accepted": bool(payload.get("eula_accepted")),
            },
        ),
        "error": None,
    }
