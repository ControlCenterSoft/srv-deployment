# PostgreSQL в Control Center 1.0.7

## Назначение

Начиная с 1.0.7 PostgreSQL является базовым **application data layer** Control Center. База хранит данные приложения, историю и состояние управления, но не заменяет фактические системные конфигурации Linux.

```text
PostgreSQL -> settings, notifications, audit, jobs, modules, service configs, cluster nodes
Netplan    -> фактическая конфигурация сети
systemd    -> фактическое состояние сервисов
Dnsmasq    -> фактическая DHCP-конфигурация
/proc,/sys -> live telemetry
```

## Локальная конфигурация

```text
database: control_center
schema:   control_center
role:     control-center
socket:   /var/run/postgresql
DSN:      dbname=control_center user=control-center host=/var/run/postgresql
```

Установщик создаёт непривилегированную PostgreSQL-роль `control-center`: без SUPERUSER, CREATEDB, CREATEROLE и REPLICATION. Web service работает от одноимённой Linux УЗ и подключается по локальному Unix socket через peer authentication. Пароль БД в приложении не хранится.

Control Center 1.0.7 не изменяет PostgreSQL `listen_addresses` для внешней сети и не включает удалённый доступ к БД автоматически.

## Схема

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

### settings

Application settings. В 1.0.7 сюда перенесены настройки обновлений и Web-порт. Для совместимости некоторые значения зеркалируются в старые JSON-файлы, которые продолжают читать существующие root workers.

### notification_events

История событий общего колокольчика и серверный `is_read`. Read/unread больше не зависит от localStorage конкретного браузера.

### audit_events

Журнал state-changing API действий: endpoint, HTTP status, remote address и технические детали запроса. Полноценная user identity появится после встроенной аутентификации.

### jobs

Модель фоновых/привилегированных заданий. В 1.0.7 её использует смена Web-порта; схема предназначена и для будущих сервисных задач.

### module_inventory / service_configs

Application-level представление установленных модулей и конфигураций. Источником истины для фактического сервиса остаётся ОС.

### cluster_nodes

Архитектурный задел Professional Cluster. В 1.0.7 регистрируется только локальный standalone node. Наличие таблицы **не означает**, что межузловая репликация, quorum, HA или cluster management уже реализованы.

## Миграции

SQL migrations находятся в:

```text
/opt/control-center/app/migrations
```

Runner:

```text
/opt/control-center/app/db_migrate.py
```

Таблица `schema_migrations` хранит version/name/SHA-256 checksum. Изменение уже применённого migration-файла считается ошибкой; новая схема должна добавляться новой migration.

Проверка:

```bash
sudo -u control-center env CONTROL_CENTER_DB_DSN='dbname=control_center user=control-center host=/var/run/postgresql' \
  /opt/control-center/venv/bin/python /opt/control-center/app/db_cli.py status

sudo -u control-center psql -d control_center -c '\dt control_center.*'
sudo -u control-center psql -d control_center -c 'select * from control_center.schema_migrations order by version;'
```

## Backup

Минимальная резервная копия application data:

```bash
sudo -u control-center pg_dump -Fc control_center > control-center-db.dump
```

Восстановление следует выполнять только на остановленном Control Center и в рамках соответствующей версии схемы.

PostgreSQL backup **не заменяет** резервную копию Netplan, dnsmasq, лицензии и других системных файлов.

## Подготовка к Professional Cluster

1.0.7 специально не открывает PostgreSQL в сеть. Будущий кластер должен добавить отдельный безопасный механизм:

- Professional entitlement;
- cluster enrollment/identity;
- TLS;
- отдельные DB credentials/certificates или иной доверенный transport;
- topology/quorum/leader model;
- replication/failover policy;
- backup/restore и split-brain protections.

`CONTROL_CENTER_DB_DSN` уже является заменяемым параметром runtime, но ручное направление текущей 1.0.7 на удалённую БД не считается поддерживаемым кластерным режимом.

## Диагностика

```bash
systemctl status postgresql --no-pager
sudo -u control-center psql -d control_center -c 'select current_database(), current_user, version();'
curl -fsS http://127.0.0.1:PORT/api/database/status | python3 -m json.tool
journalctl -u postgresql -n 100 --no-pager
journalctl -u control-center -n 100 --no-pager
```
