# SRV Control Center — Release History

> **Статус документа:** история опубликованных product-релизов, присутствующих в `main`.
>
> Формальные self-contained product releases начинаются с 1.0.0. Предыдущая линия 0.x была консолидирована в baseline 1.0.0 и отдельно больше не является поддерживаемой release chain.

## Release policy

- Каталог опубликованного релиза считается frozen.
- Исправления выпускаются только новой patch-версией.
- `deployment.json` определяет активный production release.
- `main` — production channel; `server-state` — фактическое состояние сервера.
- Типовой deployment pipeline: `preflight → backup → apply → acceptance → healthcheck`, при ошибке — rollback.

---

# Historical 0.x line

До 1.0.0 проект развивался через инкрементальные версии 0.x, включая функциональность до 0.10.0. Начиная с 1.0.0 эта линия была собрана в единый самодостаточный baseline. Для дальнейшей разработки точкой отсчёта считается 1.0.0, а не отдельные 0.x builds.

---

# 1.0.0 — Consolidated Production Baseline

**Статус:** опубликован.

1.0.0 объединил накопленную функциональность до 0.10.0 в self-contained release и сформировал современную release/deployment модель проекта.

Основные возможности:

- FastAPI + PostgreSQL SRV Control Center;
- dashboard и health endpoints;
- системный обзор сервера;
- network overview/diagnostics;
- dry-run WAN/LAN planner;
- GitHub deployment metadata;
- защищённые системные действия;
- управление обновлениями ОС;
- AdGuard VPN CLI integration;
- graceful rotation Uvicorn workers;
- clean installer;
- GitHub automatic updater;
- repaired release-fingerprint logic для предотвращения ошибочного повторного применения неизменившегося product release.

**Upgrade range:** `>=0.8.0`.

Роль релиза: стабильный baseline, заменивший прежнюю цепочку 0.x.

---

# 1.1.0 — Authentication, RBAC, Backups and Administration

**Статус:** опубликован.

Главное изменение 1.1.0 — переход Control Center от базовой панели к централизованной административной системе.

Основные возможности:

- обязательная авторизация через Linux/PAM или доменные учётные записи;
- Kerberos/SPNEGO SSO для доменной среды;
- root/server administrators full access;
- user/group RBAC Read/Write;
- отдельный раздел управления правами пользователей;
- GitHub source/mode/period settings;
- раздельные операции проверки и применения product updates;
- manual/automatic OS update mode;
- резервные копии DB/state/config/managed system parameters;
- backup schedule;
- backup-before-update;
- download/delete/restore backups;
- раздел «Торренты»;
- отдельный раздел AdGuard VPN;
- каталог «Сервисы»;
- install/remove service actions согласно RBAC;
- удаление временных UI-заглушек неготовой функциональности.

**Upgrade range:** `>=1.0.0,<1.1.0`.

---

# 1.2.0 — Dashboard, Full Admin, AdGuard VPN and Minecraft Bedrock

**Статус:** опубликован.

1.2.0 развил UI и сервисное администрирование.

Основные направления:

- переработанный four-column dashboard;
- отображение top processes;
- расширенная full-administrator RBAC model;
- настройка AdGuard VPN через Control Center;
- Minecraft Bedrock Control;
- сохранение release transaction model с preflight/apply/acceptance/rollback.

**Upgrade range:** `>=1.1.0,<1.2.0`.

---

# 1.3.0 — Samba AD + Shares + Minecraft Administration

**Статус:** опубликован.

1.3.0 стал большим функциональным расширением доменной, файловой и Minecraft-инфраструктуры.

Основные возможности:

- администрирование Samba Active Directory domain;
- управление Samba shares;
- portable Samba domain backup/restore;
- управление Samba service state;
- RBAC для доменных и файловых операций;
- Minecraft multi-server administration;
- Minecraft update control;
- player management;
- real-server acceptance path для критичных Samba/AD операций;
- дополнительные regression-проверки для Samba и Minecraft.

**Upgrade range:** `>=1.2.0,<1.3.0`.

---

# 1.3.1 — GitHub Update Visibility Maintenance

**Статус:** опубликован и подтверждён как установленный production baseline на сервере в ходе последующей диагностики 1.3.x.

Cumulative maintenance release линии 1.3.x.

Основное изменение:

- добавлены отдельные timestamps последней попытки GitHub update и последнего успешно применённого update;
- улучшена диагностируемость automatic updater;
- сохранён cumulative 1.3.x функциональный baseline.

**Upgrade range:** `>=1.2.0,<1.3.1`.

---

# 1.3.2 — Minecraft Backend Compatibility Maintenance

**Статус:** опубликован, но real-server deployment не был принят как стабильный production baseline; сервер откатился/остался на ранее рабочей версии после failed acceptance.

Основная задача 1.3.2:

- восстановить proven single-server Minecraft Bedrock management backend;
- сохранить новый 1.3.x UI;
- сохранить RBAC;
- сохранить CSRF security model.

Во время реального развёртывания выявились acceptance-проблемы, поэтому последующие исправления были вынесены в новые patch-релизы, без изменения frozen 1.3.2.

**Upgrade range:** `>=1.2.0,<1.3.2`.

---

# 1.3.3 — Auto-Update Hardening, Session Continuity and Minecraft Update Path

**Статус:** опубликован в `main`.

Основные исправления:

- hardening automatic GitHub updates;
- защита от бесконечного повторения одного и того же failed release fingerprint;
- сохранение `session.key` и authentication continuity при rollback;
- исправление acceptance logic вокруг Minecraft timers;
- возврат Minecraft Bedrock к proven update path;
- сохранение cumulative 1.3.x Samba/Minecraft/RBAC функциональности.

После публикации real-server diagnostics показали, что updater видит новый production release, но deployment 1.3.3 завершается на стадии `preflight`; фактически установленной версией оставалась 1.3.1. Поэтому исправление не вносилось в frozen 1.3.3 и было вынесено в отдельный 1.3.4 patch release.

**Upgrade range:** `>=1.2.0,<1.3.3`.

---

# 1.3.4 — Production Preflight Repair

**Статус документа:** подготовленный patch release; считать опубликованным только после merge соответствующего release PR в `main`.

Цель:

- устранить real-server failure на стадии `preflight` линии 1.3.3;
- сделать adaptation/version-range preflight менее хрупким к форматированию;
- не блокировать repair release состоянием pre-update Minecraft runtime, который сам релиз должен восстановить;
- сохранить обязательный строгий post-apply acceptance;
- переиспользовать proven 1.3.3 payload/system objects;
- не изменять frozen 1.3.3.

После merge и подтверждения server-state этот раздел должен быть обновлён со статуса «подготовленный» на «опубликован и подтверждён».

---

# Release lineage summary

| Version | Назначение | Состояние истории |
|---|---|---|
| 0.x | Инкрементальная pre-baseline разработка | Консолидирована в 1.0.0 |
| 1.0.0 | Self-contained production baseline | Released |
| 1.1.0 | Authentication/RBAC/Backups/Admin | Released |
| 1.2.0 | Dashboard/AdGuard/Minecraft | Released |
| 1.3.0 | Samba AD/Shares/Minecraft administration | Released |
| 1.3.1 | GitHub updater timestamps/maintenance | Released, real-server working baseline |
| 1.3.2 | Minecraft backend compatibility patch | Released; real-server acceptance unsuccessful |
| 1.3.3 | Auto-update/session/Minecraft update hardening | Released to main; real-server preflight failure observed |
| 1.3.4 | Repair of 1.3.3 production preflight path | Preparing / pending merge confirmation |

## Связанные документы

- `docs/ROADMAP.md` — согласованный roadmap будущих версий;
- `docs/RELEASE-1.1.0-SCOPE.md` — детальный scope 1.1.0;
- `docs/RELEASE-1.2.0-SCOPE.md` — детальный scope 1.2.0;
- `docs/RELEASE-1.3.0-SCOPE.md` — детальный scope 1.3.0;
- `docs/DEPLOYMENT-RELIABILITY.md` — deployment model;
- `docs/AUTO-UPDATES.md` — automatic GitHub updates.

При публикации каждого следующего product release история должна обновляться отдельным documentation commit или как часть release PR.