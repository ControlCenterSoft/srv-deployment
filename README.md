# Control Center

`filosoff31/srv-deployment` — production-репозиторий Control Center: web-системы централизованного управления серверной инфраструктурой с транзакционными product-релизами, централизованной авторизацией и управляемыми privileged operations.

## Текущее состояние

**Production target определяется только `deployment.json`.** На момент этой редакции `main/deployment.json` публикует **Control Center 2.0.0** из frozen-каталога `releases/2.0.0`.

Фактически установленная версия конкретного сервера может отличаться от production target после failed preflight/apply/acceptance, rollback или задержки обновления. Для runtime-состояния используйте актуальный `server-state`/`release.json`.

Каталоги `releases/<version>` после публикации считаются **frozen**. Исправления выпускаются новой версией и не вносятся задним числом в опубликованный payload.

## Что входит в Control Center 2.0

Production 2.0.0 объединяет:

- FastAPI/PostgreSQL web-панель и системный dashboard;
- Linux/PAM и Samba/winbind identities через NSS/PAM;
- Kerberos/SPNEGO SSO в корректно настроенной доменной среде;
- RBAC по пользователям и группам;
- privileged operations через ограниченные root-owned helpers/systemd agents;
- транзакционный product updater с fingerprint/failed-release protection;
- отдельное обслуживание пакетов ОС;
- backup/restore и bulk backup management;
- Samba Active Directory и SMB shares;
- DHCP/PXE management, перенесённый в 2.0;
- AdGuard VPN integration;
- Minecraft Bedrock management с health-first recovery;
- network overview и diagnostics.

Web-приложение не должно выполнять произвольные root-команды. Критические операции проходят backend validation, session/CSRF checks, RBAC и специализированные privileged paths.

## Установка

```bash
curl -fL -o install.sh \
  https://raw.githubusercontent.com/filosoff31/srv-deployment/main/install.sh
chmod +x install.sh
sudo ./install.sh
```

Installer читает активный `deployment.json` и разворачивает опубликованный self-contained release. Перед production-установкой прочитайте `docs/INSTALL.md` и `docs/PRODUCT-MANUAL-RU.md`.

## Первый вход и права

Control Center 2.0 **не использует отдельный bootstrap web-пароль**. Вход выполняется существующей локальной Linux/PAM либо доменной Samba/winbind учётной записью. После authentication применяется RBAC Control Center. Kerberos/SPNEGO SSO доступен при корректной настройке доменной среды.

Инструкции ранних 0.x про `admin-bootstrap.txt` являются историческими и не применяются к текущей production-архитектуре.

## Обновление продукта

`main` — production update channel. Ветки `release/*` и draft PR используются для подготовки будущих релизов и сами по себе не означают production-доступность функций.

Типовая транзакция:

```text
preflight → policy-controlled safety backup → apply → acceptance → healthcheck
                                                   ↘ failure → rollback
```

Updater ориентируется на release metadata/product fingerprint, поэтому documentation-only commit не должен повторно применять неизменившийся product release.

## Документация

Главная точка входа — **`docs/README.md`**.

- `docs/PRODUCT-MANUAL-RU.md` — каноническое русскоязычное руководство пользователя и администратора;
- `docs/2.0/` — release-specific документация текущей major-линии;
- `docs/INSTALL.md` — установка;
- `docs/SYSTEM-ADMIN.md` — PAM/NSS/winbind, RBAC и privileged administration;
- `docs/AUTO-UPDATES.md` — product updater;
- `docs/DEPLOYMENT-RELIABILITY.md` — deployment/rollback model;
- `docs/RELEASE-HISTORY.md` — опубликованная release lineage;
- `docs/ROADMAP.md` — будущий scope, а не описание production;
- `docs/PRODUCT-EDITIONS.md` — редакции/licensing lifecycle.

Release-specific scope, incident и validation документы сохраняются как исторические или версионные источники. Они не должны трактоваться как текущая эксплуатационная инструкция, если противоречат active `deployment.json`, frozen manifest или каноническому руководству.

## Правило актуальности

При расхождении источников используйте порядок:

1. `deployment.json`;
2. frozen payload/manifest активного release;
3. runtime `server-state` конкретного сервера;
4. `docs/RELEASE-HISTORY.md`;
5. `docs/PRODUCT-MANUAL-RU.md` и профильные current docs;
6. `docs/ROADMAP.md`;
7. исторические release/incident документы.

Документация обновляется вместе с каждым новым релизом. Frozen release payloads ради документации не изменяются, секреты в документацию и diagnostics не добавляются.
