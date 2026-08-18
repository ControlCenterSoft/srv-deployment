# Control Center 2.2.0

Эта ветка — чистая линия разработки Control Center 2.2.0.

Предыдущая production-линия до 2.1.4 сохранена в `archive/pre-2.2.0-2026-08-18`.

## Текущий этап

Первый этап — самостоятельный установщик web-интерфейса с сохранением существующего дизайна Control Center и новым главным меню: **Обзор**, **Маркет**, **RBAC**, **Система**.

Уже реализовано:

- новый независимый WSGI web-shell;
- системная PAM-аутентификация;
- подписанная сервером web-сессия;
- маршруты `/overview`, `/market`, `/rbac`, `/system`;
- публичный `/api/v1/health`;
- nginx reverse proxy;
- systemd service с базовым sandbox hardening;
- идемпотентный bootstrap installer;
- отдельная acceptance-проверка;
- GitHub Actions validation gate.

## Установка текущего bootstrap-кандидата

```bash
curl -fsSL \
  https://raw.githubusercontent.com/filosoff31/srv-deployment/release/2.2.0/installer/install.sh \
  -o /tmp/control-center-2.2.0-install.sh
sudo bash /tmp/control-center-2.2.0-install.sh
```

После `INSTALL PASS` web-интерфейс доступен по адресу `http://<server-ip>/`. Для входа используется существующая локальная системная учётная запись Linux.

Повторная проверка установленного экземпляра:

```bash
curl -fsSL \
  https://raw.githubusercontent.com/filosoff31/srv-deployment/release/2.2.0/installer/acceptance.sh \
  -o /tmp/control-center-2.2.0-acceptance.sh
sudo bash /tmp/control-center-2.2.0-acceptance.sh
```

> Ветка `release/2.2.0` пока является development/bootstrap-линией и не переключает production `main`/`deployment.json`.

Подробный план: `docs/2.2/PLAN-2.2.0.md`.
