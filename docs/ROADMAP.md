# Control Center — Product Roadmap

> **Статус документа:** канонический roadmap текущего направления разработки.
>
> Production-состояние определяется только `../deployment.json` и frozen manifest активного релиза. Roadmap описывает будущую разработку и не означает, что перечисленные функции уже доступны в production.

## Текущий контекст

- Активный production target: **2.0.0**.
- 2.0.0 опубликован и является frozen release; его payload не переписывается задним числом.
- Фактическая проверка 2.0.0 показала, что Licensing Stage 1 / Entitlement Engine в этот релиз не вошёл.
- Последовательное внедрение licensing начинается с **2.1.0** и продолжается фиксированными minor-релизами до 2.5.0.
- Историческая 1.x детализация остаётся доступна в Git history, `RELEASE-HISTORY.md` и release-specific документах; она не должна использоваться как описание текущего production.

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
11. Licensing stages 1–5 идут строго последовательно в релизах 2.1.0–2.5.0.
12. Emergency repair/hotfix patch-релиз не продвигает licensing roadmap сам по себе.
13. Если предыдущий licensing stage не прошёл acceptance, следующий stage не начинается.
14. Новый licensing release scope обязан явно содержать stage requirements и acceptance criteria до начала реализации.

---

# 2.0.0 — опубликованный базовый Control Center 2.x

**Статус:** production / frozen.

2.0.0 сформировал новый базовый major release с обновлённым интерфейсом и эксплуатационной платформой, сохранив перенос проверенной функциональности предыдущей линии.

## Реализованный scope 2.0.0

### Интерфейс

- обновлённая визуальная система Control Center;
- единая навигация и обновлённые административные страницы;
- унифицированные loading/error/empty states в перенесённых модулях;
- безопасные confirmation/prompt dialogs для административных операций;
- адаптация существующих модулей без потери backend-контрактов;
- публичный бренд продукта — **Control Center**.

### Update Center / механизм обновления

- транзакционная модель обновления;
- устойчивый automatic timer;
- product/release fingerprint;
- suppression повторного автоматического запуска одного и того же неуспешного fingerprint;
- безопасный manual retry;
- восстановление updater runtime/configuration после release apply;
- разделение `check` и `apply`;
- временные метки последней проверки и последнего успешного обновления;
- контроль состояния systemd service/timer.

### Backup Center

- массовый выбор и удаление резервных копий;
- typed confirmation для массового удаления;
- независимое управление scheduled backup и `backup_before_update`;
- authoritative backup-before-update policy;
- create/download/delete/restore и bulk-delete contracts.

### Minecraft Bedrock Server

- health-first repair;
- восстановление/обновление runtime при необходимости;
- проверка systemd service, порта, properties и процесса;
- защита от конфликтующих update timers;
- safety backup перед destructive recovery;
- обязательные health/acceptance checks.

### Перенесённая функциональность

Проверяемая линия 2.0.0 включает перенос/совместимость для:

- PAM/NSS/winbind authentication и Kerberos/SPNEGO SSO, где настроено;
- RBAC и privileged action architecture;
- Samba AD/domain administration;
- SMB shares;
- системных сервисов;
- automatic/manual product updates;
- OS updates;
- backup/restore;
- Minecraft Bedrock;
- AdGuard VPN;
- Downloads/Torrent integrations;
- network/system pages;
- DHCP/PXE management carry-forward;
- diagnostics/server-state contracts.

## Результат аудита licensing в 2.0.0

Licensing Stage 1 **не реализован** в фактическом frozen payload 2.0.0. Проверка показала:

- в release manifest 2.0.0 licensing/entitlement не заявлен;
- в payload отсутствует отдельный entitlement/license module;
- отсутствует новая DB migration для edition/license/entitlement state;
- System UI не содержит страницы/блока **О системе / Лицензия** с edition и Home usage;
- release acceptance 2.0.0 не проверяет лимиты 10 domain users / 10 network shares, API bypass или privileged-boundary enforcement.

Поэтому 2.0.0 не изменяется; Stage 1 переносится в 2.1.0.

---

# Licensing roadmap 2.1.0–2.5.0

Полная архитектура описана в `PRODUCT-EDITIONS.md`. Номера этапов теперь закреплены за конкретными minor-релизами.

## 2.1.0 — Licensing Stage 1: Edition / Entitlement Engine

**Обязательный scope 2.1.0.**

- явное edition state: **Control Center Home** / **Control Center Professional**;
- единый Entitlement Engine в Core с API/backend enforcement;
- Home: максимум **10 доменных пользователей**;
- Home: максимум **10 сетевых общих ресурсов (SMB/network shares)**;
- попытка создать 11-го доменного пользователя или 11-ю шару блокируется до системной mutation и показывает требование Professional;
- коммерческое использование остаётся Professional независимо от количества пользователей/шар;
- достижение лимита не останавливает уже работающие Samba AD, SMB, DHCP, DNS или другие критические сервисы;
- **Система → О системе / Лицензия** показывает edition, entitlement state, использование лимитов и placeholder будущей активации;
- DB/state/API foundation для следующих licensing stages;
- никаких licensing private keys или activation secrets в product repository.

### 2.1.0 Stage 1 acceptance

Stage 1 нельзя считать завершённым, пока одновременно не проверено:

1. Home edition определяется детерминированно и сохраняется после reboot/update;
2. текущие значения domain-user/share usage отображаются корректно;
3. 1–10 доменных пользователей допускаются, 11-й блокируется до privileged mutation;
4. 1–10 сетевых шар допускаются, 11-я блокируется до privileged mutation;
5. обход UI прямым API-запросом не позволяет превысить лимит;
6. privileged helper/system boundary не позволяет обойти entitlement check;
7. существующая Home-конфигурация при достижении лимита продолжает обслуживать уже созданные ресурсы;
8. migration с production 2.0.0 не теряет пользователей, шары и права;
9. RBAC, backup, update и rollback regression проходят;
10. `PRODUCT-EDITIONS.md`, `PRODUCT-MANUAL-RU.md`, release notes и сайт синхронизированы с фактической реализацией.

## 2.2.0 — Licensing Stage 2: Signed local Professional licenses

- постоянный VM-safe `installation_id`;
- подписанный local license certificate;
- Ed25519 verification public material в продукте;
- private signing keys только на стороне licensing authority;
- Professional entitlement state из валидного signed certificate;
- защита от tampered/invalid license без остановки уже работающих критических инфраструктурных сервисов.

## 2.3.0 — Licensing Stage 3: Online activation service

- licensing API в официальном namespace `control-center.pro`, предпочтительно `api.control-center.pro`;
- customer/license/installation/activation/entitlement/audit data model;
- activation key используется как credential для выдачи runtime license certificate;
- подписанная online activation, связанная с `installation_id`;
- deactivate / transfer / re-host;
- enforcement количества разрешённых активаций;
- работа по последней валидной локальной лицензии при временной потере сети.

## 2.4.0 — Licensing Stage 4: Offline activation

- экспорт bounded activation request с installation identity и nonce;
- offline request/response workflow через подключённый портал/API;
- импорт signed license response в изолированную установку;
- защита от replay/substitution/cross-installation misuse;
- отсутствие требования постоянного Интернет-соединения для критической инфраструктуры.

## 2.5.0 — Licensing Stage 5: Customer licensing portal

- личный кабинет на `control-center.pro`;
- просмотр лицензий, installations и activation status;
- deactivate / transfer / re-host;
- offline activation request/response workflow;
- lifecycle/update entitlement и license documents;
- licensing administration отделён от privileged infrastructure control plane сервера.

После принятого 2.5.0 licensing развивается как обычное направление roadmap без автоматического Stage 6.

---

# После 2.0.0 — другие функциональные направления 2.x

Эти направления могут планироваться параллельно, но не отменяют закреплённый licensing track 2.1.0–2.5.0.

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

Фиксированный порядок:

- **2.1.0 → Stage 1**;
- **2.2.0 → Stage 2**;
- **2.3.0 → Stage 3**;
- **2.4.0 → Stage 4**;
- **2.5.0 → Stage 5**.

Если предыдущий stage не прошёл acceptance, следующий stage не начинается.

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
2. для 2.1.0–2.5.0 включить закреплённый licensing stage соответствующего номера;
3. записать acceptance criteria licensing stage в release scope;
4. отделить реализованное от запланированного;
5. после публикации перенести фактически реализованные пользовательские возможности в `PRODUCT-MANUAL-RU.md` и `RELEASE-HISTORY.md`;
6. отметить licensing stage как принятый только после полного acceptance;
7. не начинать следующий licensing stage, если предыдущий не принят;
8. не оставлять roadmap единственным источником инструкции по уже выпущенной функции.
