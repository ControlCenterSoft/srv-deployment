# Control Center 2.2.0

`release/2.2.0` — новая чистая линия разработки Control Center.

Предыдущая production-линия до 2.1.4 сохранена в архивной ветке `archive/pre-2.2.0-2026-08-18`. Production `main` и `deployment.json` пока не переключены на 2.2.0.

## Текущий статус

Этап 1 находится в состоянии **bootstrap implementation**: базовый web-интерфейс, установщик и acceptance-контракт уже заложены в ветку и готовы к дальнейшему развитию и проверкам на чистом хосте.

Текущий верхнеуровневый интерфейс содержит только четыре раздела:

- **Обзор** — `/` и `/overview`;
- **Маркет** — `/market`;
- **RBAC** — `/rbac`;
- **Система** — `/system`.

Названия прежней линии «Сервисы» и «Пользователи» в UI 2.2.0 не используются.

## Уже реализовано в этапе 1

- независимый WSGI web-shell Control Center;
- сохранённая визуальная идентичность прежнего Control Center;
- системная PAM-аутентификация локальными Linux-учётными записями;
- подписанная сервером web-сессия;
- единый shell и маршрутизация четырёх разделов;
- публичный health endpoint `/api/v1/health`;
- nginx reverse proxy;
- отдельный systemd service `control-center-web.service`;
- базовый systemd sandbox hardening;
- самостоятельный установщик `installer/install.sh`;
- повторная acceptance-проверка `installer/acceptance.sh`;
- GitHub Actions validation gate;
- генерация отдельного session key на устанавливаемом хосте без публикации секрета в Git.

## Установка текущего bootstrap-кандидата

```bash
curl -fsSL \
  https://raw.githubusercontent.com/filosoff31/srv-deployment/release/2.2.0/installer/install.sh \
  -o /tmp/control-center-2.2.0-install.sh
sudo bash /tmp/control-center-2.2.0-install.sh
```

После `INSTALL PASS` web-интерфейс доступен по адресу:

```text
http://<server-ip>/
```

Для входа на текущем bootstrap-этапе используется существующая локальная системная учётная запись Linux через PAM. Отдельный bootstrap-пароль Control Center не создаётся.

## Acceptance

Повторная проверка установленного экземпляра:

```bash
curl -fsSL \
  https://raw.githubusercontent.com/filosoff31/srv-deployment/release/2.2.0/installer/acceptance.sh \
  -o /tmp/control-center-2.2.0-acceptance.sh
sudo bash /tmp/control-center-2.2.0-acceptance.sh
```

Acceptance должен подтвердить минимум:

- работоспособность backend;
- ответ `/api/v1/health` со статусом `ok`;
- версию `2.2.0`;
- доступ к health endpoint через nginx;
- доступность базовых UI-маршрутов после аутентификации.

## Архитектурная граница этапа 1

Этап 1 формирует только платформенный web-shell и установочный фундамент. Полная бизнес-логика разделов **Маркет**, **RBAC** и **Система** не считается частью текущего bootstrap и добавляется последующими шагами 2.2.0.

Следующая архитектурная зона — **Маркет**: каталог устанавливаемых модулей и единый lifecycle-контракт для состояний и действий компонентов.

## Документация

- `docs/2.2/PLAN-2.2.0.md` — канонический план и архитектурные границы новой линии;
- `docs/2.2/STATUS-2.2.0.md` — текущее фактическое состояние реализации;
- `installer/install.sh` — bootstrap installer;
- `installer/acceptance.sh` — acceptance текущего web-shell.

> 2.2.0 пока является development-линией. До отдельного решения о публикации нельзя считать её production-релизом.