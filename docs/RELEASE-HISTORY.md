# Control Center — Release History

> **Статус:** история опубликованных product releases. Активный production target всегда определяется `../deployment.json`; фактически установленная версия конкретного сервера — `release.json`/server-state.

## Release policy

- опубликованный `releases/<version>` считается frozen;
- исправления frozen release выпускаются новой версией;
- `deployment.json` определяет production target;
- `main` — production channel;
- draft/release branch не является production;
- incident/scope документы сохраняются как исторические источники;
- документация обновляется вместе с release acceptance.

---

## 0.x — историческая инкрементальная линия

До 1.0.0 проект развивался последовательными 0.x релизами. В документах этого периода встречаются устаревшие механики, включая отдельный bootstrap web-login и ранние deployment markers. После 1.0.0 они имеют только историческое значение.

## 1.0.0 — consolidated baseline

Первый self-contained production baseline: FastAPI/PostgreSQL Control Center, dashboard/health, system/network overview, protected system actions, OS maintenance, AdGuard VPN, installer и GitHub updater.

## 1.1.0 — authentication, RBAC, backups, administration

Закреплена современная identity-модель: Linux/PAM, Samba/winbind через NSS/PAM, Kerberos/SPNEGO SSO, Control Center RBAC, privileged administration, product updates и backup/restore.

## 1.2.0 — dashboard, AdGuard VPN, Minecraft Bedrock

Расширены dashboard/full-admin capabilities, AdGuard VPN и Minecraft Bedrock management.

## 1.3.0 — Samba AD, shares, Minecraft administration

Добавлены Samba Active Directory administration, shares, portable domain backup/restore, RBAC для доменных/файловых операций и расширенное Minecraft administration.

## 1.3.1 — updater visibility maintenance

Добавлены отдельные updater timestamps и улучшена диагностируемость automatic updates.

## 1.3.2 — Minecraft compatibility maintenance

Попытка восстановить proven single-server Minecraft backend при сохранении нового UI/RBAC/CSRF. Real-server acceptance выявил дополнительные проблемы, исправлявшиеся следующими patch releases.

## 1.3.3 — updater/session/Minecraft hardening

Добавлены failed-fingerprint retry suppression, session continuity при rollback и fixes вокруг Minecraft timers/update path. Real-server preflight выявил следующий blocker.

## 1.3.4 — production preflight repair

Исправлен preflight так, чтобы нездоровый компонент, который release должен восстановить, не блокировал сам repair path.

## 1.3.5 — Minecraft runtime gate / GitHub timer repair

Исправлены runtime gates и восстановление automatic GitHub updater timer.

## 1.3.6 — updater bootstrap dependency repair

Устранён dependency cycle в updater bootstrap; optional Minecraft health перестал блокировать core product apply.

## 1.3.7 — release-relative acceptance/rollback repair

Исправлены release-relative execution проблемы acceptance и rollback.

## 1.3.8 — release metadata / privileged watcher repair

Финальный production repair baseline линии 1.x: исправлены application-readable release metadata и privileged system-action watcher, сохранена rollback lineage предыдущих patch releases.

---

## 2.0.0 — текущий production major baseline

**Статус:** **current production target** согласно `main/deployment.json` на момент этой редакции; frozen release.

2.0.0 переносит проверенную функциональность 1.x в новый major baseline и перестраивает ключевые эксплуатационные области.

Подтверждённый scope по production descriptor/frozen 2.0.0:

- переработанный интерфейс Control Center;
- rebuilt transactional updater/controller;
- product fingerprint и blocked/accepted release state;
- authoritative `backup_before_update` policy;
- bulk backup management;
- DHCP/PXE carry-forward;
- Samba/domain/shares carry-forward;
- health-first Minecraft Bedrock recovery и совместимость с proven single-server path;
- release acceptance/rollback и updater runtime recovery.

Licensing/Entitlement Engine **не входит в frozen 2.0.0**. Его staged rollout относится к будущим 2.1+ releases и описывается в `PRODUCT-EDITIONS.md`/`ROADMAP.md`.

---

## Release lineage summary

| Version | Назначение | Статус |
|---|---|---|
| 0.x | Инкрементальная pre-baseline разработка | Historical |
| 1.0.0 | Self-contained baseline | Released |
| 1.1.0 | Authentication/RBAC/Backups/Admin | Released |
| 1.2.0 | Dashboard/AdGuard/Minecraft | Released |
| 1.3.0 | Samba AD/Shares/Minecraft admin | Released |
| 1.3.1 | Updater visibility | Released |
| 1.3.2 | Minecraft compatibility repair | Released; further repairs followed |
| 1.3.3 | Updater/session/Minecraft hardening | Released; further repairs followed |
| 1.3.4 | Preflight repair | Released |
| 1.3.5 | Minecraft/runtime timer repair | Released |
| 1.3.6 | Updater bootstrap repair | Released |
| 1.3.7 | Acceptance/rollback repair | Released |
| 1.3.8 | Metadata + privileged watcher repair | Released; final 1.x baseline |
| 2.0.0 | New major baseline | **Current production** |

## Development after 2.0.0

Наличие `releases/2.1.0` в development branch или открытого draft PR не означает публикацию 2.1.0. До переключения `deployment.json` и прохождения release gate такая версия считается development/staging.

## Как читать исторические документы

`RELEASE-*.md`, старые incident notes и scope documents действительны в контексте соответствующего периода. Их утверждения о UI, первом входе, updater mechanics или runtime status не должны переопределять текущий production descriptor и frozen active release.

Для текущей эксплуатации используйте в порядке приоритета:

1. `../deployment.json`;
2. `../releases/<active-version>`;
3. актуальный server-state конкретного сервера;
4. `PRODUCT-MANUAL-RU.md`;
5. профильные current docs (`SYSTEM-ADMIN.md`, `AUTO-UPDATES.md`, `INSTALL.md`);
6. этот release history;
7. `ROADMAP.md` только для будущего scope.
