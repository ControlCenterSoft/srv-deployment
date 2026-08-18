from __future__ import annotations

from fastapi import APIRouter, HTTPException, Request

from app.core.system_admin import backup_archive, enqueue
from app.core.system_auth import Identity, require_csrf, require_session


router = APIRouter(prefix="/api/v1/system", tags=["system-2.0"])
MAX_BULK_BACKUPS = 200


def _identity(session: dict) -> Identity:
    identity = session.get("identity")
    if not isinstance(identity, Identity):
        raise HTTPException(status_code=401, detail="authentication required")
    if not identity.is_admin:
        raise HTTPException(status_code=403, detail="server administrator permission required")
    return identity


def _client_ip(request: Request) -> str | None:
    return request.client.host if request.client else None


@router.post("/backups/delete-many")
async def backup_delete_many(request: Request):
    session = require_session(request)
    require_csrf(request, session)
    identity = _identity(session)
    try:
        body = await request.json()
    except Exception as exc:
        raise HTTPException(status_code=400, detail="invalid JSON payload") from exc
    raw = body.get("backup_ids") if isinstance(body, dict) else None
    if not isinstance(raw, list):
        raise HTTPException(status_code=400, detail="backup_ids must be an array")

    backup_ids: list[str] = []
    seen: set[str] = set()
    for item in raw:
        backup_id = str(item or "").strip()
        if not backup_id or backup_id in seen:
            continue
        seen.add(backup_id)
        backup_ids.append(backup_id)

    if not backup_ids:
        raise HTTPException(status_code=400, detail="select at least one backup")
    if len(backup_ids) > MAX_BULK_BACKUPS:
        raise HTTPException(
            status_code=400,
            detail=f"a maximum of {MAX_BULK_BACKUPS} backups may be deleted at once",
        )

    missing = [backup_id for backup_id in backup_ids if backup_archive(backup_id) is None]
    if missing:
        preview = ", ".join(missing[:5])
        suffix = "…" if len(missing) > 5 else ""
        raise HTTPException(status_code=404, detail=f"backup not found: {preview}{suffix}")

    queued = [
        enqueue(
            "backup-delete",
            identity.username,
            _client_ip(request),
            {"backup_id": backup_id, "bulk": True},
        )
        for backup_id in backup_ids
    ]
    return {
        "ok": True,
        "data": {
            "count": len(queued),
            "backup_ids": backup_ids,
            "requests": queued,
        },
        "error": None,
    }
