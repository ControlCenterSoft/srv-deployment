# Control Center 1.0.7

Control Center — web-панель управления Linux-сервером. Текущая release-ветка: **1.0.7**, build **20260818.2**.

## Редакции

- **Home** — редакция по умолчанию, без активации.
- **Professional** — активируемая подписанной лицензией; архитектура 1.0.7 подготовлена к будущей кластерной редакции Professional.

## Что нового в 1.0.7

- **PostgreSQL** стал базовым application data layer Control Center;
- автоматическая установка локального PostgreSQL, БД `control_center` и роли `control-center`;
- локальное соединение через Unix socket и peer authentication, без пароля БД в приложении;
- versioned SQL migrations с checksum-контролем;
- PostgreSQL tables для settings, notifications/read state, audit, jobs, module inventory, service configs и будущих cluster nodes;
- центр уведомлений хранит read/unread на сервере, а не в browser localStorage;
- настройки обновления Control Center и ОС сохраняются в PostgreSQL, с compatibility mirror для существующих root workers;
- API и карточка состояния PostgreSQL;
- **Настройки → Web-панель**: изменение TCP-порта Control Center от 1024 до 65535;
- root-helper смены порта: проверка, restart Gunicorn, health-check и rollback;
- выбранный Web-порт сохраняется при обновлениях;
- updater стал version/build-aware.

Все функции 1.0.6 сохранены: dashboard, полный перечень интерфейсов, WAN/LAN, DHCP с дополнительными options/status/config check, Market, RBAC, notification bell, мобильная верстка и Home/Professional.

## Роль PostgreSQL

PostgreSQL хранит **данные приложения и управления**, но не подменяет фактическое состояние Linux:

```text
PostgreSQL                    -> settings, notifications, audit, jobs, modules, service configs, cluster nodes
Netplan                       -> фактическая конфигурация сети
systemd                       -> фактическое состояние служб
/etc/dnsmasq.d/...            -> фактическая DHCP-конфигурация
/proc, /sys, ip, resolvectl   -> live telemetry
```

Локальная БД:

```text
database: control_center
schema:   control_center
role:     control-center
socket:   /var/run/postgresql
```

Control Center 1.0.7 **не включает PostgreSQL TCP listener для внешней сети** и не реализует межузловую репликацию. Таблица `cluster_nodes` и заменяемый `CONTROL_CENTER_DB_DSN` — задел для следующего этапа Professional Cluster, а не заявление о готовом кластере.

## Схема PostgreSQL

```text
control_center.schema_migrations
control_center.settings
control_center.notification_events
control_center.audit_events
control_center.jobs
control_center.module_inventory
control_center.service_configs
control_center.cluster_nodes
```

## Web-порт

По умолчанию Web UI работает на `8080`. В **Настройки → Web-панель** можно задать порт `1024–65535`.

Применение выполняется через:

```text
/api/settings/web
/var/lib/control-center/web-pending.json
control-center-web-apply.path
control-center-web-apply.service
/usr/local/sbin/control-center-web-apply
/etc/control-center/web.env
```

Helper проверяет доступность порта, перезапускает Gunicorn, делает health-check нового адреса и возвращает предыдущий порт при неудаче.

## Установка

```bash
git clone --depth 1 --branch release/1.0.7 https://github.com/filosoff31/srv-deployment.git
cd srv-deployment
sudo bash install/install.sh
```

Установщик сам установит PostgreSQL, создаст приложение/БД, применит SQL migrations и сохранит текущий Web-порт при обновлении существующей установки.

## Acceptance

```bash
sudo bash scripts/acceptance-1.0.7.sh
```

Проверяются PostgreSQL, peer connection, schema migration, API database status, версия/build, Web-port configuration, systemd helpers и существующие network/DHCP компоненты.

## Документация

- `docs/README.md` — индекс;
- `docs/POSTGRESQL.md` — архитектура PostgreSQL и подготовка к кластеру;
- `docs/WEB-PORT.md` — безопасная смена порта Web UI;
- `docs/INSTALL.md` — установка/обновление/удаление;
- `docs/UPDATE.md` — updater;
- `docs/NETWORK.md` — WAN/LAN;
- `docs/DHCP.md` — DHCP;
- `docs/NOTIFICATIONS.md` — уведомления;
- `docs/SECURITY.md` — trust boundaries;
- `docs/TROUBLESHOOTING.md` — диагностика;
- `releases/1.0.7/README.md` — release notes.

## Важное ограничение безопасности

Встроенная Web-аутентификация ещё не реализована. Независимо от выбранного Web-порта административную панель необходимо ограничивать доверенной LAN/VPN/firewall и не публиковать напрямую в Интернет.
