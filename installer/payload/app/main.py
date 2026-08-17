from __future__ import annotations

from fastapi import FastAPI
from fastapi.staticfiles import StaticFiles

from app.core.config import settings
from app.routers.api import router as api_router
from app.routers.ui import router as ui_router


app = FastAPI(
    title=settings.name,
    docs_url="/api/docs",
    redoc_url=None,
    openapi_url="/api/openapi.json",
)


app.mount(
    "/static",
    StaticFiles(
        directory="/opt/srv-control/static"
    ),
    name="static",
)


app.include_router(
    api_router
)

app.include_router(
    ui_router
)


@app.middleware("http")
async def security_headers(
    request,
    call_next,
):
    response = await call_next(
        request
    )

    response.headers[
        "X-Content-Type-Options"
    ] = "nosniff"

    response.headers[
        "X-Frame-Options"
    ] = "SAMEORIGIN"

    response.headers[
        "Referrer-Policy"
    ] = "same-origin"

    response.headers[
        "Permissions-Policy"
    ] = (
        "camera=(), "
        "microphone=(), "
        "geolocation=()"
    )

    response.headers[
        "Content-Security-Policy"
    ] = (
        "default-src 'self'; "
        "script-src 'self'; "
        "style-src 'self'; "
        "img-src 'self' data:; "
        "connect-src 'self'; "
        "frame-src 'self'; "
        "frame-ancestors 'self'; "
        "base-uri 'self'; "
        "form-action 'self'"
    )

    return response
