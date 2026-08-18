# Control Center

`filosoff31/srv-deployment` — production-репозиторий Control Center: web-системы централизованного управления серверной инфраструктурой с единым Core, транзакционными product-релизами и централизованным администрированием.

## Текущее production-состояние

Источник истины для опубликованного production target — **`deployment.json`**. Сейчас `main/deployment.json` публикует **Control Center 2.0.0** из frozen-каталога `releases/2.0.0`.

Фактически установленная версия конкретного сервера может отличаться после failed preflight/apply/acceptance или rollback. Для неё используется актуальный `server-state`/`release.json`. Исторические причины patch-релизов и real-server инциденты фиксируются в `docs/RELEASE-HISTORY.md`.

Каждый опубликованный `releases/<version>` считается **frozen**. Исправления опубликованного релиза выполняются новой версией, а не изменением старого payload.

## Что входит в Control Center 2.0.0

Активный production release включает:

- полностью обновлённый интерфейс и навигацию Control Center;
- FastAPI/PostgreSQL web-панель, dashboard и health;
- Linux/PAM authentication и Samba/winbind через PAM/NSS;
- Kerberos/SPNEGO SSO при корректной доменной настройке;
- RBAC по пользователям/группам и Read/Write полномочиям;
- privileged administration через ограниченные root-owned helpers/systemd agents;
- переработанный GitHub product updater с release fingerprint, разделением check/apply, устойчивым timer recovery и отдельными timestamps проверки/успешного update;
- OS maintenance как отдельный от product update механизм;
- backup/restore, включая массовое удаление backup и независимую политику `backup_before_update`;
- Samba Active Directory и SMB shares;
- DHCP/PXE management, перенесённый в 2.0.0 из ранее подготовленного функционального scope;
- Minecraft Bedrock administration и health-first recovery;
- AdGuard VPN;
- network overview/diagnostics и другие управляемые сервисные функции.

Точный реализованный контракт всегда определяется `releases/2.0.0/manifest.json` и frozen payload активного release.

## Release и update model

`main` — production update channel. `server-state` публикует фактическое состояние сервера. Ветки `release/*` и feature/docs branches не являются production target сами по себе.

Типовая deployment-транзакция:

```text
preflight → policy-controlled safety backup → apply → acceptance → healthcheck
                                                   ↘ failure → rollback
```

Updater использует product/release fingerprint, поэтому documentation-only commit не должен повторно применять неизменившийся product release.

## Установка

```bash
curl -fL -o install.sh \
  https://raw.githubusercontent.com/filosoff31/srv-deployment/main/install.sh
chmod +x install.sh
sudo ./install.sh
```

Installer читает текущий `deployment.json` и разворачивает активный self-contained release. Перед production-установкой ознакомьтесь с `docs/INSTALL.md` и каноническим руководством.

## Аутентификация и первый вход

Control Center 2.0.0 **не использует отдельный bootstrap web-пароль**. Интерактивный вход выполняется существующей локальной Linux/PAM либо доменной Samba/winbind учётной записью; затем применяется RBAC Control Center. В доменной среде поддерживается Kerberos/SPNEGO SSO при корректных DNS, времени, Kerberos и настройках клиента/браузера.

Инструкции ранних 0.x про `admin-bootstrap.txt` являются историческими и не применяются к текущей production-линии.

## Документация

Начальная точка:

- **`docs/PRODUCT-MANUAL-RU.md`** — каноническое русскоязычное руководство пользователя и администратора;
- **`docs/README.md`** — индекс документации и правила определения актуальности.

Основные документы:

- `docs/RELEASE-HISTORY.md` — история опубликованных версий;
- `docs/ROADMAP.md` — будущий scope после текущего production release;
- `docs/INSTALL.md` — чистая установка;
- `docs/SYSTEM-ADMIN.md` — PAM/NSS/RBAC и privileged administration;
- `docs/AUTO-UPDATES.md` — product updater;
- `docs/DEPLOYMENT-RELIABILITY.md` — deployment/rollback;
- `docs/PRODUCT-EDITIONS.md` — product editions и licensing roadmap.

Release-specific scope, incident и diagnostic документы сохраняются как исторические материалы. Если исторический документ противоречит `deployment.json`, active frozen release или каноническому руководству, он **не является текущей эксплуатационной инструкцией**.

## Развитие

Новая функция считается production-функцией только после реализации, validation и публикации через `deployment.json`. Документация обновляется вместе с каждым новым релизом и не используется как повод менять frozen payload опубликованных версий.
