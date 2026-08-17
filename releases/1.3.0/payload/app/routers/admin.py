from __future__ import annotations

import os
from pathlib import Path
import secrets
import shutil

from fastapi import APIRouter, File, HTTPException, Request, UploadFile
from fastapi.responses import FileResponse

from app.core.identity_directory import snapshot as identity_directory_snapshot
from app.core.minecraft import snapshot as minecraft_snapshot
from app.core.rbac import has_permission, is_full_admin, require_permission
from app.core.samba_domain import (
    backup_archive as samba_backup_archive,
    backup_items as samba_backup_items,
    snapshot as samba_domain_snapshot,
)
from app.core.samba_shares import snapshot as samba_shares_snapshot
from app.core.system_admin import (
    backup_archive,
    enqueue,
    service_catalog,
    status as system_status,
)
from app.core.system_auth import Identity, require_csrf, require_session
from app.core.torrent_status import snapshot as torrent_snapshot


router = APIRouter(prefix="/api/v1", tags=["administration"])
SECRET_DIR = Path("/var/lib/srv-control/action-secrets")
DOMAIN_IMPORT_DIR = Path("/var/lib/srv-control/domain-imports")
UPLOAD_CHUNK = 4 * 1024 * 1024
MAX_DOMAIN_IMPORT = 2 * 1024 * 1024 * 1024 * 1024  # 2 TiB safety ceiling


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


def _full_admin(request: Request, *, csrf: bool = False) -> tuple[dict, Identity]:
    session = require_session(request)
    if csrf:
        require_csrf(request, session)
    identity = _identity(session)
    if not is_full_admin(identity):
        raise HTTPException(status_code=403, detail="full administrator permission required")
    return session, identity


def _client_ip(request: Request) -> str | None:
    return request.client.host if request.client else None


async def _payload(request: Request) -> dict:
    try:
        value = await request.json()
    except Exception:
        value = {}
    return value if isinstance(value, dict) else {}


def _queue(
    action: str,
    identity: Identity,
    request: Request,
    payload: dict | None = None,
) -> dict:
    try:
        return enqueue(action, identity.username, _client_ip(request), payload)
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc


def _store_secret(value: str) -> str:
    value = str(value or "")
    if not value:
        raise HTTPException(status_code=400, detail="password is required")
    if "\x00" in value or "\r" in value or "\n" in value:
        raise HTTPException(status_code=400, detail="invalid password value")
    SECRET_DIR.mkdir(parents=True, exist_ok=True)
    try:
        os.chmod(SECRET_DIR, 0o700)
    except Exception:
        pass
    token = secrets.token_urlsafe(24)
    path = SECRET_DIR / token
    fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    try:
        os.write(fd, value.encode("utf-8"))
        os.fsync(fd)
    finally:
        os.close(fd)
    return token


async def _store_domain_import(upload: UploadFile) -> tuple[str, Path, int]:
    filename = Path(upload.filename or "domain-backup.tar").name
    if not filename or filename in {".", ".."}:
        raise HTTPException(status_code=400, detail="invalid upload filename")
    DOMAIN_IMPORT_DIR.mkdir(parents=True, exist_ok=True)
    try:
        os.chmod(DOMAIN_IMPORT_DIR, 0o700)
    except Exception:
        pass
    token = secrets.token_urlsafe(24)
    target = DOMAIN_IMPORT_DIR / f"{token}.upload"
    written = 0
    free = shutil.disk_usage(DOMAIN_IMPORT_DIR).free
    dynamic_limit = max(0, int(free * 0.90))
    limit = min(MAX_DOMAIN_IMPORT, dynamic_limit)
    if limit <= 0:
        raise HTTPException(status_code=507, detail="insufficient disk space for domain backup upload")
    try:
        with target.open("xb") as handle:
            os.chmod(target, 0o600)
            while True:
                chunk = await upload.read(UPLOAD_CHUNK)
                if not chunk:
                    break
                written += len(chunk)
                if written > limit:
                    raise HTTPException(status_code=413, detail="domain backup upload exceeds safe disk limit")
                handle.write(chunk)
            handle.flush()
            os.fsync(handle.fileno())
    except Exception:
        target.unlink(missing_ok=True)
        raise
    if written == 0:
        target.unlink(missing_ok=True)
        raise HTTPException(status_code=400, detail="uploaded backup is empty")
    metadata = target.with_suffix(".name")
    metadata.write_text(filename + "\n", encoding="utf-8")
    os.chmod(metadata, 0o600)
    return token, target, written


@router.get("/access/directory")
def access_directory(request: Request):
    _, identity = _admin(request)
    return {
        "ok": True,
        "data": {"identity": identity.as_dict(), **identity_directory_snapshot()},
        "error": None,
    }


@router.get("/system/configuration")
def configuration(request: Request):
    session = require_session(request)
    identity = _identity(session)
    data = system_status(
        include_actions=identity.is_admin,
        include_service_detail=identity.is_admin,
    )
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
    return {"ok": True, "data": _queue("backup-delete", identity, request, {"backup_id": backup_id}), "error": None}


@router.post("/system/backups/{backup_id}/restore")
def backup_restore(backup_id: str, request: Request):
    _, identity = _admin(request, csrf=True)
    if backup_archive(backup_id) is None:
        raise HTTPException(status_code=404, detail="backup not found")
    return {"ok": True, "data": _queue("backup-restore", identity, request, {"backup_id": backup_id}), "error": None}


@router.get("/system/backups/{backup_id}/download")
def backup_download(backup_id: str, request: Request):
    _admin(request)
    archive = backup_archive(backup_id)
    if archive is None:
        raise HTTPException(status_code=404, detail="backup not found")
    return FileResponse(path=archive, filename=archive.name, media_type="application/gzip")


@router.get("/services")
def services(request: Request):
    session = require_session(request)
    identity = _identity(session)
    visible = []
    for raw in service_catalog(include_detail=True):
        module = str(raw.get("permission_module") or "")
        if identity.is_admin or has_permission(identity, module, "read"):
            item = dict(raw)
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
    elif service_id == "samba-ad-dc":
        require_permission(identity, "samba", "write")
        action = "service-install-samba-dc"
    else:
        raise HTTPException(status_code=404, detail="service not found")
    return {"ok": True, "data": _queue(action, identity, request), "error": None}


@router.post("/services/{service_id}/remove")
async def service_remove(service_id: str, request: Request):
    session = require_session(request)
    require_csrf(request, session)
    identity = _identity(session)
    if service_id == "adguard-vpn":
        require_permission(identity, "network", "write")
        action = "service-remove-adguard-vpn"
        payload = {}
    elif service_id == "pxe-server":
        require_permission(identity, "pxe", "write")
        action = "service-remove-pxe"
        payload = {}
    elif service_id == "samba-ad-dc":
        require_permission(identity, "samba", "write")
        action = "service-remove-samba-dc"
        payload = await _payload(request)
        payload["purge_domain_data"] = False
    else:
        raise HTTPException(status_code=404, detail="service not found")
    return {"ok": True, "data": _queue(action, identity, request, payload), "error": None}


@router.get("/samba")
def samba_status(request: Request):
    session = require_session(request)
    identity = _identity(session)
    require_permission(identity, "samba", "read")
    data = samba_domain_snapshot()
    data["backups"] = samba_backup_items()
    data["can_write"] = identity.is_admin or has_permission(identity, "samba", "write")
    data["full_admin"] = is_full_admin(identity)
    return {"ok": True, "data": data, "error": None}


@router.post("/samba/password-policy")
async def samba_password_policy(request: Request):
    session = require_session(request)
    require_csrf(request, session)
    identity = _identity(session)
    require_permission(identity, "samba", "write")
    return {"ok": True, "data": _queue("samba-password-policy", identity, request, await _payload(request)), "error": None}


@router.post("/samba/users")
async def samba_user_create(request: Request):
    session = require_session(request)
    require_csrf(request, session)
    identity = _identity(session)
    require_permission(identity, "samba", "write")
    payload = await _payload(request)
    password = str(payload.pop("password", "") or "")
    if password:
        payload["secret_ref"] = _store_secret(password)
    return {"ok": True, "data": _queue("samba-user-create", identity, request, payload), "error": None}


@router.post("/samba/users/{username}/update")
async def samba_user_update(username: str, request: Request):
    session = require_session(request)
    require_csrf(request, session)
    identity = _identity(session)
    require_permission(identity, "samba", "write")
    payload = await _payload(request)
    payload["username"] = username
    return {"ok": True, "data": _queue("samba-user-update", identity, request, payload), "error": None}


@router.post("/samba/users/{username}/password")
async def samba_user_password(username: str, request: Request):
    session = require_session(request)
    require_csrf(request, session)
    identity = _identity(session)
    require_permission(identity, "samba", "write")
    payload = await _payload(request)
    password = str(payload.pop("password", "") or "")
    payload["username"] = username
    payload["secret_ref"] = _store_secret(password)
    return {"ok": True, "data": _queue("samba-user-password", identity, request, payload), "error": None}


@router.post("/samba/users/{username}/{operation}")
def samba_user_operation(username: str, operation: str, request: Request):
    session = require_session(request)
    require_csrf(request, session)
    identity = _identity(session)
    require_permission(identity, "samba", "write")
    actions = {
        "enable": "samba-user-enable",
        "disable": "samba-user-disable",
        "unlock": "samba-user-unlock",
        "delete": "samba-user-delete",
    }
    action = actions.get(operation)
    if action is None:
        raise HTTPException(status_code=404, detail="operation not found")
    return {"ok": True, "data": _queue(action, identity, request, {"username": username}), "error": None}


@router.post("/samba/groups")
async def samba_group_create(request: Request):
    session = require_session(request)
    require_csrf(request, session)
    identity = _identity(session)
    require_permission(identity, "samba", "write")
    return {"ok": True, "data": _queue("samba-group-create", identity, request, await _payload(request)), "error": None}


@router.post("/samba/groups/{group_name}/update")
async def samba_group_update(group_name: str, request: Request):
    session = require_session(request)
    require_csrf(request, session)
    identity = _identity(session)
    require_permission(identity, "samba", "write")
    payload = await _payload(request)
    payload["group_name"] = group_name
    return {"ok": True, "data": _queue("samba-group-update", identity, request, payload), "error": None}


@router.post("/samba/groups/{group_name}/members")
async def samba_group_members(group_name: str, request: Request):
    session = require_session(request)
    require_csrf(request, session)
    identity = _identity(session)
    require_permission(identity, "samba", "write")
    payload = await _payload(request)
    payload["group_name"] = group_name
    return {"ok": True, "data": _queue("samba-group-members", identity, request, payload), "error": None}


@router.post("/samba/groups/{group_name}/delete")
def samba_group_delete(group_name: str, request: Request):
    session = require_session(request)
    require_csrf(request, session)
    identity = _identity(session)
    require_permission(identity, "samba", "write")
    return {"ok": True, "data": _queue("samba-group-delete", identity, request, {"group_name": group_name}), "error": None}


@router.post("/samba/backups")
async def samba_backup_create(request: Request):
    session = require_session(request)
    require_csrf(request, session)
    identity = _identity(session)
    require_permission(identity, "samba", "write")
    payload = await _payload(request)
    mode = str(payload.get("mode") or "domain-config")
    if mode not in {"domain-config", "full"}:
        raise HTTPException(status_code=400, detail="invalid Samba backup mode")
    payload["mode"] = mode
    return {"ok": True, "data": _queue("samba-backup-create", identity, request, payload), "error": None}


@router.get("/samba/backups/{backup_id}/download")
def samba_backup_download(backup_id: str, request: Request):
    session = require_session(request)
    identity = _identity(session)
    require_permission(identity, "samba", "write")
    archive = samba_backup_archive(backup_id)
    if archive is None:
        raise HTTPException(status_code=404, detail="domain backup not found")
    return FileResponse(path=archive, filename=archive.name, media_type="application/octet-stream")


@router.post("/samba/backups/import")
async def samba_backup_import(request: Request, backup: UploadFile = File(...)):
    _, identity = _full_admin(request, csrf=True)
    token, _, size = await _store_domain_import(backup)
    return {
        "ok": True,
        "data": _queue("samba-backup-restore", identity, request, {"import_ref": token, "size": size}),
        "error": None,
    }


@router.get("/shares")
def samba_shares(request: Request):
    session = require_session(request)
    identity = _identity(session)
    require_permission(identity, "shares", "read")
    data = samba_shares_snapshot()
    data["can_write"] = identity.is_admin or has_permission(identity, "shares", "write")
    data["full_admin"] = is_full_admin(identity)
    return {"ok": True, "data": data, "error": None}


@router.post("/shares")
async def samba_share_create(request: Request):
    session = require_session(request)
    require_csrf(request, session)
    identity = _identity(session)
    require_permission(identity, "shares", "write")
    return {"ok": True, "data": _queue("samba-share-create", identity, request, await _payload(request)), "error": None}


@router.post("/shares/{share_name}/update")
async def samba_share_update(share_name: str, request: Request):
    session = require_session(request)
    require_csrf(request, session)
    identity = _identity(session)
    require_permission(identity, "shares", "write")
    payload = await _payload(request)
    payload["share_name"] = share_name
    return {"ok": True, "data": _queue("samba-share-update", identity, request, payload), "error": None}


@router.post("/shares/{share_name}/delete")
async def samba_share_delete(share_name: str, request: Request):
    session = require_session(request)
    require_csrf(request, session)
    identity = _identity(session)
    require_permission(identity, "shares", "write")
    payload = await _payload(request)
    delete_data = bool(payload.get("delete_data"))
    if delete_data and not is_full_admin(identity):
        raise HTTPException(status_code=403, detail="full administrator required to delete share data")
    return {
        "ok": True,
        "data": _queue(
            "samba-share-delete",
            identity,
            request,
            {"share_name": share_name, "delete_data": delete_data},
        ),
        "error": None,
    }


@router.get("/adguard")
def adguard_status(request: Request):
    session = require_session(request)
    identity = _identity(session)
    require_permission(identity, "network", "read")
    item = next(item for item in service_catalog(include_detail=True) if item["id"] == "adguard-vpn")
    item = dict(item)
    item["can_write"] = identity.is_admin or has_permission(identity, "network", "write")
    return {"ok": True, "data": item, "error": None}


@router.post("/adguard/config")
async def adguard_config(request: Request):
    session = require_session(request)
    require_csrf(request, session)
    identity = _identity(session)
    require_permission(identity, "network", "write")
    return {
        "ok": True,
        "data": _queue("service-configure-adguard-vpn", identity, request, await _payload(request)),
        "error": None,
    }


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


@router.get("/minecraft")
def minecraft_status(request: Request):
    session = require_session(request)
    identity = _identity(session)
    require_permission(identity, "minecraft", "read")
    data = minecraft_snapshot()
    data["can_write"] = identity.is_admin or has_permission(identity, "minecraft", "write")
    return {"ok": True, "data": data, "error": None}


@router.post("/minecraft/config")
async def minecraft_config(request: Request):
    session = require_session(request)
    require_csrf(request, session)
    identity = _identity(session)
    require_permission(identity, "minecraft", "write")
    return {
        "ok": True,
        "data": _queue("minecraft-configure", identity, request, await _payload(request)),
        "error": None,
    }


@router.post("/minecraft/{operation}")
def minecraft_action(operation: str, request: Request):
    session = require_session(request)
    require_csrf(request, session)
    identity = _identity(session)
    require_permission(identity, "minecraft", "write")
    actions = {
        "start": "minecraft-start",
        "stop": "minecraft-stop",
        "restart": "minecraft-restart",
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
