# SRV Control Center — Product Roadmap

> **Статус документа:** канонический roadmap проекта.
>
> Этот файл является основной точкой фиксации согласованного направления развития SRV Control Center. При изменении требований сначала корректируется этот документ, затем соответствующий release scope/implementation plan.

## Правила развития и релизов

1. `main` — единственный production update channel.
2. Каждый опубликованный релиз считается **frozen**: его каталог `releases/<version>` не изменяется после публикации.
3. Исправление дефекта опубликованного релиза выполняется только новой patch-версией: `1.4.1`, `1.4.2`, `1.5.1` и т. д.
4. Production pointer переключается на новый major/minor release только после полного CI, regression и acceptance.
5. Real-server defects закрываются последовательными patch-релизами; запрещено исправлять production «на месте» без нового релиза.
6. Высокорисковые операции должны иметь `preflight → safety backup → apply → acceptance → rollback` там, где rollback технически возможен.
7. Привилегированные системные операции выполняются через whitelisted helpers/system services, а не через произвольный shell из Web UI.
8. Секреты не публикуются в Git, diagnostics и logs проходят redaction.
9. Для долгоживущих функций используется Desired State, audit и RBAC вместо набора необратимых разовых скриптов.

---

# 1.4.0 — Network Provisioning: DHCP + PXE

**Цель:** превратить SRV Control Center в центр сетевой загрузки и автоматизированной установки клиентских ОС.

## Services

- В разделе **«Сервисы»** активировать установку/удаление DHCP Server и PXE Server по модели уже управляемых сервисов.
- Фактическое состояние сервиса, install/remove, health и audit.

## DHCP

Активировать полноценное меню **«DHCP»**:

- выбор интерфейса;
- сеть/маска;
- gateway;
- DNS;
- диапазоны выдачи адресов;
- leases;
- reservations;
- просмотр MAC/IP/hostname;
- дополнительные DHCP options как `код параметра + значение`;
- список назначенных дополнительных параметров с изменением/удалением;
- строгая валидация сети и конфликтов;
- RBAC и audit для всех изменений.

## PXE Server Windows

### Windows image lifecycle

- загрузка ISO Windows в Control Center;
- мастер импорта образа;
- анализ редакций/архитектуры;
- подготовка файлов загрузки;
- публикация установочного профиля;
- управление несколькими Windows images/profiles;
- возможность снять профиль с публикации без удаления исходного ISO.

### Авторизация компьютеров

**Установка ОС запрещена, если профиль PXE для компьютера не создан.**

Профиль ПК содержит:

- MAC — основной идентификатор; может выбираться из DHCP leases;
- IP из DHCP, если известен; поле необязательное;
- имя ПК на английском с полной проверкой правил Windows computer name;
- выбор домена или режим «не вводить в домен»;
- назначение одного или нескольких software profiles;
- назначение одного или нескольких configuration profiles;
- защита от дублирования одного ПК в несовместимых профилях;
- enabled/disabled;
- история установки и последний результат.

### Installation pipeline

Базовая схема:

`PXE authorized → OS profile → disk layout → Windows setup → drivers → domain join (optional) → software profiles → configuration profiles → acceptance`

В 1.4 основной акцент — безопасное первоначальное развёртывание; полноценный Desired State после установки относится к 1.7.0.

## PXE Server Linux

Отдельный модуль **«PXE-сервер Linux»**:

- загрузка ISO Linux;
- профили установки;
- UEFI/BIOS boot;
- unattended/autoinstall profiles там, где поддерживается;
- та же модель авторизации по созданному PXE client profile;
- история installation runs.

## Общие требования 1.4

- DHCP и PXE должны иметь независимые health checks.
- Нельзя публиковать небезопасный/неполный PXE profile.
- Все destructive действия подтверждаются и журналируются.
- Acceptance включает DHCP sandbox, PXE config syntax, profile authorization contract и real-server validation.

---

# 1.5.0 — Operations: Monitoring, Backup, DR & Automation

**Тема:** мониторинг, резервирование, диагностика и автоматизация эксплуатации сервера.

## Функциональный scope

### Unified Infrastructure Overview

Интерактивная схема:

`Internet → WAN → Firewall → LAN/Wi-Fi → DHCP → AD/DNS → Clients → PXE / Shares / Minecraft / Torrents`

Состояния: `OK / Warning / Degraded / Failed / Disabled / Maintenance`.

Dashboard показывает Health Score, uptime, CPU, RAM, storage, network, active clients, alerts и recent events.

### Monitoring Center

- CPU/load/uptime;
- RAM/swap;
- temperatures;
- filesystem/storage usage;
- disk I/O;
- network RX/TX;
- systemd service state/restart information;
- история `1h / 24h / 7d / 30d`;
- retention policy для metrics.

### Storage Health

- SMART/NVMe health;
- temperature;
- SSD/NVMe wear/resource;
- reallocated/pending/media errors;
- usage thresholds по умолчанию `80/90/95%`;
- breakdown по Samba, PXE, Minecraft, backups, torrents и Control Center.

### Backup Center

Профили backup для:

- Control Center state/config;
- PostgreSQL;
- Samba AD;
- DHCP;
- PXE;
- Minecraft;
- системной конфигурации;
- поддерживаемых service configs.

Настройки: schedule, destination, retention, compression, SHA-256 verification, cleanup policy, history.

### Disaster Recovery

`SRV Recovery Bundle` с мастер-восстановлением:

`preflight → archive analysis → safety backup → restore → service restart → acceptance → rollback on failure`.

Секреты исключаются либо помещаются в отдельно защищённый encrypted payload.

### Logs

Централизованный просмотр Control Center, nginx, systemd, Samba, DHCP, PXE, Minecraft, updater, backup, PostgreSQL, qBittorrent/TorrServer и системных событий.

Фильтры: time, severity, service, search. Экспорт diagnostics только после redaction.

### Notifications

- встроенный Notification Center;
- e-mail;
- Telegram;
- cooldown/deduplication;
- события service/disk/backup/update/certificate/DHCP/PXE/Minecraft/database/Samba health.

### Automation Scheduler

Только зарегистрированные безопасные действия:

- health check;
- backup;
- restart service;
- Minecraft update;
- OS package update;
- cleanup backups/logs;
- refresh PXE metadata.

Параметры: schedule, timeout, retries, owner, run history.

### Self-Healing

`health check → bounded restart attempts → recheck → degraded → notification`.

Бесконечные циклы запрещены. Samba/PostgreSQL/network получают отдельные safety rules.

### Update Center 2.0

- current/target version;
- commit SHA;
- release notes;
- installation history;
- стадии `detected/preflight/backup/apply/acceptance/success/rollback/failed`;
- maintenance window;
- manual/automatic mode;
- repeated failed fingerprint suppression;
- manual retry;
- Ubuntu security/regular updates.

### Network Clients Monitoring

- hostname/IP/MAC;
- DHCP lease;
- interface;
- first/last seen;
- online/offline;
- RX/TX;
- ссылки на DHCP reservation, PXE profile, AD computer, block/access policy.

### Audit Center

- actor/auth source/IP/time/module/action/object/result;
- before/after diff без секретов;
- отдельная категория `high-risk`.

### TLS / Certificates

- CN/SAN/issuer/validity/expiration;
- import/replace;
- local CA;
- expiration alerts `30/14/7/3/1` days;
- приватные ключи никогда не возвращаются API.

### Health Score

Агрегирует system, storage, network, Samba, DB, backup, updates, certificates, Minecraft, DHCP/PXE. Critical fault не скрывается высоким средним score.

### Maintenance Mode

- блокирует конфликтующие automation/self-healing/auto-update actions;
- monitoring остаётся активным;
- ожидаемые alerts подавляются;
- выход из maintenance запускает обязательный health check.

### One-Click Diagnostics

Read-only комплексная проверка systemd, filesystem, storage, PostgreSQL, Samba AD, DNS, DHCP, PXE, Minecraft, nginx, certificates, updater, backups и Control Center API с итогом `PASS/WARNING/FAIL`.

### RBAC 1.5

Новые permissions:

`monitoring.read`, `logs.read`, `backup.read`, `backup.run`, `backup.restore`, `automation.read`, `automation.run`, `automation.manage`, `updates.read`, `updates.apply`, `certificates.read`, `certificates.manage`, `audit.read`, `diagnostics.run`.

Restore, certificate management, update apply и high-risk automation — только admin/full-admin.

## Порядок реализации 1.5.0

1. DB schema + migrations + RBAC + universal jobs + audit foundation.
2. Monitoring Core.
3. Storage Health.
4. Health Engine.
5. Backup Center.
6. Disaster Recovery.
7. Logs & Diagnostics.
8. Notifications.
9. Automation Scheduler.
10. Self-Healing.
11. Update Center 2.0.
12. Audit Center UI.
13. TLS / Certificates.
14. Network Clients Monitoring.
15. Unified Dashboard.
16. Maintenance Mode integration.
17. Full 1.5.0 acceptance.

Каждая фаза получает отдельный regression milestone; production pointer меняется только после завершения всех фаз.

---

# 1.6.0 — Infrastructure: Storage, Containers, VM & Security

**Цель:** превратить Control Center в локальную инфраструктурную платформу.

## Storage Manager

- физические SATA/SAS/NVMe/USB диски;
- partitions/filesystems/mounts;
- EXT4/XFS/Btrfs;
- UUID/labels;
- create/format/mount/extend/unmount;
- dependency awareness;
- destructive preflight + explicit confirmation.

## RAID

`mdadm` backend:

- RAID1/5/6/10;
- RAID0 только с явным предупреждением;
- create/add/replace;
- rebuild progress;
- degraded state;
- hot spare;
- scrub/check;
- failure notifications.

## ZFS

- pools/vdevs/datasets;
- compression;
- quotas/reservations;
- snapshots/clones;
- scrub;
- disk replacement;
- snapshot schedules;
- datasets как storage backend для Samba/PXE/Minecraft/Backup/Containers/VM.

## Storage Migration Wizard

Безопасное перемещение данных сервисов на другой storage:

`preflight → stop/quiesce → copy → checksum → reconfigure → start → acceptance → optional old-data cleanup`.

## Snapshot Center

Единый интерфейс ZFS/Btrfs snapshots, retention, rollback и clone. UI явно показывает: **snapshot не является backup**.

## Container Manager

Первая реализация — **Podman**, backend остаётся абстрактным:

- images;
- containers;
- volumes;
- networks;
- environment/secrets references;
- ports;
- logs;
- start/stop/restart;
- CPU/RAM limits;
- healthcheck;
- autostart.

## Application Catalog

Версионируемые/контролируемые SRV manifests для приложений (например Jellyfin, Home Assistant, Immich, Nextcloud, Vaultwarden, Grafana, Prometheus, Uptime Kuma).

Никаких автоматически исполняемых случайных manifests из Интернета.

## Custom Compose

Только для advanced/full-admin:

`parse → security analysis → ports → mounts → privileges → secrets → preview → confirmation`.

Отдельно маркируются `privileged`, host network, `/dev`, root mounts, container socket и capabilities.

## Virtual Machine Manager

KVM/QEMU + libvirt:

- create/delete;
- CPU/RAM/disk;
- ISO;
- network;
- UEFI/BIOS;
- Secure Boot;
- lifecycle;
- snapshots;
- autostart;
- HTML5 console;
- Ubuntu/Debian/Windows 11/Windows Server templates.

Интеграция **PXE/ISO Library → Create VM** для проверки установочных образов перед разрешением физическим клиентам.

## Virtual Networks / VLAN

- LAN bridge;
- NAT;
- isolated networks;
- VLAN;
- VLAN ID/parent/subnet/DHCP/firewall zone;
- готовые IoT и Guest profiles.

## VPN Server

WireGuard:

- users/devices;
- keys;
- QR;
- allowed networks;
- expiration/revoke;
- last handshake;
- RX/TX.

Control Center по умолчанию не публикуется напрямую в Internet; удалённое администрирование идёт через VPN.

## MFA & Sessions

- TOTP;
- recovery codes;
- mandatory MFA для full-admin;
- active sessions, IP/device/login/last activity;
- revoke one/all other sessions.

## Firewall 2.0

Object-based UI: `Zones → Rules → Services → Hosts → Networks`.

Port Forwarding wizard с предупреждениями для Control Center, Samba, PostgreSQL, SSH, AD/DC.

## IDS — первая версия

Suricata alerts/history/severity/source/destination/signature/protocol. Автоматический IPS/blocking по умолчанию выключен.

## Security Center

Единый экран Security Score, Firewall, VPN, MFA, Certificates, Updates, IDS, failed logins, open ports и admin sessions.

## Secrets Vault

Секреты SMTP/Telegram/VPN/API/apps/backup encryption не хранятся как обычные значения в PostgreSQL. API после сохранения показывает только `Configured / Not configured`.

## Resource Quotas

CPU/RAM/storage limits для containers, VMs, Minecraft и applications. UI показывает physical/reserved/used/available.

## Dependency Engine

Нельзя удалить storage/network/object, пока его используют Samba, Minecraft, VM, Container, Backup, PXE или другой компонент. UI показывает зависимости.

## Infrastructure Map 2.0

Расширение схемы 1.5 до Firewall/IDS/VPN/VLAN/IoT/Guest/Storage/Containers/VM/Applications.

## Ansible foundation

В 1.6 добавляется **Ansible Core как внутренний orchestration backend**:

- inventory abstraction;
- controlled predefined playbooks;
- RBAC/audit;
- никаких произвольных playbooks для обычного администратора;
- архитектурный фундамент для Endpoint Management 1.7.

Ansible не является единственным механизмом управления Windows-клиентами.

---

# 1.7.0 — Endpoint Management: Domain + PXE Clients

**Цель:** единая система установки ПО и управления параметрами клиентских компьютеров.

## Единая модель клиента

Один компьютер может иметь признаки:

- `Domain Client`;
- `PXE Client`;
- одновременно оба (установлен через PXE и затем введён в домен).

Карточка клиента:

- computer name;
- MAC;
- current/last IP;
- OS edition/build;
- domain/OU;
- current user;
- PXE profile;
- installed software;
- assigned software/configuration profiles;
- last seen/online;
- compliance/sync state.

## Desired State Engine

Пользователь задаёт не только разовую команду, а требуемое состояние:

`Client/Group → Software Profiles + Configuration Profiles + Policies`.

Состояния: `Desired / Actual / Compliant / Drifted / Failed`.

Если ПК выключен, назначение сохраняется и применяется после появления клиента онлайн.

## Software Repository

Пакеты:

- MSI;
- MSIX;
- EXE silent installers;
- PowerShell installers;
- offline packages из SRV.

Metadata:

- name/vendor/version/architecture;
- installer type;
- silent arguments;
- dependencies/order;
- detection rule;
- uninstall rule;
- expected version;
- reboot requirement;
- SHA-256.

Изменившийся бинарный файл не выполняется без повторного утверждения.

## Software Profiles

Профили могут наследоваться/комбинироваться и назначаться ПК/группам/OU/PXE profiles.

Пример:

`Base PC → 7-Zip + Browser + VLC + Reader + Office suite`

`Accounting Workstation → Base PC + accounting/crypto software`.

## Configuration Profiles

Декларативное управление:

- registry;
- local policies;
- Windows firewall;
- services;
- mapped drives;
- printers;
- certificates;
- Wi-Fi;
- DNS/proxy;
- power settings;
- Windows Update policy;
- desktop/start menu;
- environment variables;
- browser settings;
- RDP;
- BitLocker policy.

## Domain Clients + GPO

Назначение профилей:

- user;
- user group;
- computer;
- computer group;
- OU.

Полноценное управление Samba-compatible GPO из Control Center для естественных domain policies.

## PXE Client Lifecycle

`PXE authorized → OS → disk layout → drivers → domain join → software profiles → configuration profiles → acceptance`.

PXE становится началом полного жизненного цикла endpoint, а не только установщиком ОС.

## SRV Client Agent for Windows

Лёгкий клиентский агент для задач, неудобных/ненадёжных через GPO/WinRM:

- hardware/software inventory;
- task status/progress;
- retries;
- compliance;
- online/offline;
- reboot request;
- post-PXE configuration;
- Desired State convergence.

Agent не принимает произвольный shell; только подписанные/разрешённые task types. Machine identity — уникальный token/certificate over TLS.

## Ansible in 1.7

Архитектура доставки:

- **GPO** — domain policy, registry/security/mapped resources/certificates и естественные AD policies;
- **Ansible** — orchestration, bootstrap, массовая конфигурация/remediation и поддерживаемые software operations;
- **SRV Client Agent** — persistent Desired State, inventory, offline catch-up, progress/retries/compliance и сложные endpoint tasks.

Пользователь работает с профилями Control Center, а backend выбирает delivery channel.

## Inventory & Dynamic Groups

Inventory: CPU/RAM/disks/GPU/NICs, installed software, Windows updates, free space, uptime, logged-in user, BitLocker и antivirus state.

Dynamic groups, например:

- Windows 11;
- laptops;
- PXE-installed;
- domain clients;
- offline > N days;
- disk free < threshold;
- software missing/outdated.

## Compliance Center

По каждому клиенту и профилю: `compliant/warning/failed`, с деталями по software/settings.

## Removal semantics

При снятии профиля для каждого компонента поддерживается policy:

- leave;
- uninstall/remove;
- restore previous setting, если технически возможно.

## Security/RBAC

- SHA-256 packages;
- signed/allowed task types;
- audit;
- no passwords in task payload;
- high-risk category для BitLocker/firewall/destructive operations;
- full-admin для наиболее опасных endpoint actions.

---

# 1.8.0 — High Availability / Multi-SRV

**Тема:** несколько физических SRV и отказоустойчивая инфраструктура.

Предварительный scope:

- Multi-SRV inventory;
- cluster membership;
- node health/quorum model;
- service failover;
- HA Control Center components;
- distributed/replicated configuration;
- controlled workload placement;
- VM live migration — при подтверждении технической модели;
- distributed storage — после отдельного design/acceptance;
- multi-site/fleet management;
- расширенный IDS/IPS и security orchestration.

Точный scope 1.8 фиксируется отдельным design document после стабилизации 1.7.x.

---

# Архитектурная последовательность

| Release | Направление | Результат |
|---|---|---|
| 1.4.x | Network Provisioning | DHCP + PXE + авторизованное первоначальное развёртывание ПК |
| 1.5.x | Operations | Monitoring + Backup + DR + Automation + Diagnostics |
| 1.6.x | Infrastructure | Storage + RAID/ZFS + Containers + VM + Network/Security + Ansible foundation |
| 1.7.x | Endpoint Management | Domain/PXE clients + Software/Config Profiles + GPO + Ansible + Client Agent + Compliance |
| 1.8.x | High Availability | Multi-SRV + cluster + failover/distributed infrastructure |

## Управление изменениями roadmap

При новой идее или изменении scope:

1. определить целевой release;
2. обновить этот roadmap;
3. при необходимости создать `docs/RELEASE-<version>-SCOPE.md`;
4. определить migration/RBAC/security/acceptance impact;
5. только после этого начинать implementation branch.

Таким образом GitHub остаётся единственным долговременным источником согласованного product roadmap.