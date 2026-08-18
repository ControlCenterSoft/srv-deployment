# Control Center 2.2.0 — текущее состояние реализации

Дата: 2026-08-18

Ветка: `release/2.2.0`

Статус: **development / bootstrap implementation**

## Архив предыдущей линии

Предыдущая production-линия до Control Center 2.1.4 сохранена в:

`archive/pre-2.2.0-2026-08-18`

Production `main` и `deployment.json` пока продолжают относиться к предыдущей production-линии. 2.2.0 ещё не опубликован как production.

## Текущий реализованный состав

### Web shell

Реализован новый независимый web-shell Control Center без функциональной зависимости от payload старой линии.

Главное меню:

- Обзор;
- Маркет;
- RBAC;
- Система.

Маршруты:

- `/`;
- `/overview`;
- `/market`;
- `/rbac`;
- `/system`.

### Authentication

Текущий bootstrap использует PAM-аутентификацию существующих локальных Linux-учётных записей.

Отдельный bootstrap-пароль Control Center не создаётся.

Web-session подписывается секретным ключом, который создаётся непосредственно на устанавливаемом хосте и не хранится в репозитории.

### Health

Публичный endpoint:

`/api/v1/health`

Минимальный контракт:

- `status = ok`;
- `product = Control Center`;
- `version = 2.2.0`.

### Runtime

Web-приложение запускается отдельным systemd unit:

`control-center-web.service`

Frontend entrypoint предоставляется nginx reverse proxy.

Backend слушает loopback-интерфейс и не публикуется напрямую наружу.

### Installer

Текущий установщик:

`installer/install.sh`

Он выполняет:

- preflight;
- установку системных зависимостей;
- размещение application payload;
- генерацию session key;
- настройку systemd;
- настройку nginx;
- запуск сервисов;
- backend health check;
- nginx health check.

### Acceptance

Отдельный сценарий:

`installer/acceptance.sh`

Предназначен для повторной проверки уже установленного экземпляра.

### CI

В ветке заложен GitHub Actions validation gate для проверки bootstrap-контракта до дальнейшей стабилизации.

## Что пока не считается завершённым

- полноценная clean-host acceptance на реальном чистом сервере;
- production publication;
- переключение `main`/`deployment.json`;
- полноценная RBAC-модель;
- функциональный каталог Маркета;
- module manifest/API lifecycle contract;
- расширенные функции раздела Система;
- production migration/upgrade contract со старой линией.

## Следующая зона разработки

Следующий блок — архитектура **Маркета**.

До добавления конкретных модулей требуется закрепить единый контракт:

- manifest;
- module id;
- version;
- dependencies;
- states;
- install;
- remove;
- start;
- stop;
- configure;
- health;
- error;
- rollback;
- RBAC permissions;
- UI card metadata.

Рекомендуемые пользовательские состояния карточки:

- Не установлен;
- Установлен;
- Запущен;
- Остановлен;
- Ошибка.

## Канонические документы

- `README.md` — краткое актуальное состояние ветки и установка;
- `docs/2.2/PLAN-2.2.0.md` — канонический архитектурный план;
- `docs/2.2/STATUS-2.2.0.md` — текущий фактический статус реализации.

При расхождении будущих черновиков с этими документами приоритет имеет фактически реализованный код и затем актуализированный `PLAN-2.2.0.md`.