from __future__ import annotations

import asyncio
import json
from datetime import datetime, timezone
from pathlib import Path

from fastapi import APIRouter, HTTPException, Request
from fastapi.responses import JSONResponse, StreamingResponse
from sqlalchemy import text

from app.core.auth import (
    COOKIE_NAME,
    SESSION_TTL,
    authenticate,
    change_password,
    create_session,
    parse_session,
    require_csrf,
    require_session,
)
from app.core.metrics import snapshot
from app.core.network import snapshot as network_snapshot
from app.core.network_diagnostics import run as network_diagnostics
from app.core.network_plan import build_plan
from app.core.network_plan import capabilities as network_capabilities
from app.core.system_admin import ALLOWED_ACTIONS, enqueue as enqueue_system_action
from app.core.system_admin import status as system_admin_status
from app.database import engine


router = APIRouter(
    prefix="/api/v1",
    tags=["api"],
)

RELEASE_METADATA_FILE = Path(
    "/var/lib/srv-control/release.json"
)
DEPLOYMENT_STATUS_FILE = Path(
    "/var/lib/srv-control/deployment-status.json"
)


def _load_string_metadata(
    path: Path,
    defaults: dict[str, str | None],
) -> dict[str, str | None]:
    metadata = dict(defaults)
    try:
        if path.exists():
            with path.open("r", encoding="utf-8") as handle:
                payload = json.load(handle)
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
        {
            "version": None,
            "release_id": None,
            "synced_at": None,
            "git_sha": None,
        },
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
    if request.client is None:
        return None
    return request.client.host


def _audit(
    *,
    actor: str | None,
    client_ip: str | None,
    action: str,
    success: bool,
    details: dict | None = None,
) -> None:
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
    return {
        "ok": True,
        "data": {
            "authenticated": session is not None,
            "username": session.get("u") if session else None,
            "must_change": bool(session.get("must_change")) if session else False,
            "csrf_token": session.get("csrf") if session else None,
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
    account = authenticate(username, password)

    if account is None:
        _audit(
            actor=username or None,
            client_ip=_client_ip(request),
            action="auth.login",
            success=False,
        )
        raise HTTPException(status_code=401, detail="invalid credentials")

    token, csrf = create_session(
        username,
        bool(account.get("must_change")),
    )
    response = JSONResponse(
        {
            "ok": True,
            "data": {
                "authenticated": True,
                "username": username,
                "must_change": bool(account.get("must_change")),
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
        secure=False,
        path="/",
    )
    _audit(
        actor=username,
        client_ip=_client_ip(request),
        action="auth.login",
        success=True,
    )
    return response


@router.post("/auth/logout")
def auth_logout(request: Request):
    session = require_session(request, allow_password_change=True)
    require_csrf(request, session)
    response = JSONResponse({"ok": True, "data": None, "error": None})
    response.delete_cookie(COOKIE_NAME, path="/")
    _audit(
        actor=str(session.get("u")),
        client_ip=_client_ip(request),
        action="auth.logout",
        success=True,
    )
    return response


@router.post("/auth/change-password")
async def auth_change_password(request: Request):
    session = require_session(request, allow_password_change=True)
    require_csrf(request, session)

    try:
        payload = await request.json()
    except Exception:
        payload = {}

    current_password = str(payload.get("current_password") or "")
    new_password = str(payload.get("new_password") or "")

    try:
        change_password(
            str(session.get("u")),
            current_password,
            new_password,
        )
    except ValueError as exc:
        _audit(
            actor=str(session.get("u")),
            client_ip=_client_ip(request),
            action="auth.change_password",
            success=False,
            details={"reason": str(exc)},
        )
        raise HTTPException(status_code=400, detail=str(exc)) from exc

    token, csrf = create_session(str(session.get("u")), False)
    response = JSONResponse(
        {
            "ok": True,
            "data": {
                "authenticated": True,
                "username": session.get("u"),
                "must_change": False,
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
        secure=False,
        path="/",
    )
    _audit(
        actor=str(session.get("u")),
        client_ip=_client_ip(request),
        action="auth.change_password",
        success=True,
    )
    return response


@router.get("/dashboard/metrics")
def dashboard_metrics():
    return {"ok": True, "data": snapshot(), "error": None}


@router.get("/system/admin")
def system_administration_status(request: Request):
    session = parse_session(request)
    data = system_admin_status()
    data["auth"] = {
        "authenticated": session is not None,
        "username": session.get("u") if session else None,
        "must_change": bool(session.get("must_change")) if session else False,
        "csrf_token": session.get("csrf") if session else None,
    }
    return {"ok": True, "data": data, "error": None}


@router.post("/system/actions/{action}")
async def system_action(action: str, request: Request):
    if action not in ALLOWED_ACTIONS:
        raise HTTPException(status_code=404, detail="unknown system action")

    session = require_session(request)
    require_csrf(request, session)

    try:
        payload = await request.json()
    except Exception:
        payload = {}

    if action == "reboot" and payload.get("confirm") != "REBOOT":
        raise HTTPException(status_code=400, detail="reboot confirmation is required")

    if action == "service-remove-adguard-vpn" and payload.get("confirm") != "REMOVE":
        raise HTTPException(status_code=400, detail="service removal confirmation is required")

    actor = str(session.get("u"))
    try:
        queued = enqueue_system_action(
            action,
            actor,
            _client_ip(request),
        )
    except Exception as exc:
        _audit(
            actor=actor,
            client_ip=_client_ip(request),
            action=f"system.{action}",
            success=False,
            details={"reason": str(exc)},
        )
        raise HTTPException(status_code=500, detail="failed to queue system action") from exc

    _audit(
        actor=actor,
        client_ip=_client_ip(request),
        action=f"system.{action}",
        success=True,
        details=queued,
    )
    return {"ok": True, "data": queued, "error": None}


@router.get("/network/overview")
def network_overview():
    return {"ok": True, "data": network_snapshot(), "error": None}


@router.get("/network/diagnostics")
def network_diagnostics_endpoint():
    return {"ok": True, "data": network_diagnostics(), "error": None}


@router.get("/network/capabilities")
def network_capability_overview():
    return {"ok": True, "data": network_capabilities(), "error": None}


@router.post("/network/plan")
async def network_plan(request: Request):
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
            yield (
                "event: metrics\n"
                "data: "
                + json.dumps(
                    payload,
                    ensure_ascii=False,
                    separators=(",", ":"),
                )
                + "\n\n"
            )
        except asyncio.CancelledError:
            break
        except Exception as exc:
            payload = {
                "ok": False,
                "data": None,
                "error": str(exc)[:300],
            }
            yield (
                "event: metrics\n"
                "data: "
                + json.dumps(
                    payload,
                    ensure_ascii=False,
                    separators=(",", ":"),
                )
                + "\n\n"
            )
        await asyncio.sleep(2)


@router.get("/dashboard/stream")
async def dashboard_stream():
    return StreamingResponse(
        metric_event_stream(),
        media_type="text/event-stream",
        headers={
            "Cache-Control": "no-cache",
            "X-Accel-Buffering": "no",
        },
    )
