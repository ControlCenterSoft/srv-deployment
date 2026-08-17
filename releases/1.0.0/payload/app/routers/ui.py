from __future__ import annotations

from fastapi import APIRouter
from fastapi import Request
from fastapi.responses import HTMLResponse
from fastapi.templating import Jinja2Templates

from app.core.config import settings


router = APIRouter(
    tags=["ui"],
)


templates = Jinja2Templates(
    directory="/opt/srv-control/templates"
)


MODULES = {
    "samba": {
        "title": "Домен / Samba",
        "description": (
            "Управление доменом hm.dm, пользователями, "
            "группами, политиками и файловыми ресурсами."
        ),
        "stage": "будет подключён отдельным этапом",
    },

    "pxe": {
        "title": "PXE / Установка ОС",
        "description": (
            "Windows 11, Linux, профили компьютеров, "
            "образы и группы программ."
        ),
        "stage": "будет подключён отдельным этапом",
    },

    "minecraft": {
        "title": "Minecraft",
        "description": (
            "Управление Minecraft Bedrock, игроками, "
            "мирами, резервными копиями и обновлениями."
        ),
        "stage": "будет подключён отдельным этапом",
    },

    "downloads": {
        "title": "Загрузки",
        "description": (
            "Deluge и TorrServer для Lampa."
        ),
        "stage": "будет подключён отдельным этапом",
    },

    "docker": {
        "title": "Docker",
        "description": (
            "Контейнеры, images, compose stacks, "
            "volumes, networks и журналы."
        ),
        "stage": "будет подключён отдельным этапом",
    },
}


@router.get(
    "/",
    response_class=HTMLResponse,
)
def shell(
    request: Request,
):
    return templates.TemplateResponse(
        request=request,
        name="shell.html",
        context={
            "app_name": settings.name,
            "canonical_host": settings.canonical_host,
        },
    )


@router.get(
    "/ui/dashboard",
    response_class=HTMLResponse,
)
def dashboard(
    request: Request,
):
    return templates.TemplateResponse(
        request=request,
        name="dashboard.html",
        context={
            "app_name": settings.name,
        },
    )


@router.get(
    "/ui/module/system",
    response_class=HTMLResponse,
)
def system_module(
    request: Request,
):
    return templates.TemplateResponse(
        request=request,
        name="system.html",
        context={
            "app_name": settings.name,
        },
    )


@router.get(
    "/ui/module/internet",
    response_class=HTMLResponse,
)
def internet_module(
    request: Request,
):
    return templates.TemplateResponse(
        request=request,
        name="internet.html",
        context={
            "app_name": settings.name,
        },
    )


@router.get(
    "/ui/module/{module_name}",
    response_class=HTMLResponse,
)
def module_placeholder(
    request: Request,
    module_name: str,
):
    item = MODULES.get(
        module_name,
        {
            "title": "Модуль",
            "description": "Раздел пока не существует.",
            "stage": "не настроен",
        },
    )

    return templates.TemplateResponse(
        request=request,
        name="placeholder.html",
        context={
            "module": item,
        },
    )
