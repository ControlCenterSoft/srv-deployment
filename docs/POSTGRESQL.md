# PostgreSQL в Control Center 1.0.11

PostgreSQL — application data layer Control Center. Локальное приложение подключается через Unix socket/peer authentication:

```text
dbname=control_center user=control-center host=/var/run/postgresql
```

Пароль PostgreSQL для локальной роли приложению не требуется.

## Versioned migrations

Migrations находятся в:

```text
/opt/control-center/app/migrations
```

История:

- `001` — базовая application schema;
- `002` — Samba AD-DC preparation profiles/nodes/preflight;
- `003` — readiness runs и dry-run change plans;
- `004` — production Samba AD-DC lifecycle jobs и health runs.

Контрольная таблица:

```text
control_center.schema_migrations
```

Checksum уже применённой migration не может изменяться. Installer включает `control-center-db-migrate.service` с retry при временно недоступной PostgreSQL.

## Samba AD-DC 1.0.11

Основные таблицы:

```text
control_center.ad_dc_profiles
control_center.ad_dc_nodes
control_center.ad_dc_preflight_runs
control_center.ad_dc_readiness_runs
control_center.ad_dc_change_plans
control_center.ad_dc_lifecycle_jobs
control_center.ad_dc_health_runs
```

`ad_dc_profiles` в migration 004 получает interface/IP/DNS-forwarder, managed/provisioned и health fields.

`ad_dc_lifecycle_jobs` хранит:

- job ID;
- action/state;
- публичный request;
- result;
- backup path;
- error/timestamps.

`ad_dc_health_runs` хранит результаты post-provision health checks.

## Secret boundary

В PostgreSQL **не сохраняются**:

- Domain Administrator password;
- одноразовый Samba approval code;
- temporary smbclient credentials;
- private license signing keys.

Provision request для DB формируется отдельно от secret request и содержит только Realm/NetBIOS/interface/IP/network/forwarder и safety flags.

## Web runtime independence

Начиная с 1.0.10 фактический Web port/SSL runtime не зависит от текущей доступности PostgreSQL. После восстановления БД Web settings reconciled автоматически.

## Проверка

```bash
sudo -u control-center psql -d control_center -Atqc \
  "select version,name,applied_at from control_center.schema_migrations order by version"

sudo -u control-center psql -d control_center -c \
  'select job_id,action,state,backup_path,error,created_at,finished_at from control_center.ad_dc_lifecycle_jobs order by created_at desc limit 20;'

sudo -u control-center psql -d control_center -c \
  'select profile_id,healthy,created_at from control_center.ad_dc_health_runs order by id desc limit 20;'
```
