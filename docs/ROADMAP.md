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
11. Для каждого нового **функционального** релиза автоматически включается следующий незавершённый этап licensing roadmap из `PRODUCT-EDITIONS.md`. Этапы идут строго последовательно и не пропускаются.
12. Emergency repair/hotfix patch-релиз не продвигает licensing roadmap сам по себе. Если активный licensing stage не завершён acceptance, он остаётся обязательным для следующего функционального релиза.
13. Новый release scope обязан явно указывать активный licensing stage и его acceptance criteria до начала реализации.

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

## Licensing Stage 1 — Edition / Entitlement Engine

**Обязательный scope 2.0.0.** Это первый этап последовательного внедрения Professional licensing и он должен войти в 2.0.0 по умолчанию.

- ввести явное edition state: **Control Center Home** / **Control Center Professional**;
- единый Entitlement Engine в Core с API/backend enforcement, а не только UI-ограничениями;
- Home: максимум **10 доменных пользователей**;
- Home: максимум **10 сетевых общих ресурсов (SMB/network shares)**;
- попытка создать 11-го доменного пользователя или 11-ю шару должна безопасно блокироваться до изменения системы и показывать требование Professional;
- коммерческое использование остаётся Professional независимо от количества пользователей/шар;
- достижение лимита не должно останавливать уже работающие Samba AD, SMB, DHCP, DNS или другие критические сервисы;
- добавить **Система → О системе / Лицензия** либо эквивалентный экран с edition, entitlement state, текущим использованием Home-лимитов и состоянием лицензии;
- подготовить schema/state/API foundation для последующих signed-license и activation stages;
- licensing private key или activation secrets на Stage 1 не требуются и не должны появляться в product repository.

### Stage 1 acceptance

Stage 1 нельзя считать завершённым, пока одновременно не проверено:

1. Home edition определяется детерминированно и сохраняется после reboot/update;
2. текущие значения domain-user/share usage отображаются корректно;
3. 1–10 доменных пользователей допускаются, 11-й блокируется до privileged mutation;
4. 1–10 сетевых шар допускаются, 11-я блокируется до privileged mutation;
5. обход UI прямым API-запросом не позволяет превысить лимит;
6. privileged helper/system boundary также не позволяет обойти entitlement check;
7. существующая Home-конфигурация при достижении лимита продолжает обслуживать уже созданные ресурсы;
8. migration с production 1.3.8 не теряет пользователей, шары и права;
9. RBAC, backup, update и rollback regression проходят;
10. `PRODUCT-EDITIONS.md`, `PRODUCT-MANUAL-RU.md`, release notes и сайт синхронизированы с фактической реализацией.

После acceptance Stage 1 следующий функциональный релиз автоматически получает **Licensing Stage 2 — Signed local Professional licenses** из `PRODUCT-EDITIONS.md`.

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
8. **Licensing Stage 1 acceptance полностью пройден**;
9. migration test с фактической 1.3.8 production line, включая сохранение domain users и SMB shares;
10. rollback test;
11. real-server acceptance;
12. актуализация `PRODUCT-MANUAL-RU.md`, `RELEASE-HISTORY.md`, `INSTALL.md`, `SYSTEM-ADMIN.md`, `AUTO-UPDATES.md`, `PRODUCT-EDITIONS.md` и этого roadmap.

После успешного перехода неактуальные **неопубликованные** 1.x development branches могут быть удалены. Опубликованные frozen release directories и необходимая историческая release lineage сохраняются.

---

# После 2.0.0 — функциональные направления 2.x

Ниже перечислены направления, а не обещанные номера/даты релизов. Приоритет определяется отдельным release scope. Исключение — последовательный licensing track: следующий незавершённый licensing stage включается в каждый новый функциональный release scope автоматически.

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

Архитектура редакций и полный staged rollout описываются в `PRODUCT-EDITIONS.md`. Licensing не должен ослаблять security controls, RBAC, backup safety или integrity проверки.

Автоматический порядок после Stage 1:

- следующий функциональный релиз после принятого 2.0.0 → **Stage 2: signed local Professional licenses**;
- следующий после принятого Stage 2 → **Stage 3: online activation service**;
- следующий после принятого Stage 3 → **Stage 4: offline activation**;
- следующий после принятого Stage 4 → **Stage 5: customer licensing portal**.

Точные номера этих релизов назначаются при начале их подготовки и не угадываются заранее. Если предыдущий stage не прошёл acceptance, следующий stage не начинается.

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
2. **автоматически назначить следующий незавершённый licensing stage из `PRODUCT-EDITIONS.md` для функционального релиза**;
3. записать acceptance criteria этого licensing stage в release scope;
4. отделить реализованное от запланированного;
5. после публикации перенести фактически реализованные пользовательские возможности в `PRODUCT-MANUAL-RU.md` и `RELEASE-HISTORY.md`;
6. отметить licensing stage как принятый только после его полного acceptance;
7. не оставлять roadmap единственным источником инструкции по уже выпущенной функции.
