from __future__ import annotations

from fastapi import APIRouter, HTTPException, Request
from fastapi.responses import FileResponse

from app.core.rbac import has_permission, require_permission
from app.core.system_admin import (
    backup_archive,
    enqueue,
    service_catalog,
    status as system_status,
)
from app.core.system_auth import Identity, require_csrf, require_session
from app.core.torrent_status import snapshot as torrent_snapshot


router = APIRouter(prefix="/api/v1", tags=["administration"])


def _identity(session: dict) -> Identity:
    identity = session.get("identity")
    if not isinstance(identity, Identity):
        raise HTTPException(status_code=401, detail="authentication required")
    return identity


def _admin(request: Request, *, csrf: bool = False) -> tuple[dict, Identity]:
    session = require_session(request)
    if csrf:
        require_csrf(request, session)
    identity = _identity(session)
    if not identity.is_admin:
        raise HTTPException(status_code=403, detail="server administrator permission required")
    return session, identity


def _client_ip(request: Request) -> str | None:
    return request.client.host if request.client else None


async def _payload(request: Request) -> dict:
    try:
        value = await request.json()
    except Exception:
        value = {}
    return value if isinstance(value, dict) else {}


def _queue(action: str, identity: Identity, request: Request, payload: dict | None = None) -> dict:
    try:
        return enqueue(action, identity.username, _client_ip(request), payload)
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc


@router.get("/system/configuration")
def configuration(request: Request):
    session = require_session(request)
    identity = _identity(session)
    data = system_status(include_actions=identity.is_admin, include_service_detail=identity.is_admin)
    data["can_write"] = identity.is_admin
    return {"ok": True, "data": data, "error": None}


@router.post("/system/github/config")
async def github_config(request: Request):
    _, identity = _admin(request, csrf=True)
    return {"ok": True, "data": _queue("github-update-config", identity, request, await _payload(request)), "error": None}


@router.post("/system/github/check")
def github_check(request: Request):
    _, identity = _admin(request, csrf=True)
    return {"ok": True, "data": _queue("github-check", identity, request), "error": None}


@router.post("/system/github/update")
def github_update(request: Request):
    _, identity = _admin(request, csrf=True)
    current = system_status().get("github_updates", {}).get("status") or {}
    if not bool(current.get("update_available")):
        raise HTTPException(status_code=409, detail="no GitHub product update is available")
    return {"ok": True, "data": _queue("github-update", identity, request), "error": None}


@router.post("/system/os/config")
async def os_config(request: Request):
    _, identity = _admin(request, csrf=True)
    return {"ok": True, "data": _queue("os-update-config", identity, request, await _payload(request)), "error": None}


@router.post("/system/os/update")
def os_update(request: Request):
    _, identity = _admin(request, csrf=True)
    return {"ok": True, "data": _queue("os-update", identity, request), "error": None}


@router.post("/system/backups/config")
async def backup_config(request: Request):
    _, identity = _admin(request, csrf=True)
    return {"ok": True, "data": _queue("backup-config", identity, request, await _payload(request)), "error": None}


@router.post("/system/backups")
def backup_create(request: Request):
    _, identity = _admin(request, csrf=True)
    return {"ok": True, "data": _queue("backup-create", identity, request), "error": None}


@router.delete("/system/backups/{backup_id}")
def backup_delete(backup_id: str, request: Request):
    _, identity = _admin(request, csrf=True)
    if backup_archive(backup_id) is None:
        raise HTTPException(status_code=404, detail="backup not found")
    return {
        "ok": True,
        "data": _queue("backup-delete", identity, request, {"backup_id": backup_id}),
        "error": None,
    }


@router.post("/system/backups/{backup_id}/restore")
def backup_restore(backup_id: str, request: Request):
    _, identity = _admin(request, csrf=True)
    if backup_archive(backup_id) is None:
        raise HTTPException(status_code=404, detail="backup not found")
    return {
        "ok": True,
        "data": _queue("backup-restore", identity, request, {"backup_id": backup_id}),
        "error": None,
    }


@router.get("/system/backups/{backup_id}/download")
def backup_download(backup_id: str, request: Request):
    _admin(request)
    archive = backup_archive(backup_id)
    if archive is None:
        raise HTTPException(status_code=404, detail="backup not found")
    return FileResponse(
        path=archive,
        filename=archive.name,
        media_type="application/gzip",
    )


@router.get("/services")
def services(request: Request):
    session = require_session(request)
    identity = _identity(session)
    visible = []
    for item in service_catalog(include_detail=True):
        module = str(item.get("permission_module") or "")
        if identity.is_admin or has_permission(identity, module, "read"):
            item = dict(item)
            item["can_write"] = identity.is_admin or has_permission(identity, module, "write")
            visible.append(item)
    return {"ok": True, "data": {"items": visible}, "error": None}


@router.post("/services/{service_id}/install")
def service_install(service_id: str, request: Request):
    session = require_session(request)
    require_csrf(request, session)
    identity = _identity(session)
    if service_id == "adguard-vpn":
        require_permission(identity, "network", "write")
        action = "service-install-adguard-vpn"
    elif service_id == "pxe-server":
        require_permission(identity, "pxe", "write")
        action = "service-install-pxe"
    else:
        raise HTTPException(status_code=404, detail="service not found")
    return {"ok": True, "data": _queue(action, identity, request), "error": None}


@router.post("/services/{service_id}/remove")
def service_remove(service_id: str, request: Request):
    session = require_session(request)
    require_csrf(request, session)
    identity = _identity(session)
    if service_id == "adguard-vpn":
        require_permission(identity, "network", "write")
        action = "service-remove-adguard-vpn"
    elif service_id == "pxe-server":
        require_permission(identity, "pxe", "write")
        action = "service-remove-pxe"
    else:
        raise HTTPException(status_code=404, detail="service not found")
    return {"ok": True, "data": _queue(action, identity, request), "error": None}


@router.get("/adguard")
def adguard_status(request: Request):
    session = require_session(request)
    identity = _identity(session)
    require_permission(identity, "network", "read")
    item = next(item for item in service_catalog(include_detail=True) if item["id"] == "adguard-vpn")
    item = dict(item)
    item["can_write"] = identity.is_admin or has_permission(identity, "network", "write")
    return {"ok": True, "data": item, "error": None}


@router.post("/adguard/{operation}")
def adguard_action(operation: str, request: Request):
    session = require_session(request)
    require_csrf(request, session)
    identity = _identity(session)
    require_permission(identity, "network", "write")
    actions = {
        "refresh": "service-refresh-adguard-vpn",
        "connect": "service-connect-adguard-vpn-socks",
        "disconnect": "service-disconnect-adguard-vpn",
        "update": "service-update-adguard-vpn",
    }
    action = actions.get(operation)
    if action is None:
        raise HTTPException(status_code=404, detail="operation not found")
    return {"ok": True, "data": _queue(action, identity, request), "error": None}


@router.get("/torrents")
def torrents(request: Request):
    session = require_session(request)
    identity = _identity(session)
    require_permission(identity, "downloads", "read")
    return {"ok": True, "data": torrent_snapshot(), "error": None}
