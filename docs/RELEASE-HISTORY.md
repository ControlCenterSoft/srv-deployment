# Control Center — Release History

> История опубликованных product-релизов. Активный production target определяется `../deployment.json`, установленная версия конкретного сервера — его `server-state`/`release.json`.

## Release policy

Опубликованный `releases/<version>` frozen. Исправление выпускается новой версией. `main` — production channel. Типовая transaction: `preflight → safety backup → apply → acceptance → healthcheck`, при ошибке — rollback. Incident/scope документы сохраняются как исторические и не заменяют текущую эксплуатационную документацию.

## Historical 0.x

Инкрементальная ранняя линия, позднее консолидированная 1.0.0. Документы 0.x, включая bootstrap web-login инструкции, являются историческими.

## 1.x production lineage

- **1.0.0** — self-contained baseline: FastAPI/PostgreSQL, dashboard/health, system/network, deployment metadata, OS maintenance, AdGuard VPN, installer/updater.
- **1.1.0** — PAM/NSS и Samba/winbind authentication, Kerberos/SPNEGO SSO, RBAC, system administration, product/OS updates, backup/restore.
- **1.2.0** — dashboard/full-admin, AdGuard VPN management, Minecraft Bedrock control.
- **1.3.0** — Samba AD, shares, domain backup/restore, Minecraft administration.
- **1.3.1–1.3.8** — последовательные production repairs updater/session/Minecraft/deployment contracts; 1.3.8 — последний 1.x baseline перед 2.x.

Каждый repair выпускался новой frozen patch-версией; старые payload не переписывались.

## 2.0.0 — Control Center 2.x baseline

**Статус:** опубликован, frozen; superseded.

Новый major baseline: обновлённый интерфейс/навигация и перенос проверенных contracts 1.x, включая PAM/NSS/winbind + RBAC, system administration, updater/backup, Samba AD/shares, Minecraft, AdGuard VPN, network/system и перенесённые DHCP/PXE paths. Licensing Stage 1 в frozen 2.0.0 фактически не вошёл.

## 2.1.0 — Minecraft canonical runtime stabilization

**Статус:** опубликован, frozen; superseded.

Сохраняет существующий мир и настройки, нормализует Bedrock runtime в один канонический `srv-control-minecraft-bedrock.service`, маршрутизирует Control Center operations через него, отключает конфликтующий multi-instance updater и сохраняет transactional rollback/fallback contract.

## 2.1.1 — privileged Minecraft service-action repair

**Статус:** опубликован, frozen; superseded.

Repair-линия укрепила privilege bridge для Minecraft service actions и сохранила `NoNewPrivileges` sandbox web-процесса. Привилегированные start/stop/restart операции выполняются через ограниченный системный путь, а не через произвольные root-команды web-приложения.

## 2.1.2 — Minecraft status and confirmed-result repair

**Статус:** **текущий production target** согласно `../deployment.json`.

Frozen 2.1.2 сохраняет contracts 2.1.0/2.1.1 и дополнительно:

- использует канонический systemd `WorkingDirectory` для определения Minecraft runtime/status, включая остановленный сервер;
- возвращает явные подтверждённые ONLINE/OFFLINE результаты service actions;
- добавляет live-status в Minecraft UI с периодическим обновлением около 5 секунд;
- сохраняет `NoNewPrivileges` и privilege bridge 2.1.1;
- сохраняет frozen 2.1.0/2.1.1 без изменений.

Real-server acceptance остаётся обязательной частью эксплуатационной проверки. Если общий health успешен, но отдельная UI-страница падает, это рассматривается как отдельный application/render defect, а не как доказательство исправности модуля.

## Сводка

| Version | Назначение | Статус |
|---|---|---|
| 0.x | ранняя incremental line | Historical |
| 1.0–1.3.0 | baseline → auth/RBAC → admin/Samba/Minecraft | Released |
| 1.3.1–1.3.8 | последовательные production repairs | Released / superseded |
| 2.0.0 | новый major baseline | Released / superseded |
| 2.1.0 | canonical Minecraft runtime stabilization | Released / superseded |
| 2.1.1 | privileged Minecraft action repair | Released / superseded |
| 2.1.2 | status/confirmed-result/live-status repair | **Current production** |

## Исторические документы

`RELEASE-*.md`, incident notes и implementation records действительны в контексте соответствующей версии. Для текущей эксплуатации используйте `deployment.json`, frozen active release, `PRODUCT-MANUAL-RU.md`, `SYSTEM-ADMIN.md`, `AUTO-UPDATES.md`, `DEPLOYMENT-RELIABILITY.md` и актуальный `server-state` конкретного сервера.
