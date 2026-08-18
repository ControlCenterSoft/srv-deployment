# Control Center

`filosoff31/srv-deployment` — production-репозиторий Control Center: web-системы централизованного управления серверной инфраструктурой с единым Core, транзакционными product-релизами и централизованным администрированием.

## Текущее production-состояние

Источник истины для опубликованного production target — **`deployment.json`**, а не номер версии, упомянутый в документации. На момент этой редакции `main/deployment.json` публикует **Control Center 1.3.8** из `releases/1.3.8`.

Фактически установленная версия конкретного сервера может отличаться после failed preflight/apply/acceptance и rollback. Для неё следует использовать актуальный `server-state`/`release.json`. Исторические причины patch-релизов и real-server инциденты фиксируются в `docs/RELEASE-HISTORY.md`.

Каждый опубликованный каталог `releases/<version>` считается **frozen**. Исправления уже опубликованного релиза выполняются новой patch-версией, а не изменением старого payload.

## Что представляет собой Control Center

Текущая production-линия включает:

- FastAPI/PostgreSQL web-панель и dashboard/health;
- Linux/PAM аутентификацию и доменную Samba/winbind интеграцию через PAM/NSS;
- Kerberos/SPNEGO SSO в корректно настроенной доменной среде;
- RBAC по пользователям/группам и Read/Write полномочиям;
- системное администрирование через ограниченные privileged helpers/systemd agents;
- GitHub product updater и отдельный механизм обслуживания пакетов ОС;
- backup/restore;
- Samba Active Directory и Samba shares;
- AdGuard VPN;
- Minecraft Bedrock administration;
- network overview/diagnostics и другие управляемые сервисные функции текущей release line.

Web-приложение не должно выполнять произвольные root-команды. Привилегированные операции проходят backend/RBAC, CSRF/session checks и специализированные root-owned action paths.

## Release и update model

`main` — единственный production update channel. `server-state` используется для публикации фактического состояния сервера. Ветки `release/*` предназначены для подготовки и validation будущих product-релизов.

Типовая deployment-транзакция:

```text
preflight → safety backup → apply → acceptance → healthcheck
                                      ↘ failure → rollback
```

Updater использует release metadata и product fingerprint. Documentation-only commit не должен повторно применять неизменившийся product release.

## Установка

```bash
curl -fL -o install.sh \
  https://raw.githubusercontent.com/filosoff31/srv-deployment/main/install.sh
chmod +x install.sh
sudo ./install.sh
```

Installer читает текущий `deployment.json` и разворачивает активный self-contained release. Перед production-установкой ознакомьтесь с `docs/INSTALL.md`, каноническим руководством и историей текущей release line.

## Аутентификация и первый вход

Современная production-линия **не использует отдельный bootstrap web-пароль Control Center**. Интерактивный вход выполняется существующей локальной Linux/PAM либо доменной Samba/winbind учётной записью; после authentication применяется RBAC Control Center. Для доменной среды поддерживается Kerberos/SPNEGO SSO при корректной настройке клиента, DNS, времени и браузера.

Устаревшие инструкции ранних 0.x про `admin-bootstrap.txt` являются историческими и не должны использоваться для текущей production-линии.

## Документация

Начальная точка для пользователя и администратора:

- **`docs/PRODUCT-MANUAL-RU.md`** — каноническое русскоязычное руководство;
- **`docs/README.md`** — индекс документации и правила определения актуальности документов.

Основные источники:

- `docs/ROADMAP.md` — согласованный будущий product roadmap;
- `docs/RELEASE-HISTORY.md` — история опубликованных версий и известных real-server результатов;
- `docs/INSTALL.md` — чистая установка;
- `docs/SYSTEM-ADMIN.md` — PAM/NSS/RBAC и privileged system administration;
- `docs/AUTO-UPDATES.md` — GitHub updater;
- `docs/DEPLOYMENT-RELIABILITY.md` — транзакционная модель deployment/rollback;
- `docs/PRODUCT-EDITIONS.md` — редакции, licensing architecture и lifecycle.

Release-specific scope, incident и diagnostic документы сохраняются как исторические источники соответствующего периода. Если исторический документ противоречит `deployment.json`, frozen-файлам активного release или каноническому руководству, он **не является текущей эксплуатационной инструкцией**.

## Развитие

Roadmap является источником будущего scope. Новая функция считается текущей только после реализации, validation и публикации через production release metadata. Пользовательская документация должна обновляться вместе с каждым новым релизом без переписывания frozen release payloads.
