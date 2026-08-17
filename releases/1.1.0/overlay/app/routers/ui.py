from __future__ import annotations

from fastapi import APIRouter, Request
from fastapi.responses import HTMLResponse
from fastapi.templating import Jinja2Templates

from app.core.config import settings


router = APIRouter(tags=["ui"])
templates = Jinja2Templates(directory="/opt/srv-control/templates")


def render(request: Request, name: str):
    return templates.TemplateResponse(
        request=request,
        name=name,
        context={"app_name": settings.name, "canonical_host": settings.canonical_host},
    )


@router.get("/login", response_class=HTMLResponse)
def login(request: Request):
    return render(request, "login.html")


@router.get("/", response_class=HTMLResponse)
def shell(request: Request):
    return render(request, "shell.html")


@router.get("/ui/dashboard", response_class=HTMLResponse)
def dashboard(request: Request):
    return render(request, "dashboard.html")


@router.get("/ui/module/system", response_class=HTMLResponse)
def system_module(request: Request):
    return render(request, "system.html")


@router.get("/ui/module/internet", response_class=HTMLResponse)
def internet_module(request: Request):
    return render(request, "internet.html")


@router.get("/ui/module/access", response_class=HTMLResponse)
def access_module(request: Request):
    return render(request, "access.html")


@router.get("/ui/module/services", response_class=HTMLResponse)
def services_module(request: Request):
    return render(request, "services.html")


@router.get("/ui/module/adguard", response_class=HTMLResponse)
def adguard_module(request: Request):
    return render(request, "adguard.html")


@router.get("/ui/module/torrents", response_class=HTMLResponse)
def torrents_module(request: Request):
    return render(request, "torrents.html")
