# Control Center — Release History

> **Статус документа:** история опубликованных product-релизов. Активный production target всегда определяется `deployment.json`; фактически установленная версия конкретного сервера определяется актуальным `server-state`/`release.json`.

## Release policy

- Каталог опубликованного релиза считается frozen.
- Исправления выпускаются новой версией.
- `deployment.json` определяет активный production release.
- `main` — production channel; `server-state` — фактическое состояние сервера.
- Типовой pipeline: `preflight → safety backup/policy gate → apply → acceptance → healthcheck`, при ошибке — rollback.
- Release-specific incident/scope документы сохраняются как исторические источники и не заменяют текущую эксплуатационную документацию.

---

# Historical 0.x line

До 1.0.0 проект развивался через инкрементальные 0.x версии. Начиная с 1.0.0 эта линия была консолидирована в self-contained baseline. Документы ранних 0.x могут содержать устаревшую bootstrap web-login модель и рассматриваются только как исторический контекст.

# 1.0.0 — Consolidated Production Baseline

**Статус:** опубликован.

Self-contained baseline: FastAPI/PostgreSQL Control Center, dashboard/health, system/network overview, GitHub deployment metadata, защищённые системные действия, OS maintenance, AdGuard VPN, installer и updater.

# 1.1.0 — Authentication, RBAC, Backups and Administration

**Статус:** опубликован.

Введены Linux/PAM и Samba/winbind через PAM/NSS, Kerberos/SPNEGO SSO, RBAC, system administration, product/OS updates и backup/restore без отдельной web password database.

# 1.2.0 — Dashboard, Full Admin, AdGuard VPN and Minecraft Bedrock

**Статус:** опубликован.

Расширены dashboard/full-admin model, AdGuard VPN и Minecraft Bedrock management.

# 1.3.0 — Samba AD + Shares + Minecraft Administration

**Статус:** опубликован.

Добавлены Samba AD administration, shares, portable domain backup/restore, соответствующий RBAC и расширенное Minecraft management.

# 1.3.1 — GitHub Update Visibility Maintenance

**Статус:** опубликован; использовался как рабочий real-server baseline.

Добавлены отдельные timestamps GitHub updater и улучшена его диагностируемость.

# 1.3.2 — Minecraft Backend Compatibility Maintenance

**Статус:** опубликован; real-server acceptance выявил проблемы.

Возвращён proven single-server Minecraft backend при сохранении нового UI/RBAC/CSRF.

# 1.3.3 — Auto-Update Hardening, Session Continuity and Minecraft Update Path

**Статус:** опубликован.

Hardening updater, failed-fingerprint suppression, session/auth continuity при rollback и repairs Minecraft update path. Real-server preflight defect потребовал следующего patch release.

# 1.3.4 — Production Preflight Repair

**Статус:** опубликован.

Repair preflight: нездоровый optional Minecraft updater runtime больше не должен блокировать core product apply.

# 1.3.5 — Minecraft Runtime Gate / GitHub Timer Repair

**Статус:** опубликован.

Repair broken Minecraft runtime gates и восстановление automatic GitHub timer.

# 1.3.6 — Updater Bootstrap Dependency Repair

**Статус:** опубликован.

Разорван updater bootstrap dependency cycle, automatic scheduling закреплён как post-apply contract.

# 1.3.7 — Release-Relative Acceptance/Rollback Repair

**Статус:** опубликован.

Исправлены release-relative execution проблемы acceptance/rollback.

# 1.3.8 — Release Metadata / Privileged Action Watcher Repair

**Статус:** опубликован; последний production baseline линии 1.x перед 2.0.0.

Исправлены permissions release metadata и privileged system-action watcher. 1.3.8 стал исходной production-базой для перехода на 2.0.0.

---

# 2.0.0 — New Major Production Baseline

**Статус:** **текущий production target** согласно `main/deployment.json`.

2.0.0 опубликован как новый major baseline. Frozen manifest фиксирует следующие ключевые изменения:

- полностью переработанный administration interface;
- rebuilt transactional update controller;
- явные update/check timestamps;
- bulk backup management;
- authoritative `backup_before_update` policy enforcement;
- health-first Minecraft Bedrock recovery;
- carried-forward DHCP/PXE management.

Updater 2.0.0 использует product/release fingerprint, разделяет check/apply, восстанавливает automatic scheduling и подавляет бесконечный automatic retry known-failed release fingerprint. Backup schedule и pre-update backup policy рассматриваются независимо; внутренний rollback snapshot не подменяет пользовательский backup.

Minecraft recovery в 2.0.0 ориентирован на health-first подход: исправный runtime не должен переустанавливаться, а destructive recovery допускается только после safety backup старого состояния.

DHCP/PXE функциональность, ранее существовавшая в development scope, включена в active 2.0 frozen payload и зарегистрирована в runtime вместе с native 2.0 UI/API.

Если какое-либо требование старого 2.0 roadmap не подтверждается manifest/frozen payload, оно не считается частью опубликованного 2.0.0 и переносится в будущий 2.x scope.

---

# Release lineage summary

| Version | Назначение | Исторический статус |
|---|---|---|
| 0.x | Pre-baseline incremental development | Historical; consolidated |
| 1.0.0 | Self-contained production baseline | Released |
| 1.1.0 | Authentication/RBAC/Backups/Admin | Released |
| 1.2.0 | Dashboard/AdGuard/Minecraft | Released |
| 1.3.0 | Samba AD/Shares/Minecraft administration | Released |
| 1.3.1 | Updater visibility maintenance | Released; working baseline observed |
| 1.3.2 | Minecraft compatibility patch | Released; acceptance issues observed |
| 1.3.3 | Updater/session/Minecraft hardening | Released; preflight issue observed |
| 1.3.4 | Production preflight repair | Released |
| 1.3.5 | Minecraft runtime gate/GitHub timer repair | Released |
| 1.3.6 | Updater bootstrap dependency repair | Released |
| 1.3.7 | Acceptance/rollback relative-path repair | Released |
| 1.3.8 | Release metadata + privileged action watcher repair | Released; final 1.x production baseline |
| 2.0.0 | New UI/updater/backup/Minecraft/DHCP-PXE major baseline | **Current production target** |

## Как использовать исторические документы

`RELEASE-*.md`, incident notes и release-specific implementation records сохраняются для трассируемости. Их утверждения действительны только в контексте соответствующей версии.

Для текущей эксплуатации используйте `deployment.json`, active frozen release, `PRODUCT-MANUAL-RU.md`, `SYSTEM-ADMIN.md`, `AUTO-UPDATES.md`, `DEPLOYMENT-RELIABILITY.md` и актуальный `server-state`.

При публикации следующего release этот документ обновляется документационным commit/PR без изменения frozen releases.
