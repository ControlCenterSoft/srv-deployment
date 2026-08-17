from __future__ import annotations

from fastapi import APIRouter, Request
from fastapi.responses import HTMLResponse
from fastapi.templating import Jinja2Templates

from app.core.config import settings


router = APIRouter(tags=["ui"])
templates = Jinja2Templates(directory="/opt/srv-control/templates")


@router.get("/login", response_class=HTMLResponse)
def login(request: Request):
    return templates.TemplateResponse(
        request=request,
        name="login.html",
        context={"app_name": settings.name},
    )


@router.get("/", response_class=HTMLResponse)
def shell(request: Request):
    return templates.TemplateResponse(
        request=request,
        name="shell.html",
        context={
            "app_name": settings.name,
            "canonical_host": settings.canonical_host,
        },
    )


@router.get("/ui/dashboard", response_class=HTMLResponse)
def dashboard(request: Request):
    return templates.TemplateResponse(
        request=request,
        name="dashboard.html",
        context={"app_name": settings.name},
    )


@router.get("/ui/module/system", response_class=HTMLResponse)
def system_module(request: Request):
    return templates.TemplateResponse(
        request=request,
        name="system.html",
        context={"app_name": settings.name},
    )


@router.get("/ui/module/internet", response_class=HTMLResponse)
def internet_module(request: Request):
    return templates.TemplateResponse(
        request=request,
        name="internet.html",
        context={"app_name": settings.name},
    )


@router.get("/ui/module/access", response_class=HTMLResponse)
def access_module(request: Request):
    return templates.TemplateResponse(
        request=request,
        name="access.html",
        context={"app_name": settings.name},
    )
