# Control Center — Product Roadmap

> Roadmap описывает будущую разработку. Production определяется только `../deployment.json` и frozen active release.

## Текущий контекст

- Активный production target: **2.1.0**.
- 2.0.0 и 2.1.0 опубликованы и frozen.
- 2.1.0 фактически выпущен как **Minecraft canonical runtime stabilization**, а не Licensing Stage 1.
- Licensing Stage 1 в frozen 2.0.0/2.1.0 не реализован.
- Ранее закреплённая схема «2.1.0 = Stage 1, … 2.5.0 = Stage 5» стала историческим планом и больше не может быть нормативной: опубликованный 2.1.0 не переписывается.
- Licensing rollout сохраняет последовательность Stage 1 → 5, но конкретные будущие номера версий назначаются при подготовке release scope. Следующий licensing feature release должен начинаться со Stage 1.

## Правила развития

`main` — production channel. Published releases frozen. Исправления публикуются новой версией. Production pointer переключается после CI/regression/acceptance. Привилегированные операции используют allowlisted helpers/services. Secrets не публикуются. Diagnostics проходят redaction. Документация синхронизируется с фактическим release до/сразу после publication. Emergency stabilization не считается автоматически выполнением следующего roadmap stage.

## Published 2.x baseline

### 2.0.0

Новый major baseline: обновлённый интерфейс/навигация, transactional updater, backup center, health-first Minecraft repair и перенос PAM/NSS/winbind, RBAC, Samba AD/shares, system services, OS/product updates, AdGuard VPN, network/system и DHCP/PXE compatibility paths. Licensing Stage 1 отсутствует в frozen payload.

### 2.1.0

Текущий production stabilization release: сохраняет существующий Minecraft world/settings, нормализует Bedrock runtime в `srv-control-minecraft-bedrock.service`, направляет Control Center operations через канонический service, отключает конфликтующий multi-instance updater и сохраняет rollback/fallback contract.

## Licensing roadmap — последовательные Stages 1–5

Полная архитектура — `PRODUCT-EDITIONS.md`. Номер будущего minor release не фиксируется этим документом заранее после фактического использования 2.1.0 для stabilization.

### Stage 1 — Edition / Entitlement Engine

Home/Professional edition state; единый backend entitlement engine; Home limits до 10 domain users и 10 SMB/network shares; enforcement до privileged mutation и через API; existing services продолжают работать при достижении лимита; System → License/About usage state; DB/API foundation; без private licensing keys в product repo.

Acceptance: persistent edition state, корректный usage, 1–10 разрешены/11-й блокируется, API/helper bypass невозможен, migration не теряет users/shares/rights, RBAC/backup/update/rollback regression green, docs/site синхронизированы.

### Stage 2 — Signed local Professional licenses

VM-safe `installation_id`, signed local certificate, public verification material, private signing keys только у licensing authority, tamper handling без остановки уже работающей критической инфраструктуры.

### Stage 3 — Online activation

Licensing API в официальном namespace `control-center.pro`, activation/installation/entitlement/audit model, signed certificate bound to installation, deactivate/transfer/re-host, activation limits и offline tolerance по последней валидной локальной лицензии.

### Stage 4 — Offline activation

Bounded request с installation identity/nonce, offline request/response, signed response import, replay/substitution/cross-installation protection.

### Stage 5 — Customer licensing portal

Личный кабинет, licenses/installations/activation status, deactivate/transfer/re-host, offline workflow и lifecycle documents; licensing administration отделён от privileged server control plane.

Следующий stage не начинается, пока предыдущий не прошёл acceptance.

## Другие направления 2.x

**DHCP/PXE:** service lifecycle, DHCP interfaces/subnets/ranges/options/leases/reservations, Windows/Linux PXE profiles, installation только для разрешённого client profile, software/configuration profiles и run history.

**Monitoring/operations:** infrastructure overview, CPU/RAM/storage/network/service health, SMART/NVMe, centralized logs, diagnostics, notifications, audit, maintenance mode, bounded automation/self-healing.

**Backup/DR:** service-specific backup profiles, retention/compression/integrity, disaster-recovery bundle, safe restore with acceptance/rollback.

**Storage/infrastructure:** storage manager, RAID/ZFS/Btrfs, snapshots vs backups, migration wizard, containers, KVM/libvirt, VLAN/virtual networks, WireGuard/firewall/security monitoring.

**Desired State для ПК:** AD computer inventory, software/config profiles, post-PXE reconciliation, history/drift/audit и безопасное применение к Windows clients.

## Правило актуализации

Перед релизом release scope выбирает пункты roadmap и фиксирует acceptance. После публикации фактически реализованное переносится в `PRODUCT-MANUAL-RU.md` и `RELEASE-HISTORY.md`; roadmap не используется как единственный источник инструкции. Уже опубликованный frozen release никогда не изменяется для соответствия старому плану.