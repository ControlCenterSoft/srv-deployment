from __future__ import annotations

from fastapi import FastAPI, Request
from fastapi.responses import JSONResponse, RedirectResponse
from fastapi.staticfiles import StaticFiles

from app.core.config import settings
from app.core.system_auth import parse_session
from app.routers.admin import router as admin_router
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
    StaticFiles(directory="/opt/srv-control/static"),
    name="static",
)

app.include_router(api_router)
app.include_router(admin_router)
app.include_router(ui_router)

PUBLIC_EXACT = {
    "/login",
    "/api/v1/health",
    "/api/v1/auth/login",
    "/api/v1/auth/sso",
    "/api/v1/auth/status",
}
PUBLIC_PREFIXES = ("/static/",)


@app.middleware("http")
async def authentication_gate(request: Request, call_next):
    path = request.url.path
    is_public = path in PUBLIC_EXACT or any(path.startswith(prefix) for prefix in PUBLIC_PREFIXES)
    if not is_public and parse_session(request) is None:
        if path.startswith("/api/"):
            return JSONResponse(
                {"ok": False, "data": None, "error": "authentication required"},
                status_code=401,
            )
        return RedirectResponse(url="/login", status_code=303)
    return await call_next(request)


@app.middleware("http")
async def security_headers(request: Request, call_next):
    response = await call_next(request)
    response.headers["X-Content-Type-Options"] = "nosniff"
    response.headers["X-Frame-Options"] = "SAMEORIGIN"
    response.headers["Referrer-Policy"] = "same-origin"
    response.headers["Permissions-Policy"] = "camera=(), microphone=(), geolocation=()"
    response.headers["Content-Security-Policy"] = (
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
