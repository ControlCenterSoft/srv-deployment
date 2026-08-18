# Control Center — Product Roadmap

> **Статус документа:** канонический roadmap будущего развития.
>
> Production-состояние определяется только `../deployment.json` и frozen manifest активного релиза. Roadmap не является доказательством production-доступности функции.

## Текущий контекст

- Активный production target: **Control Center 2.0.0**.
- 2.0.0 уже опубликован и больше не является будущим release scope.
- Историческая 1.x линия и причины repair-релизов находятся в `RELEASE-HISTORY.md`.
- Требования прежнего 2.0 roadmap, которые не подтверждаются active manifest/frozen payload, автоматически не считаются реализованными и переносятся в будущую 2.x линию.

## Что уже закрыто выпуском 2.0.0

Согласно active manifest/frozen payload в production вошли:

- новый интерфейс Control Center;
- rebuilt transactional update controller;
- явные timestamps проверки/попытки/успешного update;
- bulk backup management;
- authoritative `backup_before_update` policy;
- health-first Minecraft Bedrock recovery;
- carried-forward DHCP/PXE management;
- сохранение ключевой authentication/RBAC/Samba/shares/service архитектуры 1.x.

Эти пункты теперь документируются в `PRODUCT-MANUAL-RU.md` и `RELEASE-HISTORY.md`, а не как будущие задачи roadmap.

## Правила развития и релизов

1. `main` — production update channel.
2. Каждый опубликованный `releases/<version>` frozen.
3. Исправление production выполняется новой версией, а не изменением frozen payload.
4. Production pointer переключается только после полного CI/regression/acceptance.
5. Real-server defects закрываются patch/repair-релизами.
6. Высокорисковые операции используют preflight, policy-controlled backup, acceptance и rollback, когда rollback возможен.
7. Привилегированные операции выполняются через allowlisted helpers/system services.
8. Secrets не публикуются в Git; diagnostics/logs проходят redaction.
9. Документация является частью release acceptance.
10. Новая функция считается production только после реализации, validation и публикации через `deployment.json`.

---

# Ближайшие направления 2.x

Ниже перечислены направления, а не обещанные номера или даты релизов. Конкретный release scope формируется отдельно.

## Licensing / Product Editions

Архитектура редакций описана в `PRODUCT-EDITIONS.md`.

Прежний roadmap включал Licensing Stage 1 в план 2.0.0, однако active 2.0.0 manifest не заявляет licensing/entitlement engine как часть опубликованного baseline. Поэтому licensing нельзя документировать как реализованный production-функционал без подтверждения frozen implementation.

Будущий licensing rollout должен проходить последовательно:

- Stage 1 — Edition / Entitlement Engine;
- Stage 2 — signed local Professional licenses;
- Stage 3 — online activation;
- Stage 4 — offline activation;
- Stage 5 — customer licensing portal.

Каждый stage считается завершённым только после backend enforcement, migration/regression checks, security review и синхронизации документации.

## DHCP и PXE — развитие после базового переноса

Базовые DHCP/PXE возможности уже включены в 2.0.0. Следующее развитие может включать:

- расширенное управление ranges, leases, reservations и custom DHCP options;
- lifecycle Windows/Linux PXE images/profiles;
- более строгий client-profile workflow;
- software/configuration profiles;
- installation history и acceptance каждой run;
- post-install reconciliation.

Конкретная возможность считается production только при наличии реализации в активном release.

## Monitoring, diagnostics и operations

- unified infrastructure overview;
- CPU/RAM/storage/network/service health;
- SMART/NVMe monitoring;
- централизованные logs;
- one-click diagnostics;
- notifications;
- audit center;
- maintenance mode;
- automation scheduler только для зарегистрированных безопасных действий;
- bounded self-healing без бесконечных циклов.

## Backup / Disaster Recovery

- backup profiles для Control Center, Samba AD, DHCP, PXE, Minecraft и поддерживаемых service configs;
- retention policies;
- compression/integrity verification;
- disaster-recovery bundle;
- restore pipeline с acceptance/rollback;
- более прозрачная визуализация размеров, возраста и состояния backup sets.

## Storage / infrastructure

- storage manager;
- RAID/mdadm и ZFS/Btrfs support;
- snapshot center с явным разделением snapshot и backup;
- storage migration wizard;
- Podman/container management;
- KVM/libvirt virtual machines;
- VLAN/virtual networks;
- WireGuard VPN server;
- firewall management и security monitoring.

## Desired State для клиентских ПК

- AD computer inventory;
- software profiles;
- configuration profiles;
- post-install reconciliation после PXE;
- history/drift detection/audit;
- безопасное применение политик к доменным Windows clients.

## Minecraft Bedrock — дальнейшее развитие

После health-first baseline 2.0.0 возможны:

- унификация legacy и multi-instance control path без конфликтующих timers;
- расширенный world lifecycle;
- безопасная автоматизация update/rollback;
- richer player/session telemetry;
- более полная диагностика runtime/package/world compatibility.

## Update Center — дальнейшее развитие

После rebuild 2.0.0 дальнейшие направления:

- richer release state/history;
- более явное отображение blocked failed fingerprints;
- guided recovery/manual retry;
- release notes/impact preview перед apply;
- maintenance windows;
- подтверждаемые rollback readiness checks до apply.

---

## Release gate для будущих функциональных релизов

Каждый новый функциональный release должен проходить минимум:

1. static/syntax checks;
2. UI/API contract validation;
3. authentication/RBAC regressions;
4. updater regression;
5. backup-policy regression;
6. Samba/share regression;
7. Minecraft regression, если затронут;
8. DHCP/PXE regression, если затронут;
9. migration test с текущего production baseline;
10. rollback test;
11. real-server acceptance для критичных изменений;
12. обновление `PRODUCT-MANUAL-RU.md`, `RELEASE-HISTORY.md`, профильных инструкций и roadmap.

Неактуальные неопубликованные development branches могут удаляться после безопасного перехода. Опубликованные frozen release directories и необходимая release lineage сохраняются.

## Связанные документы

- `README.md` — индекс документации;
- `PRODUCT-MANUAL-RU.md` — каноническое production-руководство;
- `RELEASE-HISTORY.md` — опубликованная история;
- `PRODUCT-EDITIONS.md` — editions/licensing architecture;
- `SYSTEM-ADMIN.md` — authentication/RBAC/privileged administration;
- `AUTO-UPDATES.md` — updater;
- `DEPLOYMENT-RELIABILITY.md` — deployment transaction model.
