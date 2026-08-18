# Безопасность Control Center 1.0.7

## Разделение привилегий

Web-процесс работает от системной УЗ `control-center` без root-доступа. Привилегированные изменения выполняются отдельными systemd workers: сеть, Market/DHCP, лицензирование, обновления и новая смена Web-порта.

Web UI создаёт pending requests в Web-writable state, но root helpers повторно валидируют критичные параметры перед применением.

## State

```text
/var/lib/control-center          # Web-writable compatibility settings + pending requests
/var/lib/control-center-system   # root:control-center applied state/status/modules
/var/lib/control-center-root     # root:root 0700 rollback
/var/lib/control-center-license  # root:control-center validated license
PostgreSQL control_center        # application data, history and management state
```

PostgreSQL не заменяет protected root state и системные конфигурационные файлы.

## PostgreSQL

Локальная модель 1.0.7:

```text
database: control_center
role: control-center
transport: Unix socket /var/run/postgresql
auth: peer
```

PostgreSQL роль создаётся как `NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION`. Пароль БД в Web-приложении не хранится. Control Center 1.0.7 не меняет `listen_addresses`, не открывает PostgreSQL TCP listener и не создаёт firewall rule для внешней БД.

`/etc/control-center/database.env` хранится `root:root 0600` и содержит локальный DSN, а не пароль.

Future Professional Cluster потребует отдельного security design: enrollment, TLS, cluster identity, replication credentials, authorization, quorum/failover и backup policy. Наличие таблицы `cluster_nodes` не означает готового сетевого кластера.

## Database migrations

`schema_migrations` хранит SHA-256 checksum каждого применённого migration. Уже применённый migration нельзя тихо заменить новым SQL под тем же номером: runner завершится ошибкой checksum mismatch.

## Audit

State-changing `/api/*` запросы записываются в `control_center.audit_events`: endpoint/action, HTTP status, remote address и технические details. До появления встроенной Web-аутентификации это не является полноценным user-attribution audit trail.

## Уведомления

Read/unread в 1.0.7 хранится server-side в `control_center.notification_events`, а не localStorage браузера. Это делает состояние единым для разных браузеров, но до пользовательской аутентификации read-state общий для всей установки Control Center.

## Read-only live configuration

Web service имеет только чтение:

```text
/etc/netplan/90-control-center.yaml
/etc/dnsmasq.d/control-center-dhcp.conf
```

Изменение выполняют root helpers.

## Web-порт

Настраиваемый порт `1024–65535` не применяется непосредственно Web-процессом. Root helper:

- повторно проверяет порт;
- проверяет bind;
- обновляет root-owned `/etc/control-center/web.env`;
- синхронизирует PostgreSQL setting;
- перезапускает Gunicorn;
- выполняет localhost health-check;
- возвращает старый порт при ошибке.

Смена порта не включает HTTPS, authentication или firewall rules.

## Production Web runtime

Gunicorn через `wsgi:app` с CSP `script-src 'self'`, nosniff, frame denial, Referrer/Permissions/COOP headers, no-store для API/HTML, same-origin guard и 64 KiB request limit.

## Systemd hardening Web UI

```text
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ProtectHome=true
ProtectKernelTunables=true
ProtectKernelModules=true
ProtectControlGroups=true
RestrictSUIDSGID=true
LockPersonality=true
ReadWritePaths=/var/lib/control-center
ReadOnlyPaths=/var/lib/control-center-system /var/lib/control-center-license /etc/netplan/90-control-center.yaml /etc/dnsmasq.d/control-center-dhcp.conf
InaccessiblePaths=/var/lib/control-center-root
```

## Известное ограничение

В 1.0.7 встроенная Web-аутентификация всё ещё отсутствует. PostgreSQL-backed audit и server-side notifications не заменяют authentication/authorization.

Административный Web-порт — 8080 или пользовательский — должен быть доступен только из доверенной LAN/VPN/firewall либо через защищённый reverse proxy.

## Проверка

```bash
sudo bash scripts/acceptance-1.0.7.sh
systemctl cat control-center
sudo -u control-center psql -d control_center -c 'select current_user,current_database();'
ss -ltnp | grep postgres
```

При стандартной конфигурации Control Center не должен создавать внешний PostgreSQL listener специально для продукта.
