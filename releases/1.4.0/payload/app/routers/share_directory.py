from __future__ import annotations

from fastapi import APIRouter, HTTPException, Request

from app.core.rbac import require_permission
from app.core.samba_domain import snapshot as samba_domain_snapshot
from app.core.system_auth import Identity, require_session


router = APIRouter(prefix="/api/v1", tags=["shares"])


def _identity(request: Request) -> Identity:
    session = require_session(request)
    identity = session.get("identity")
    if not isinstance(identity, Identity):
        raise HTTPException(status_code=401, detail="authentication required")
    return identity


@router.get("/shares/directory")
def share_directory(request: Request):
    identity = _identity(request)
    require_permission(identity, "shares", "read")
    source = samba_domain_snapshot()
    users = []
    for item in source.get("users") or []:
        if not isinstance(item, dict):
            continue
        username = str(item.get("username") or "").strip()
        if username:
            users.append({
                "name": username,
                "display_name": item.get("display_name") or username,
                "enabled": bool(item.get("enabled", True)),
            })
    groups = []
    for item in source.get("groups") or []:
        if not isinstance(item, dict):
            continue
        name = str(item.get("name") or "").strip()
        if name:
            groups.append({"name": name, "protected": bool(item.get("protected"))})
    return {
        "ok": True,
        "data": {
            "domain": (source.get("domain") or {}).get("netbios_domain"),
            "users": users,
            "groups": groups,
        },
        "error": None,
    }
