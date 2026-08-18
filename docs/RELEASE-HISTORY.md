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
- **1.3.1** — updater visibility/timestamps; наблюдался как рабочий baseline.
- **1.3.2** — Minecraft backend compatibility; real-server acceptance выявил проблемы.
- **1.3.3** — auto-update/session/Minecraft hardening; выявлен preflight blocker.
- **1.3.4** — production preflight repair.
- **1.3.5** — Minecraft runtime gate/GitHub timer repair.
- **1.3.6** — updater bootstrap dependency repair.
- **1.3.7** — release-relative acceptance/rollback repair.
- **1.3.8** — release metadata ownership/permissions и privileged action watcher repair; последний 1.x production baseline перед 2.x.

Каждый repair выпускался новой frozen patch-версией; старые payload не переписывались.

## 2.0.0 — Control Center 2.x baseline

**Статус:** опубликован, frozen; исторический production target, заменён 2.1.0.

2.0.0 сформировал новый major baseline: обновлённый интерфейс/навигация и перенос проверенных contracts 1.x, включая PAM/NSS/winbind + RBAC, system administration, updater/backup, Samba AD/shares, Minecraft, AdGuard VPN, network/system и перенесённые DHCP/PXE paths. Release закрепил health-first и transactional deployment подход. Licensing Stage 1 в frozen 2.0.0 фактически не вошёл.

## 2.1.0 — Minecraft canonical runtime stabilization

**Статус:** **текущий production target** согласно `../deployment.json`.

Frozen manifest 2.1.0 определяет release как stabilization Minecraft Bedrock Server. Release:

- сохраняет существующий мир и настройки;
- нормализует live Bedrock runtime в один канонический `srv-control-minecraft-bedrock.service`;
- маршрутизирует Control Center operations через канонический service;
- отключает конфликтующий multi-instance automatic updater;
- сохраняет transactional rollback и availability fallback для ранее unmanaged runtime;
- принимает upgrade lineage `>=1.3.8,<2.1.0`.

2.1.0 **не является Licensing Stage 1**. Ранее запланированное использование номера 2.1.0 для licensing было вытеснено production stabilization и не может быть восстановлено изменением frozen release; roadmap должен учитывать фактически опубликованную lineage.

## Сводка

| Version | Назначение | Статус |
|---|---|---|
| 0.x | ранняя incremental line | Historical |
| 1.0–1.3.0 | baseline → auth/RBAC → admin/Samba/Minecraft | Released |
| 1.3.1–1.3.8 | последовательные production repairs | Released / superseded |
| 2.0.0 | новый major baseline | Released / superseded |
| 2.1.0 | canonical Minecraft runtime stabilization | **Current production** |

## Исторические документы

`RELEASE-*.md`, incident notes и implementation records действительны в контексте соответствующей версии. Для текущей эксплуатации используйте `deployment.json`, frozen active release, `PRODUCT-MANUAL-RU.md`, `SYSTEM-ADMIN.md`, `AUTO-UPDATES.md`, `DEPLOYMENT-RELIABILITY.md` и актуальный `server-state` конкретного сервера.