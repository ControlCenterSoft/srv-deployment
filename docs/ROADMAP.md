# Control Center — Product Roadmap

> **Статус документа:** канонический roadmap текущего направления разработки.
>
> Production-состояние определяется только `../deployment.json` и frozen manifest активного релиза. Roadmap описывает будущую разработку и не означает, что перечисленные функции уже доступны в production.

## Текущий контекст

- Активный production target на момент актуализации документации: **1.3.8**.
- Новая линия разработки ведётся как **2.x**, начиная с **2.0.0**.
- Ранее планировавшиеся отдельные 1.4/1.5/1.6/1.7/1.8 этапы больше не являются каноническим порядком выпуска. Полезные требования из них переносятся в 2.x по мере реализации и проверки.
- Историческая 1.x детализация остаётся доступна в Git history, `RELEASE-HISTORY.md` и release-specific документах; она не должна использоваться как описание текущего production или обязательного будущего порядка релизов.

## Правила развития и релизов

1. `main` — единственный production update channel.
2. Каждый опубликованный релиз считается **frozen**: каталог `releases/<version>` не изменяется после публикации.
3. Исправление опубликованного релиза выполняется новой patch-версией, а не изменением frozen payload.
4. Production pointer переключается только после полного CI, regression и acceptance.
5. Real-server defects закрываются последовательными repair/patch-релизами; production не исправляется «на месте» без нового релиза.
6. Высокорисковые операции используют `preflight → safety backup → apply → acceptance → rollback`, когда rollback технически возможен.
7. Привилегированные системные операции выполняются через allowlisted helpers/system services, а не через произвольный shell из Web UI.
8. Секреты не публикуются в Git; diagnostics и logs проходят redaction.
9. Для долгоживущих функций используются Desired State, audit и RBAC.
10. Документация является частью release acceptance и синхронизируется с фактической реализацией до публикации релиза.

---

# 2.0.0 — новый Control Center

**Цель:** сформировать новый базовый major release с полностью обновлённым интерфейсом и исправленной эксплуатационной платформой, сохранив совместимость с проверенной 1.3.x функциональностью.

## Интерфейс

- полностью обновлённая визуальная система Control Center;
- единая навигация, responsive/mobile layout и keyboard accessibility;
- унифицированные loading/error/empty states;
- единые безопасные confirmation/prompt dialogs для административных операций;
- адаптация существующих модулей под новый интерфейс без потери их backend-контрактов;
- бренд продукта — **Control Center**, без устаревшего префикса `SRV` в новом интерфейсе и новой документации.

## Update Center / механизм обновления

Полностью переработать механизм product update с учётом дефектов 1.3.x:

- транзакционная модель обновления;
- устойчивый automatic timer, который не остаётся отключённым после неуспешной транзакции;
- product/release fingerprint вместо принятия решения только по commit SHA;
- suppression повторного автоматического запуска одного и того же неуспешного fingerprint;
- безопасный manual retry;
- восстановление updater runtime/configuration после release apply;
- явное разделение операций `check` и `apply`;
- сохранение и отображение временных меток:
  - **Последняя проверка обновления**;
  - **Последняя попытка обновления** — внутреннее/диагностическое состояние, если требуется;
  - **Последнее успешное обновление**;
- контроль состояния systemd service/timer и автоматическое восстановление расписания;
- acceptance механизма обновления на реальном сервере перед переключением production pointer.

## Backup Center

- массовый выбор и удаление резервных копий;
- typed confirmation для массового удаления;
- независимое управление scheduled backup и `backup_before_update`;
- отключение `backup_before_update` должно реально запрещать пользовательский pre-update backup и для product update, и для OS update;
- внутренний rollback snapshot release transaction не считается пользовательским backup и может сохраняться независимо от этой настройки;
- проверка create/download/delete/restore и bulk-delete contracts.

## Minecraft Bedrock Server

- диагностика фактического runtime/service/world state;
- health-first repair: исправлять только нездоровую установку;
- восстановление/обновление runtime с официального Bedrock package при необходимости;
- проверка systemd service, порта, server properties и запуска процесса;
- конфликтующие legacy/multi-instance update timers не должны одновременно управлять одним runtime;
- перед destructive recovery обязательно создаётся safety backup;
- при невозможности восстановить старый мир допускается переход на новый recovery world только после успешного backup старого состояния;
- после восстановления обязательны health/acceptance checks.

## Перенос функциональности 1.x

Все актуальные функции 1.x должны быть либо перенесены, либо явно признаны deprecated до выпуска 2.0.0. Обязательная проверка включает:

- PAM/NSS/winbind authentication и Kerberos/SPNEGO SSO, где настроено;
- RBAC и privileged action architecture;
- Samba AD/domain administration;
- SMB shares;
- системные сервисы;
- automatic/manual product updates;
- OS updates;
- backup/restore;
- Minecraft Bedrock;
- AdGuard VPN;
- Downloads/Torrent integrations;
- текущие network/system pages;
- diagnostics/server-state contracts.

## 2.0.0 release gate

Production pointer нельзя переключать на 2.0.0, пока не выполнены одновременно:

1. static/syntax checks;
2. UI contract validation;
3. updater regression tests;
4. backup-policy regression tests;
5. Minecraft health/recovery tests;
6. authentication/RBAC regressions;
7. Samba/share regressions;
8. migration test с фактической 1.3.8 production line;
9. rollback test;
10. real-server acceptance;
11. актуализация `PRODUCT-MANUAL-RU.md`, `RELEASE-HISTORY.md`, `INSTALL.md`, `SYSTEM-ADMIN.md`, `AUTO-UPDATES.md` и этого roadmap.

После успешного перехода неактуальные **неопубликованные** 1.x development branches могут быть удалены. Опубликованные frozen release directories и необходимая историческая release lineage сохраняются.

---

# После 2.0.0 — функциональные направления 2.x

Ниже перечислены направления, а не обещанные номера/даты релизов. Приоритет определяется отдельным release scope.

## DHCP и PXE

- установка/удаление DHCP и PXE services из Control Center;
- DHCP interfaces, subnet, mask, gateway, DNS, ranges, leases, reservations и custom options;
- PXE Windows image lifecycle;
- PXE Linux profiles;
- установка разрешена только для ПК с созданным/включённым PXE client profile;
- MAC как основной идентификатор, optional DHCP IP, Windows-safe computer name, optional domain join;
- software/configuration profiles;
- history и acceptance каждой installation run.

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
- retention, compression и integrity verification;
- disaster-recovery bundle;
- безопасный restore pipeline с acceptance и rollback.

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
- history, drift detection и audit;
- безопасное применение политик к доменным Windows clients.

## Product editions и licensing

Архитектура редакций описывается отдельно в `PRODUCT-EDITIONS.md`. Licensing не должен ослаблять security controls, RBAC, backup safety или integrity проверки.

---

## Связанные документы

- `README.md` — индекс документации;
- `PRODUCT-MANUAL-RU.md` — каноническое руководство пользователя/администратора;
- `RELEASE-HISTORY.md` — опубликованная release lineage;
- `SYSTEM-ADMIN.md` — authentication/RBAC/system administration;
- `AUTO-UPDATES.md` — update architecture;
- `DEPLOYMENT-RELIABILITY.md` — transaction/rollback model;
- `PRODUCT-EDITIONS.md` — editions/licensing.

## Правило актуализации roadmap

Перед каждым новым release scope необходимо:

1. определить, какие пункты этого roadmap входят в релиз;
2. отделить реализованное от запланированного;
3. после публикации перенести фактически реализованные пользовательские возможности в `PRODUCT-MANUAL-RU.md` и `RELEASE-HISTORY.md`;
4. не оставлять roadmap единственным источником инструкции по уже выпущенной функции.
