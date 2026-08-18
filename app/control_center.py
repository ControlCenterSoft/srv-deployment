#!/usr/bin/env python3
import base64
import hashlib
import hmac
import html
import json
import os
import secrets
import time
from http import cookies
from urllib.parse import parse_qs

import pam

VERSION = "2.2.0"
SESSION_KEY_PATH = os.environ.get("CONTROL_CENTER_SESSION_KEY", "/etc/control-center/session.key")
SESSION_TTL = int(os.environ.get("CONTROL_CENTER_SESSION_TTL", "28800"))

NAV = (
    ("overview", "Обзор"),
    ("market", "Маркет"),
    ("rbac", "RBAC"),
    ("system", "Система"),
)


def _key():
    with open(SESSION_KEY_PATH, "rb") as fh:
        return fh.read().strip()


def _b64(data: bytes) -> str:
    return base64.urlsafe_b64encode(data).decode("ascii").rstrip("=")


def _unb64(value: str) -> bytes:
    return base64.urlsafe_b64decode(value + "=" * (-len(value) % 4))


def make_session(username: str) -> str:
    body = json.dumps({"u": username, "exp": int(time.time()) + SESSION_TTL}, separators=(",", ":")).encode()
    payload = _b64(body)
    sig = _b64(hmac.new(_key(), payload.encode(), hashlib.sha256).digest())
    return f"{payload}.{sig}"


def read_session(environ):
    raw = environ.get("HTTP_COOKIE", "")
    jar = cookies.SimpleCookie()
    try:
        jar.load(raw)
        token = jar.get("cc_session")
        if not token:
            return None
        payload, sig = token.value.rsplit(".", 1)
        expected = _b64(hmac.new(_key(), payload.encode(), hashlib.sha256).digest())
        if not hmac.compare_digest(sig, expected):
            return None
        data = json.loads(_unb64(payload))
        if int(data.get("exp", 0)) < int(time.time()):
            return None
        user = str(data.get("u", "")).strip()
        return user or None
    except Exception:
        return None


def response(start_response, status, body, content_type="text/html; charset=utf-8", headers=None):
    raw = body.encode("utf-8") if isinstance(body, str) else body
    hdrs = [("Content-Type", content_type), ("Content-Length", str(len(raw))), ("X-Content-Type-Options", "nosniff"), ("X-Frame-Options", "DENY"), ("Referrer-Policy", "same-origin")]
    if headers:
        hdrs.extend(headers)
    start_response(status, hdrs)
    return [raw]


def redirect(start_response, location, extra=None):
    headers = [("Location", location)]
    if extra:
        headers.extend(extra)
    start_response("302 Found", headers)
    return [b""]


def shell(title, active, username, content):
    nav = "".join(
        f'<a class="nav-item {"active" if key == active else ""}" href="/{key}"><span>{label}</span></a>'
        for key, label in NAV
    )
    return f'''<!doctype html>
<html lang="ru"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>{html.escape(title)} — Control Center</title><link rel="stylesheet" href="/static/style.css"></head>
<body><div class="app-shell"><aside class="sidebar"><div class="brand"><div class="brand-mark">C</div><div><strong>CONTROL CENTER</strong><small>Server management platform</small></div></div><nav>{nav}</nav><div class="sidebar-footer"><span>{html.escape(username)}</span><a href="/logout">Выйти</a></div></aside>
<main class="main"><header><div><span class="eyebrow">CONTROL CENTER {VERSION}</span><h1>{html.escape(title)}</h1></div><div class="status"><i></i>ONLINE</div></header><section class="content">{content}</section></main></div></body></html>'''


def login_page(error=""):
    err = f'<div class="login-error">{html.escape(error)}</div>' if error else ""
    return f'''<!doctype html><html lang="ru"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Вход — Control Center</title><link rel="stylesheet" href="/static/style.css"></head>
<body class="login-body"><main class="login-shell"><section class="login-brand"><div class="brand"><div class="brand-mark">C</div><div><strong>CONTROL CENTER</strong><small>Server management platform</small></div></div><div><span class="eyebrow">SECURE ADMINISTRATION</span><h1>Единая точка управления сервером</h1><p>Новая модульная линия Control Center 2.2.0.</p></div></section><section class="login-card"><span class="eyebrow">ADMIN CONSOLE</span><h2>Вход в систему</h2><p>Используйте локальную системную учётную запись.</p>{err}<form method="post" action="/login"><label>Пользователь<input name="username" autocomplete="username" required autofocus></label><label>Пароль<input name="password" type="password" autocomplete="current-password" required></label><button type="submit">Войти в Control Center</button></form></section></main></body></html>'''


def app(environ, start_response):
    path = environ.get("PATH_INFO", "/")
    method = environ.get("REQUEST_METHOD", "GET").upper()

    if path == "/api/v1/health":
        payload = json.dumps({"status": "ok", "product": "Control Center", "version": VERSION, "line": "2.2"})
        return response(start_response, "200 OK", payload, "application/json; charset=utf-8")

    if path == "/static/style.css":
        try:
            with open("/opt/control-center/app/static/style.css", "rb") as fh:
                return response(start_response, "200 OK", fh.read(), "text/css; charset=utf-8", [("Cache-Control", "no-cache")])
        except OSError:
            return response(start_response, "404 Not Found", "not found", "text/plain; charset=utf-8")

    if path == "/login" and method == "POST":
        try:
            length = min(int(environ.get("CONTENT_LENGTH") or 0), 16384)
        except ValueError:
            length = 0
        form = parse_qs(environ["wsgi.input"].read(length).decode("utf-8", "replace"))
        username = form.get("username", [""])[0].strip()
        password = form.get("password", [""])[0]
        ok = bool(username and password and pam.pam().authenticate(username, password, service="login"))
        password = ""
        if ok:
            token = make_session(username)
            cookie = f"cc_session={token}; Path=/; HttpOnly; SameSite=Lax; Max-Age={SESSION_TTL}"
            return redirect(start_response, "/overview", [("Set-Cookie", cookie), ("Cache-Control", "no-store")])
        return response(start_response, "401 Unauthorized", login_page("Неверное имя пользователя или пароль."), headers=[("Cache-Control", "no-store")])

    if path == "/logout":
        return redirect(start_response, "/login", [("Set-Cookie", "cc_session=; Path=/; HttpOnly; SameSite=Lax; Max-Age=0")])

    user = read_session(environ)
    if not user:
        if path == "/login":
            return response(start_response, "200 OK", login_page(), headers=[("Cache-Control", "no-store")])
        return redirect(start_response, "/login")

    if path == "/":
        return redirect(start_response, "/overview")

    pages = {
        "/overview": ("Обзор", "overview", '<div class="hero-card"><span class="eyebrow">PLATFORM STATUS</span><h2>Control Center готов к работе</h2><p>Базовый web-shell новой линии установлен. Функциональные модули будут подключаться по этапам.</p></div><div class="grid"><article><small>WEB</small><strong>ONLINE</strong><p>Интерфейс и health contract активны.</p></article><article><small>MARKET</small><strong>READY</strong><p>Каркас каталога модулей подготовлен.</p></article><article><small>RBAC</small><strong>BASE</strong><p>Аутентификация через системный PAM.</p></article><article><small>SYSTEM</small><strong>READY</strong><p>Раздел подготовлен для системных функций.</p></article></div>'),
        "/market": ("Маркет", "market", '<div class="empty"><span class="eyebrow">MODULE CATALOG</span><h2>Маркет</h2><p>Каталог установки и управления компонентами будет добавлен следующим этапом.</p></div>'),
        "/rbac": ("RBAC", "rbac", '<div class="empty"><span class="eyebrow">ACCESS CONTROL</span><h2>RBAC</h2><p>Каркас управления ролями, субъектами и разрешениями готов к расширению.</p></div>'),
        "/system": ("Система", "system", '<div class="empty"><span class="eyebrow">SYSTEM MANAGEMENT</span><h2>Система</h2><p>Системные параметры, обновления, диагностика, журналы и backup будут подключаться здесь.</p></div>'),
    }
    page = pages.get(path)
    if not page:
        return response(start_response, "404 Not Found", shell("404", "", user, '<div class="empty"><h2>Страница не найдена</h2></div>'))
    title, active, content = page
    return response(start_response, "200 OK", shell(title, active, user, content), headers=[("Cache-Control", "no-store")])


application = app
