# Control Center — Release History

> **Статус документа:** история опубликованных product-релизов, присутствующих в `main`. Активный production target всегда определяется `deployment.json`; фактически установленная версия конкретного сервера определяется актуальным `server-state`/`release.json`.

## Release policy

- Каталог опубликованного релиза считается frozen.
- Исправления выпускаются только новой patch-версией.
- `deployment.json` определяет активный production release.
- `main` — production channel; `server-state` — фактическое состояние сервера.
- Типовой deployment pipeline: `preflight → safety backup → apply → acceptance → healthcheck`, при ошибке — rollback.
- Release-specific incident/scope документы сохраняются как исторические источники и не заменяют текущую эксплуатационную документацию.

---

# Historical 0.x line

До 1.0.0 проект развивался через инкрементальные версии 0.x, включая функциональность до 0.10.0. Начиная с 1.0.0 эта линия была консолидирована в self-contained baseline. Отдельные 0.x документы могут содержать устаревшие инструкции, включая ранний bootstrap web-login, и должны рассматриваться только как исторический контекст.

---

# 1.0.0 — Consolidated Production Baseline

**Статус:** опубликован.

1.0.0 объединил накопленную функциональность 0.x в self-contained release и закрепил современную release/deployment модель.

Ключевые возможности: FastAPI/PostgreSQL Control Center, dashboard/health, system/network overview, dry-run WAN/LAN planner, GitHub deployment metadata, защищённые системные действия, OS maintenance, AdGuard VPN CLI, clean installer и automatic GitHub updater.

---

# 1.1.0 — Authentication, RBAC, Backups and Administration

**Статус:** опубликован.

Ключевые изменения:

- Linux/PAM и доменная authentication без отдельной web password database;
- Samba/winbind через PAM/NSS;
- Kerberos/SPNEGO SSO;
- user/group RBAC Read/Write;
- системное администрирование;
- product update check/apply;
- OS maintenance modes;
- backup schedule, backup-before-update, download/delete/restore;
- сервисные модули и RBAC-aware actions.

---

# 1.2.0 — Dashboard, Full Admin, AdGuard VPN and Minecraft Bedrock

**Статус:** опубликован.

Основные направления: переработанный dashboard, расширенная full-admin модель, AdGuard VPN management, Minecraft Bedrock Control и сохранение транзакционного release pipeline.

---

# 1.3.0 — Samba AD + Shares + Minecraft Administration

**Статус:** опубликован.

Основные возможности:

- Samba Active Directory administration;
- Samba shares;
- portable domain backup/restore;
- RBAC для доменных/файловых операций;
- Minecraft administration/update/player management;
- real-server acceptance для критичных Samba/AD операций.

---

# 1.3.1 — GitHub Update Visibility Maintenance

**Статус:** опубликован; в последующей 1.3.x диагностике фиксировался как рабочий real-server baseline.

Добавлены отдельные timestamps состояния GitHub updater и улучшена диагностируемость automatic updates.

---

# 1.3.2 — Minecraft Backend Compatibility Maintenance

**Статус:** опубликован; real-server acceptance не стал стабильным baseline.

Задача релиза — восстановить proven single-server Minecraft Bedrock backend при сохранении нового UI/RBAC/CSRF. Реальный deployment выявил acceptance-проблемы, поэтому исправления были вынесены в последующие patch-релизы без изменения frozen 1.3.2.

---

# 1.3.3 — Auto-Update Hardening, Session Continuity and Minecraft Update Path

**Статус:** опубликован.

Исправления:

- hardening automatic GitHub updates;
- failed release fingerprint retry suppression;
- сохранение session/auth continuity при rollback;
- исправления acceptance вокруг Minecraft timers;
- возврат к proven Minecraft update path.

После публикации real-server diagnostics выявили failure на `preflight`; исправление было вынесено в 1.3.4.

---

# 1.3.4 — Production Preflight Repair

**Статус:** опубликован.

Release manifest определяет 1.3.4 как repair production preflight: proven 1.3.3 payload должен применяться даже при нездоровом pre-update Minecraft updater runtime. Frozen 1.3.3 не изменялся.

---

# 1.3.5 — Minecraft Runtime Gate / GitHub Timer Repair

**Статус:** опубликован.

Repair release устраняет broken pre-update Minecraft runtime gates, восстанавливает proven legacy Minecraft updater во время apply и повторно включает GitHub updater timer, если настроен automatic mode.

---

# 1.3.6 — Updater Bootstrap Dependency Repair

**Статус:** опубликован.

1.3.6 разрывает второй updater bootstrap dependency cycle: optional Minecraft updater health больше не может прерывать core product apply, при этом automatic GitHub scheduling остаётся обязательным post-apply contract.

---

# 1.3.7 — Release-Relative Acceptance/Rollback Repair

**Статус:** опубликован.

Исправляет обнаруженные на реальном 1.3.6 сервере проблемы release-relative execution acceptance/rollback, сохраняя proven 1.3.6 payload и восстановление automatic GitHub updater.

---

# 1.3.8 — Release Metadata / Privileged Action Watcher Repair

**Статус:** опубликован и является текущим production target согласно `main/deployment.json` на момент этой редакции.

1.3.8 устраняет real-server acceptance blockers 1.3.7:

- восстанавливает ownership/permissions release metadata так, чтобы web-приложение могло безопасно читать текущую release identity;
- повторно активирует privileged system-action path/watcher;
- сохраняет proven 1.3.7 payload и rollback lineage.

`deployment.json` указывает на `releases/1.3.8` и его отдельные `preflight-1.3.8.sh`, `apply-1.3.8.sh`, `acceptance-1.3.8.sh`, `rollback-1.3.8.sh`.

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
| 1.3.8 | Release metadata + privileged action watcher repair | **Current production target** |

## Как использовать исторические документы

Документы `RELEASE-*.md`, старые incident notes и release-specific implementation records сохраняются для трассируемости. Их утверждения об интерфейсе, первом входе, update mechanics или operational status действительны только в контексте соответствующей версии.

Для текущей эксплуатации используйте:

- `deployment.json`;
- `docs/PRODUCT-MANUAL-RU.md`;
- `docs/SYSTEM-ADMIN.md`;
- `docs/AUTO-UPDATES.md`;
- `docs/DEPLOYMENT-RELIABILITY.md`;
- актуальный `server-state` для конкретного сервера.

При публикации следующего product release этот документ должен обновляться отдельным documentation commit/PR либо как документационная часть release PR, не изменяя frozen releases.
