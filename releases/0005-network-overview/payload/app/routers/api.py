from __future__ import annotations

import asyncio
import json
from datetime import datetime, timezone
from pathlib import Path

from fastapi import APIRouter
from fastapi.responses import StreamingResponse
from sqlalchemy import text

from app.core.metrics import snapshot
from app.core.network import snapshot as network_snapshot
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
            with path.open(
                "r",
                encoding="utf-8",
            ) as handle:
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


@router.get("/health")
def health():
    database = "error"

    try:
        with engine.connect() as connection:
            connection.execute(
                text(
                    "SELECT 1"
                )
            )

        database = "ok"

    except Exception:
        pass

    return {
        "ok": database == "ok",
        "data": {
            "service": "srv-control",
            "database": database,
            "timestamp": datetime.now(
                timezone.utc
            ).isoformat(),
            "release": release_metadata(),
            "deployment": deployment_metadata(),
        },
        "error": (
            None
            if database == "ok"
            else "database unavailable"
        ),
    }


@router.get("/dashboard/metrics")
def dashboard_metrics():
    return {
        "ok": True,
        "data": snapshot(),
        "error": None,
    }


@router.get("/network/overview")
def network_overview():
    return {
        "ok": True,
        "data": network_snapshot(),
        "error": None,
    }


@router.get("/dashboard/stream")
async def dashboard_stream():
    async def event_stream():
        while True:
            payload = {
                "ok": True,
                "data": snapshot(),
                "error": None,
            }

            yield (
                "event: metrics\n"
                f"data: {json.dumps(payload, ensure_ascii=False)}\n\n"
            )

            await asyncio.sleep(2)

    return StreamingResponse(
        event_stream(),
        media_type="text/event-stream",
        headers={
            "Cache-Control": "no-cache",
            "X-Accel-Buffering": "no",
        },
    )
