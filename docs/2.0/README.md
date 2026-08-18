# Control Center 2.x — документация major-линии

Эта папка содержит **version-specific** документацию линии Control Center 2.x. Общая текущая инструкция находится в `../PRODUCT-MANUAL-RU.md`, а production target всегда определяется `../../deployment.json`.

## Production baseline

Опубликованный baseline линии — **Control Center 2.0.0**. Каталог `../../releases/2.0.0` является frozen и не изменяется ради исправления документации или будущих patch/minor releases.

## Состав

- `RELEASE-2.0.0.md` — фактический scope, ограничения и особенности 2.0.0;
- `ADMIN-GUIDE.md` — ежедневное администрирование интерфейса/модулей 2.0;
- `UPGRADE-1.x-TO-2.0.md` — переход с production-линии 1.x;
- `VALIDATION.md` — CI, acceptance и real-server validation для линии 2.0.

Общие документы находятся уровнем выше:

- `../PRODUCT-MANUAL-RU.md` — каноническое руководство;
- `../INSTALL.md` — установка;
- `../SYSTEM-ADMIN.md` — identity/RBAC/privileged operations;
- `../AUTO-UPDATES.md` — updater;
- `../RELEASE-HISTORY.md` — история версий;
- `../ROADMAP.md` — будущий scope.

## Подсистемы baseline 2.0.0

В документации 2.0 учитываются только возможности, подтверждённые опубликованным release metadata/frozen payload: новый интерфейс, transactional updater, backup management, Samba/domain/shares, DHCP/PXE carry-forward, AdGuard VPN, diagnostics и Minecraft Bedrock health-first recovery.

Если будущая 2.1+ функция уже существует в draft PR или `ROADMAP.md`, она не должна описываться здесь как доступная в 2.0.0.

## Исторические документы 1.x

Материалы 1.x сохраняются для release history, миграции и расследования прошлых инцидентов. После перехода production на 2.0.0 они не являются основной эксплуатационной инструкцией.

## Правило обновления

Каждый новый релиз 2.x должен одновременно обновлять release history, каноническое руководство и затронутые version-specific документы. Изменение интерфейса, API, updater, backup/restore, authentication/RBAC или managed services считается документально незавершённым, пока соответствующая инструкция не приведена в соответствие с фактическим frozen release.
