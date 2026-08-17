from __future__ import annotations

import asyncio
import json
from datetime import datetime, timezone
from pathlib import Path

from fastapi import APIRouter, HTTPException, Request
from fastapi.responses import JSONResponse, StreamingResponse
from sqlalchemy import text

from app.core.metrics import snapshot
from app.core.network import snapshot as network_snapshot
from app.core.network_diagnostics import run as network_diagnostics
from app.core.network_plan import build_plan
from app.core.network_plan import capabilities as network_capabilities
from app.core.rbac import (
    MODULES,
    delete_grant,
    list_grants,
    permissions_for,
    require_permission,
    upsert_grant,
)
from app.core.system_admin import ALLOWED_ACTIONS, enqueue as enqueue_system_action
from app.core.system_admin import status as system_admin_status
from app.core.system_auth import (
    COOKIE_NAME,
    SESSION_TTL,
    Identity,
    authenticate_system,
    create_session,
    login_retry_after,
    parse_session,
    record_login_result,
    require_csrf,
    require_session,
    sso_identity,
)
from app.database import engine


router = APIRouter(prefix="/api/v1", tags=["api"])
RELEASE_METADATA_FILE = Path("/var/lib/srv-control/release.json")
DEPLOYMENT_STATUS_FILE = Path("/var/lib/srv-control/deployment-status.json")


def _load_string_metadata(path: Path, defaults: dict[str, str | None]) -> dict[str, str | None]:
    metadata = dict(defaults)
    try:
        if path.exists():
            payload = json.loads(path.read_text(encoding="utf-8"))
            if isinstance(payload, dict):
                for key in metadata:
                    value = payload.get(key)
                    if isinstance(value, str):
                        metadata[key] = value
    except Exception:
        pass
    return metadata


def release_metadata() -> dict[str, str | None]:
    return _load_string_metadata(
        RELEASE_METADATA_FILE,
        {"version": None, "release_id": None, "synced_at": None, "git_sha": None},
    )


def deployment_metadata() -> dict[str, str | None]:
    return _load_string_metadata(
        DEPLOYMENT_STATUS_FILE,
        {
            "result": None,
            "stage": None,
            "release_id": None,
            "version": None,
            "remote_sha": None,
            "release_synced_at": None,
            "deployment_finished_at": None,
            "healthchecked_at": None,
        },
    )


def _client_ip(request: Request) -> str | None:
    return request.client.host if request.client else None


def _secure_cookie(request: Request) -> bool:
    forwarded = request.headers.get("X-Forwarded-Proto", "").lower()
    return request.url.scheme == "https" or forwarded == "https"


def _identity(session: dict) -> Identity:
    identity = session.get("identity")
    if not isinstance(identity, Identity):
        raise HTTPException(status_code=401, detail="authentication required")
    return identity


def _require_admin(session: dict) -> Identity:
    identity = _identity(session)
    if not identity.is_admin:
        raise HTTPException(status_code=403, detail="server administrator permission required")
    return identity


def _session_response(request: Request, identity: Identity) -> JSONResponse:
    token, csrf = create_session(identity)
    response = JSONResponse(
        {
            "ok": True,
            "data": {
                "authenticated": True,
                "identity": identity.as_dict(),
                "permissions": permissions_for(identity),
                "csrf_token": csrf,
            },
            "error": None,
        }
    )
    response.set_cookie(
        COOKIE_NAME,
        token,
        max_age=SESSION_TTL,
        httponly=True,
        samesite="strict",
        secure=_secure_cookie(request),
        path="/",
    )
    return response


def _audit(*, actor: str | None, client_ip: str | None, action: str, success: bool, details: dict | None = None) -> None:
    try:
        with engine.begin() as connection:
            connection.execute(
                text(
                    """
                    INSERT INTO audit_events
                        (actor, client_ip, module, action, success, details)
                    VALUES
                        (:actor, :client_ip, 'system', :action, :success,
                         CAST(:details AS jsonb))
                    """
                ),
                {
                    "actor": actor,
                    "client_ip": client_ip,
                    "action": action,
                    "success": success,
                    "details": json.dumps(details or {}, ensure_ascii=False),
                },
            )
    except Exception:
        pass


@router.get("/health")
def health():
    database = "error"
    try:
        with engine.connect() as connection:
            connection.execute(text("SELECT 1"))
        database = "ok"
    except Exception:
        pass
    return {
        "ok": database == "ok",
        "data": {
            "service": "srv-control",
            "database": database,
            "timestamp": datetime.now(timezone.utc).isoformat(),
            "release": release_metadata(),
            "deployment": deployment_metadata(),
        },
        "error": None if database == "ok" else "database unavailable",
    }


@router.get("/auth/status")
def auth_status(request: Request):
    session = parse_session(request)
    if session is None:
        return {
            "ok": True,
            "data": {
                "authenticated": False,
                "identity": None,
                "permissions": {},
                "csrf_token": None,
            },
            "error": None,
        }
    identity = _identity(session)
    return {
        "ok": True,
        "data": {
            "authenticated": True,
            "identity": identity.as_dict(),
            "permissions": permissions_for(identity),
            "csrf_token": session.get("csrf"),
        },
        "error": None,
    }


@router.post("/auth/login")
async def auth_login(request: Request):
    try:
        payload = await request.json()
    except Exception:
        payload = {}
    username = str(payload.get("username") or "").strip()
    password = str(payload.get("password") or "")
    client_ip = _client_ip(request)

    retry_after = login_retry_after(username, client_ip)
    if retry_after > 0:
        _audit(
            actor=username or None,
            client_ip=client_ip,
            action="auth.login",
            success=False,
            details={"reason": "rate-limited"},
        )
        raise HTTPException(
            status_code=429,
            detail="too many login attempts; try again later",
            headers={"Retry-After": str(retry_after)},
        )

    identity = authenticate_system(username, password)
    if identity is None:
        record_login_result(username, client_ip, False)
        _audit(actor=username or None, client_ip=client_ip, action="auth.login", success=False)
        raise HTTPException(status_code=401, detail="invalid system credentials")

    record_login_result(username, client_ip, True)
    response = _session_response(request, identity)
    _audit(
        actor=identity.username,
        client_ip=client_ip,
        action="auth.login",
        success=True,
        details={"source": identity.auth_source, "uid": identity.uid},
    )
    return response


@router.get("/auth/sso")
def auth_sso(request: Request):
    identity = sso_identity(request)
    if identity is None:
        raise HTTPException(status_code=401, detail="SSO identity unavailable")
    response = _session_response(request, identity)
    _audit(
        actor=identity.username,
        client_ip=_client_ip(request),
        action="auth.sso",
        success=True,
        details={"uid": identity.uid},
    )
    return response


@router.post("/auth/logout")
def auth_logout(request: Request):
    session = require_session(request)
    require_csrf(request, session)
    identity = _identity(session)
    response = JSONResponse({"ok": True, "data": None, "error": None})
    response.delete_cookie(COOKIE_NAME, path="/")
    _audit(actor=identity.username, client_ip=_client_ip(request), action="auth.logout", success=True)
    return response


@router.get("/access/modules")
def access_modules(request: Request):
    session = require_session(request)
    identity = _identity(session)
    return {
        "ok": True,
        "data": {
            "identity": identity.as_dict(),
            "modules": MODULES,
            "permissions": permissions_for(identity),
        },
        "error": None,
    }


@router.get("/access/grants")
def access_grants(request: Request):
    session = require_session(request)
    identity = _require_admin(session)
    return {
        "ok": True,
        "data": {"identity": identity.as_dict(), "modules": MODULES, "grants": list_grants()},
        "error": None,
    }


@router.post("/access/grants")
async def access_grant_upsert(request: Request):
    session = require_session(request)
    require_csrf(request, session)
    identity = _require_admin(session)
    try:
        payload = await request.json()
    except Exception:
        payload = {}
    try:
        grant = upsert_grant(
            group_name=str(payload.get("group_name") or ""),
            source=str(payload.get("source") or ""),
            module=str(payload.get("module") or ""),
            access=str(payload.get("access") or ""),
            actor=identity.username,
        )
    except ValueError as exc:
        raise HTTPException(status_code=400, detail=str(exc)) from exc
    _audit(
        actor=identity.username,
        client_ip=_client_ip(request),
        action="access.grant",
        success=True,
        details={"grant": {k: str(v) if k == "updated_at" else v for k, v in grant.items()}},
    )
    return {"ok": True, "data": grant, "error": None}


@router.delete("/access/grants/{grant_id}")
def access_grant_delete(grant_id: int, request: Request):
    session = require_session(request)
    require_csrf(request, session)
    identity = _require_admin(session)
    deleted = delete_grant(grant_id)
    if not deleted:
        raise HTTPException(status_code=404, detail="grant not found")
    _audit(
        actor=identity.username,
        client_ip=_client_ip(request),
        action="access.grant.delete",
        success=True,
        details={"grant_id": grant_id},
    )
    return {"ok": True, "data": {"deleted": grant_id}, "error": None}


@router.get("/dashboard/metrics")
def dashboard_metrics(request: Request):
    require_session(request)
    return {"ok": True, "data": snapshot(), "error": None}


@router.get("/system/admin")
def system_administration_status(request: Request):
    session = require_session(request)
    identity = _identity(session)
    data = system_admin_status(
        include_actions=identity.is_admin,
        include_service_detail=True,
    )
    data["auth"] = {
        "authenticated": True,
        "identity": identity.as_dict(),
        "csrf_token": session.get("csrf"),
    }
    return {"ok": True, "data": data, "error": None}


@router.post("/system/actions/{action}")
async def system_action(action: str, request: Request):
    if action not in ALLOWED_ACTIONS:
        raise HTTPException(status_code=404, detail="unknown system action")
    session = require_session(request)
    require_csrf(request, session)
    identity = _require_admin(session)
    try:
        payload = await request.json()
    except Exception:
        payload = {}

    if action == "reboot" and payload.get("confirm") != "REBOOT":
        raise HTTPException(status_code=400, detail="reboot confirmation is required")
    if action == "service-remove-adguard-vpn" and payload.get("confirm") != "REMOVE":
        raise HTTPException(status_code=400, detail="service removal confirmation is required")

    try:
        queued = enqueue_system_action(action, identity.username, _client_ip(request))
    except Exception as exc:
        _audit(
            actor=identity.username,
            client_ip=_client_ip(request),
            action=f"system.{action}",
            success=False,
            details={"reason": str(exc)},
        )
        raise HTTPException(status_code=500, detail="failed to queue system action") from exc

    _audit(
        actor=identity.username,
        client_ip=_client_ip(request),
        action=f"system.{action}",
        success=True,
        details=queued,
    )
    return {"ok": True, "data": queued, "error": None}


@router.get("/network/overview")
def network_overview(request: Request):
    session = require_session(request)
    require_permission(_identity(session), "network", "read")
    return {"ok": True, "data": network_snapshot(), "error": None}


@router.get("/network/diagnostics")
def network_diagnostics_endpoint(request: Request):
    session = require_session(request)
    require_permission(_identity(session), "network", "read")
    return {"ok": True, "data": network_diagnostics(), "error": None}


@router.get("/network/capabilities")
def network_capability_overview(request: Request):
    session = require_session(request)
    require_permission(_identity(session), "network", "read")
    return {"ok": True, "data": network_capabilities(), "error": None}


@router.post("/network/plan")
async def network_plan(request: Request):
    session = require_session(request)
    require_permission(_identity(session), "network", "read")
    try:
        payload = await request.json()
    except Exception:
        payload = None
    current = network_snapshot()
    plan = build_plan(payload, current)
    return {
        "ok": plan.get("valid") is True,
        "data": {
            "plan": plan,
            "current": current,
            "capabilities": network_capabilities(),
        },
        "error": None if plan.get("valid") is True else "network plan validation failed",
    }


async def metric_event_stream():
    while True:
        try:
            payload = {"ok": True, "data": snapshot(), "error": None}
            yield "event: metrics\ndata: " + json.dumps(payload, ensure_ascii=False, separators=(",", ":")) + "\n\n"
        except asyncio.CancelledError:
            break
        except Exception as exc:
            payload = {"ok": False, "data": None, "error": str(exc)[:300]}
            yield "event: metrics\ndata: " + json.dumps(payload, ensure_ascii=False, separators=(",", ":")) + "\n\n"
        await asyncio.sleep(2)


@router.get("/dashboard/stream")
async def dashboard_stream(request: Request):
    require_session(request)
    return StreamingResponse(
        metric_event_stream(),
        media_type="text/event-stream",
        headers={"Cache-Control": "no-cache", "X-Accel-Buffering": "no"},
    )
