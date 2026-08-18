# Безопасность Control Center 1.0.9

## Разделение привилегий

Web-процесс работает от системной УЗ `control-center` без root-доступа. Привилегированные изменения выполняются отдельными systemd workers: сеть, Market/DHCP, лицензирование, обновления и Web runtime.

Web UI создаёт pending requests в Web-writable state, а root helpers повторно валидируют критичные параметры перед применением.

## State

```text
/var/lib/control-center          # Web-writable settings + pending requests
/var/lib/control-center-system   # root:control-center applied state/status/modules
/var/lib/control-center-root     # root:root 0700 rollback
/var/lib/control-center-license  # root:control-center validated license
PostgreSQL control_center        # application data/history/management state
```

PostgreSQL не заменяет protected root state и фактические Linux-конфигурации.

## PostgreSQL

Локальная модель:

```text
database: control_center
role: control-center
transport: Unix socket /var/run/postgresql
auth: peer
```

Роль: `NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION`. Пароль БД в приложении не хранится. Control Center не открывает внешний PostgreSQL listener автоматически.

## Standard ports без root Web-process

Для HTTP/HTTPS стандартных портов `80/443` Web service получает только capability:

```text
AmbientCapabilities=CAP_NET_BIND_SERVICE
CapabilityBoundingSet=CAP_NET_BIND_SERVICE
```

`User=control-center` и `NoNewPrivileges=true` сохраняются. Полные root-права Gunicorn не получает.

## HTTPS 1.0.9

При первом включении SSL root helper создаёт локальную пару:

```text
/etc/control-center/tls/server.crt
/etc/control-center/tls/server.key
```

Private key имеет `root:control-center 0640`. Certificate содержит hostname/localhost/IP SAN и используется Gunicorn только для TLS termination Web UI.

Self-signed сертификат **шифрует соединение, но не подтверждает доверие браузера автоматически**. Предупреждение браузера ожидаемо, пока сертификат не добавлен в доверенные либо не внедрён ACME/пользовательский сертификат.

HTTPS **не заменяет authentication/authorization**.

## Web runtime apply/rollback

Root helper проверяет порт, при необходимости создаёт TLS material, обновляет root-owned env/protected config/PostgreSQL settings, перезапускает Web service и выполняет HTTP/HTTPS localhost health-check. При ошибке возвращается предыдущий runtime.

Control Center не меняет внешний firewall, NAT или ACL автоматически.

## Samba AD-DC preparation

Migration `002` создаёт только operational schema/preflight history. Plaintext Administrator/domain secrets туда не записываются.

1.0.9 не выполняет `samba-tool domain provision`, DNS cutover или изменение realm. Это намеренно оставлено отдельному релизу с backup/rollback и secret-handling design.

Preflight проверяет prerequisites, но `ready=true` **не означает**, что домен уже создан или безопасно готов к production provisioning.

## Database migrations

`schema_migrations` хранит SHA-256 checksum каждого migration. Изменение уже применённого SQL под тем же номером приводит к checksum mismatch.

## Audit и уведомления

State-changing `/api/*` запросы записываются в PostgreSQL audit. Read/unread уведомлений также server-side. До появления встроенной Web-аутентификации это не полноценный user-attribution audit trail.

## Production Web runtime

Gunicorn через `wsgi:app` с CSP `script-src 'self'`, nosniff, frame denial, Referrer/Permissions/COOP headers, no-store для API/HTML, same-origin guard и 64 KiB request limit.

## Systemd hardening

```text
User=control-center
Group=control-center
AmbientCapabilities=CAP_NET_BIND_SERVICE
CapabilityBoundingSet=CAP_NET_BIND_SERVICE
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
InaccessiblePaths=/var/lib/control-center-root
```

## Известное ограничение

Встроенная Web-аутентификация пока отсутствует. Даже при HTTPS административный интерфейс должен быть доступен только из доверенной LAN/VPN/firewall либо через reverse proxy с аутентификацией.

## Проверка

```bash
sudo bash scripts/acceptance-1.0.9.sh
systemctl cat control-center
sudo -u control-center psql -d control_center -c 'select current_user,current_database();'
sudo cat /etc/control-center/web.env
```
