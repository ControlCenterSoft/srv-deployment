"""Server-rendered Web UI Control Center в безопасном режиме только для чтения."""

from __future__ import annotations

from html import escape
from typing import Any

UI_PATHS = frozenset({"/", "/overview", "/market", "/rbac", "/system"})


def _safe(value: Any) -> str:
    return escape(str(value), quote=True)


def _status(value: Any) -> str:
    labels = {
        "planned": "Запланировано",
        "bootstrap": "Начальная сборка",
        "development": "В разработке",
        "ready": "Готово",
        "rc": "Кандидат в релиз",
        "released": "Выпущено",
        "not_run": "Не запускался",
        "pending": "В процессе",
        "passed": "Пройден",
        "failed": "Не пройден",
    }
    return labels.get(str(value), "Неизвестно")


def _feature(manifest: dict[str, Any], feature_id: str) -> dict[str, Any] | None:
    for item in manifest.get("features", []):
        if isinstance(item, dict) and item.get("id") == feature_id:
            return item
    return None


def _card(title: str, value: str, note: str) -> str:
    return (
        '<article class="card">'
        f'<span class="label">{_safe(title)}</span>'
        f'<strong>{_safe(value)}</strong>'
        f'<p>{_safe(note)}</p>'
        "</article>"
    )


def _overview(manifest: dict[str, Any]) -> str:
    release = manifest["release"]
    installer = _feature(manifest, "installer-foundation") or {"status": "planned"}
    api_contracts = _feature(manifest, "api-contracts") or {"status": "planned"}
    clients = manifest.get("clients", {})
    return f"""
<section class="hero">
  <div>
    <span class="eyebrow">Control Center · серверная консоль</span>
    <h1>Обзор</h1>
    <p class="lead">Единая точка управления сервером. На текущем этапе интерфейс работает только в безопасном режиме чтения.</p>
  </div>
  <div class="release-chip">Релиз {_safe(release['version'])} · {_safe(_status(release['status']))}</div>
</section>
<section class="grid">
  {_card('API платформы', 'v1', f"{_status(api_contracts.get('status'))}; health/readiness/version/release")}
  {_card('Установщик', _status(installer.get('status')), 'Предварительная проверка, атомарная установка/восстановление и откат')}
  {_card('Приёмка', _status(release.get('acceptance')), 'Production-релиз не объявляется до статуса «Пройден»')}
  {_card('Android Client', _status(clients.get('android_client', {}).get('status')), clients.get('android_client', {}).get('version', '—'))}
  {_card('Android Admin', _status(clients.get('android_admin', {}).get('status')), clients.get('android_admin', {}).get('version', '—'))}
  {_card('Web-портал', _status(clients.get('website', {}).get('status')), clients.get('website', {}).get('version', '—'))}
</section>
<section class="panel">
  <h2>Текущий безопасный контур</h2>
  <div class="rows">
    <div><span>Состояние API</span><code>/api/v1/health</code></div>
    <div><span>Готовность</span><code>/api/v1/readiness</code></div>
    <div><span>Версия</span><code>/api/v1/version</code></div>
    <div><span>Метаданные релиза</span><code>/api/v1/release</code></div>
  </div>
</section>
"""


def _market(manifest: dict[str, Any]) -> str:
    return """
<section class="hero compact"><div><span class="eyebrow">Модули Control Center</span><h1>Маркет</h1>
<p class="lead">Каталог устанавливаемых сервисов будет подключён после появления подписанных метаданных пакетов, проверок зависимостей и безопасного привилегированного worker.</p></div></section>
<section class="panel"><h2>Сейчас</h2><p>Установка и удаление модулей из Web-процесса намеренно недоступны. Это предотвращает появление произвольного root execution до утверждения security-контракта.</p></section>
"""


def _rbac(manifest: dict[str, Any]) -> str:
    rbac = _feature(manifest, "rbac-foundation") or {"status": "planned"}
    return f"""
<section class="hero compact"><div><span class="eyebrow">Доступ и полномочия</span><h1>RBAC</h1>
<p class="lead">Серверные роли и разрешения. Клиентская видимость элементов никогда не считается авторизацией.</p></div><div class="release-chip">{_safe(_status(rbac.get('status')))}</div></section>
<section class="grid two">
  {_card('Viewer', 'только чтение', 'Просмотр разрешённых данных без привилегированных операций')}
  {_card('Admin', 'проверка на сервере', 'Административные действия будут разрешаться только после проверки сессии, разрешения и политики аудита')}
</section>
"""


def _system(manifest: dict[str, Any]) -> str:
    release = manifest["release"]
    update = _feature(manifest, "update-foundation") or {"status": "planned"}
    diagnostics = _feature(manifest, "diagnostics-foundation") or {"status": "planned"}
    return f"""
<section class="hero compact"><div><span class="eyebrow">Состояние платформы</span><h1>Система</h1>
<p class="lead">Версия, готовность, диагностика и фундамент обновлений — без прямой передачи root-команд из браузера.</p></div></section>
<section class="grid">
  {_card('Релиз', release['version'], f"{_status(release['status'])}; приёмка: {_status(release['acceptance'])}")}
  {_card('Диагностика', _status(diagnostics.get('status')), 'Ограниченный диагностический контур без секретов')}
  {_card('Обновления', _status(update.get('status')), 'Подготовка, атомарное переключение и проверка после обновления')}
</section>
"""


def render_ui(path: str, manifest: dict[str, Any]) -> str:
    active = "/overview" if path == "/" else path
    pages = {
        "/": _overview,
        "/overview": _overview,
        "/market": _market,
        "/rbac": _rbac,
        "/system": _system,
    }
    body = pages[path](manifest)
    nav_parts: list[str] = []
    for href, label in (
        ("/overview", "Обзор"),
        ("/market", "Маркет"),
        ("/rbac", "RBAC"),
        ("/system", "Система"),
    ):
        current = ' aria-current="page"' if active == href else ""
        nav_parts.append(f'<a href="{href}"{current}>{label}</a>')
    nav = "".join(nav_parts)

    return f"""<!doctype html>
<html lang="ru">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>Control Center · {_safe(active.strip('/') or 'overview')}</title>
<style>
:root{{color-scheme:dark;font-family:Inter,ui-sans-serif,system-ui,-apple-system,BlinkMacSystemFont,"Segoe UI",sans-serif;--bg:#090b0f;--panel:#11151b;--panel2:#151a22;--line:#252c37;--text:#f5f7fa;--muted:#9da8b7;--accent:#d7e5ff}}
*{{box-sizing:border-box}}body{{margin:0;background:radial-gradient(circle at 82% -10%,#1b2430 0,transparent 34%),var(--bg);color:var(--text);min-height:100vh}}a{{color:inherit;text-decoration:none}}header{{border-bottom:1px solid var(--line);background:rgba(9,11,15,.94)}}.top,main{{width:min(1180px,calc(100% - 32px));margin:0 auto}}.top{{min-height:72px;display:flex;align-items:center;justify-content:space-between;gap:28px}}.brand{{font-weight:800;letter-spacing:-.02em}}nav{{display:flex;gap:6px;flex-wrap:wrap}}nav a{{padding:10px 13px;border-radius:10px;color:var(--muted);font-size:14px}}nav a[aria-current="page"]{{background:#171c24;color:var(--text)}}main{{padding:64px 0 88px}}.hero{{display:flex;align-items:end;justify-content:space-between;gap:32px;margin-bottom:32px}}.hero.compact{{align-items:center}}.eyebrow,.label{{display:block;color:var(--muted);font-size:12px;text-transform:uppercase;letter-spacing:.12em;font-weight:700}}h1{{font-size:clamp(48px,7vw,78px);line-height:.95;letter-spacing:-.055em;margin:16px 0}}h2{{font-size:26px;letter-spacing:-.03em;margin:0 0 18px}}p{{color:var(--muted);line-height:1.65}}.lead{{font-size:18px;max-width:760px;margin:0}}.release-chip{{border:1px solid var(--line);background:var(--panel);padding:11px 14px;border-radius:999px;white-space:nowrap;color:var(--accent);font-size:13px}}.grid{{display:grid;grid-template-columns:repeat(3,minmax(0,1fr));gap:14px;margin:28px 0}}.grid.two{{grid-template-columns:repeat(2,minmax(0,1fr))}}.card,.panel{{border:1px solid var(--line);background:linear-gradient(180deg,var(--panel2),var(--panel));border-radius:20px}}.card{{padding:22px}}.card strong{{display:block;font-size:22px;margin:12px 0 5px}}.card p{{font-size:14px;margin:0}}.panel{{padding:26px;margin-top:20px}}.rows>div{{display:flex;justify-content:space-between;gap:18px;padding:13px 0;border-top:1px solid var(--line)}}.rows span{{color:var(--muted)}}code{{color:#c8d6ea}}footer{{border-top:1px solid var(--line);padding:24px 0;color:var(--muted);font-size:12px}}footer div{{width:min(1180px,calc(100% - 32px));margin:0 auto}}@media(max-width:800px){{.top,.hero{{align-items:flex-start;flex-direction:column;padding:18px 0}}nav{{width:100%;overflow:auto;flex-wrap:nowrap}}main{{padding-top:42px}}.grid,.grid.two{{grid-template-columns:1fr}}.release-chip{{white-space:normal}}}}
</style>
</head>
<body>
<header><div class="top"><a class="brand" href="/overview">Control Center</a><nav>{nav}</nav></div></header>
<main>{body}</main>
<footer><div>Control Center · Релиз {_safe(manifest['release']['version'])} · интерфейс чтения</div></footer>
</body></html>"""
