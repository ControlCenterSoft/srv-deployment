# Control Center

`filosoff31/srv-deployment` — production-репозиторий Control Center: web-системы управления домашней/серверной инфраструктурой с единым Core, транзакционными product-релизами и централизованным администрированием.

## Текущее состояние

Фактический production target всегда определяется `deployment.json`, а не текстом README. На момент этой редакции `main` публикует **1.3.4**. Этот patch-релиз опубликован как production repair после неудачной попытки обновления предыдущей линии; фактическую установленную на конкретном сервере версию следует определять по `server-state`/`release.json`, а историю инцидентов — по `docs/RELEASE-HISTORY.md`.

Каждый опубликованный `releases/<version>` считается frozen. Ошибки опубликованного релиза исправляются новой patch-версией, а не редактированием уже опубликованного payload.

## Что представляет собой Control Center

Текущая линия включает FastAPI/PostgreSQL web-панель, dashboard/health, Linux/PAM и доменную Samba/winbind аутентификацию, Kerberos/SPNEGO SSO, групповой RBAC, системное администрирование, GitHub product updater, OS maintenance, backup/restore, Samba Active Directory, Samba shares, AdGuard VPN и Minecraft Bedrock management.

Web-приложение не является root-процессом: критические системные операции проходят через специализированные privileged helpers/systemd agents и проверяются backend/RBAC.

## Release и update model

`main` — единственный production update channel. `server-state` используется для публикации фактического состояния сервера. `release/*` — ветки подготовки и validation будущих релизов.

Типовая транзакция deployment:

```text
preflight → backup → apply → acceptance → healthcheck
                                      ↘ failure → rollback
```

Updater использует product fingerprint, поэтому documentation-only commit не должен повторно применять неизменившийся product release.

## Установка

```bash
curl -fL -o install.sh \
  https://raw.githubusercontent.com/filosoff31/srv-deployment/main/install.sh
chmod +x install.sh
sudo ./install.sh
```

Installer читает текущий `deployment.json` и разворачивает активный self-contained release. Перед production установкой ознакомьтесь с `docs/INSTALL.md` и статусом текущей версии в `docs/RELEASE-HISTORY.md`.

## Аутентификация

Современная production-линия **не использует отдельный bootstrap web-пароль Control Center**. Вход выполняется существующей локальной Linux/PAM или доменной Samba/winbind учётной записью; затем применяется RBAC. Для доменной среды поддерживается Kerberos/SPNEGO SSO при корректной клиентской конфигурации.

Подробности: `docs/SYSTEM-ADMIN.md` и каноническое `docs/PRODUCT-MANUAL-RU.md`.

## Документация

Начальная точка для пользователя и администратора — **`docs/PRODUCT-MANUAL-RU.md`**, каноническое русскоязычное руководство.

Основные документы:

- `docs/PRODUCT-MANUAL-RU.md` — обзор, доступ, установка, первый вход, интерфейс, администрирование, updates, backup/restore, Samba, shares, Minecraft, диагностика, безопасность и версии;
- `docs/ROADMAP.md` — согласованный будущий product roadmap;
- `docs/RELEASE-HISTORY.md` — история опубликованных версий и известный real-server status;
- `docs/INSTALL.md` — чистая установка;
- `docs/SYSTEM-ADMIN.md` — PAM/NSS/RBAC и privileged system administration;
- `docs/AUTO-UPDATES.md` — GitHub updater;
- `docs/DEPLOYMENT-RELIABILITY.md` — транзакционная модель deployment/rollback;
- `docs/PRODUCT-EDITIONS.md` — Home/Professional, licensing architecture и release-based lifecycle.

Release-specific scope и incident/diagnostic документы являются историческими источниками для соответствующих версий и не должны трактоваться как описание текущего интерфейса, если они противоречат активной production metadata или каноническому руководству.

## Развитие

Roadmap является источником будущего scope. Изменения пользовательской архитектуры должны сопровождаться обновлением канонического руководства. Release-specific implementation не должна переписывать уже опубликованные frozen releases.
