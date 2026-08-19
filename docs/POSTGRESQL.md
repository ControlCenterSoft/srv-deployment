# PostgreSQL — Control Center 1.0.11

Control Center использует локальную PostgreSQL `control_center` через Unix socket/peer authentication:

```text
dbname=control_center user=control-center host=/var/run/postgresql
```

## Migrations

```text
001  base application schema
002  Samba AD-DC preparation
003  AD readiness/change plans
004  AD production lifecycle/health
005  RBAC bootstrap + service dependencies + DHCP reservations + cleanup audits
```

Последняя migration 1.0.11: **005**.

## Domain lifecycle

```text
control_center.ad_dc_profiles
control_center.ad_dc_nodes
control_center.ad_dc_preflight_runs
control_center.ad_dc_readiness_runs
control_center.ad_dc_change_plans
control_center.ad_dc_lifecycle_jobs
control_center.ad_dc_health_runs
```

Administrator password и one-time approval code в эти таблицы не записываются.

## RBAC-ready schema

Migration 005 создаёт:

```text
control_center.rbac_roles
control_center.rbac_bindings
```

Seed roles:

```text
admin
viewer
```

Текущий portal authorization использует bootstrap mapping, но schema позволяет последующим релизам перенести mapping Local/Domain principals в PostgreSQL без изменения способа аутентификации.

## Service dependencies

```text
control_center.service_dependencies
```

Обязательные связи:

```text
domain -> dns
domain -> storage
```

## DHCP reservations

```text
control_center.dhcp_reservations
```

Сохраняются MAC, IPv4, hostname, enabled и metadata. Root worker остаётся фактическим источником применённой dnsmasq-конфигурации; DB синхронизируется после успешного apply.

## Cleanup audit history

```text
control_center.service_cleanup_audits
```

Хранятся service/action, clean flag, checks и recovery path. Root JSON audit остаётся доступен даже при временно недоступной PostgreSQL.

## Secret boundary

Не сохраняются:

- Local/Domain passwords;
- Domain Administrator password;
- provisioning/removal approval codes;
- temporary smbclient credentials;
- session secret;
- vendor private signing key.

Session secret хранится отдельно в `/etc/control-center/auth.env`, а provisioning secrets — только в `/run`.

## Проверка

```bash
sudo -u control-center psql -d control_center -Atqc \
  "select version,name,applied_at from control_center.schema_migrations order by version"

sudo -u control-center psql -d control_center -c \
  'select * from control_center.service_dependencies order by service_id,depends_on;'

sudo -u control-center psql -d control_center -c \
  'select auth_source,principal,role_id,enabled from control_center.rbac_bindings order by id;'

sudo -u control-center psql -d control_center -c \
  'select mac,ipv4,hostname,enabled from control_center.dhcp_reservations order by ipv4;'

sudo -u control-center psql -d control_center -c \
  'select service_id,action,clean,created_at,recovery_path from control_center.service_cleanup_audits order by id desc limit 30;'
```
