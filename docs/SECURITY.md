# Безопасность Control Center 1.0.6

## Разделение привилегий

Web-процесс работает от системной УЗ `control-center` без root-доступа. Привилегированные действия выполняются отдельными systemd workers: сеть, Market/DHCP, лицензирование, обновление Control Center и обновление ОС/пакетов.

Web UI создаёт pending requests в Web-writable state, но root helpers не доверяют им и повторно валидируют критичные параметры перед применением.

## State

```text
/var/lib/control-center          # Web-writable settings + pending requests
/var/lib/control-center-system   # root:control-center applied state/status/modules
/var/lib/control-center-root     # root:root 0700 rollback
/var/lib/control-center-license  # root:control-center validated license
```

## Read-only live configuration

Для выполнения требования 1.0.6 «показывать уже настроенные параметры» Web service получает только чтение Control Center-managed конфигураций:

```text
/etc/netplan/90-control-center.yaml
/etc/dnsmasq.d/control-center-dhcp.conf
```

Netplan-файл хранится как `root:control-center 0640`. Изменение этих файлов по-прежнему возможно только через root helpers.

## Production Web runtime

Web UI запускается Gunicorn через `wsgi:app`. WSGI layer включает:

- `Content-Security-Policy`;
- `X-Content-Type-Options: nosniff`;
- `X-Frame-Options: DENY`;
- `Referrer-Policy`;
- `Permissions-Policy`;
- `Cross-Origin-Opener-Policy`;
- `Cache-Control: no-store` для HTML/API;
- same-origin проверку browser write requests;
- лимит request body 64 KiB;
- атомарные JSON writes для нескольких Gunicorn workers.

В 1.0.6 JavaScript вынесен в `/static/app.js`. CSP теперь использует:

```text
script-src 'self'
```

и больше не требует `unsafe-inline`.

## XSS

Все системные/пользовательские строки, которые вставляются в динамический HTML, проходят HTML escaping в `app.js`.

## DHCP additional options

Дополнительные DHCP options проходят двойную проверку Web API + root helper. Ограничены numeric codes `1..254`, максимум 32 записей; запрещены управляющие символы и дублирование. Options `1`, `3`, `6`, `51` управляются основными полями и не могут быть добавлены повторно.

## Уведомления

`/api/notifications` только агрегирует protected status files и фактический DHCP service state. Read/unread хранится в localStorage браузера и не влияет на server-side состояние.

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

## Известное ограничение 1.0.6

Встроенная Web-аутентификация пока отсутствует. Same-origin/CSP/systemd hardening не заменяют authentication/authorization. TCP/8080 нельзя публиковать напрямую в Интернет или недоверенную сеть.

Рекомендуется разрешать доступ только из административной LAN/VPN/firewall или через reverse proxy с аутентификацией.

## Проверка

```bash
sudo bash scripts/acceptance-1.0.6.sh
systemctl cat control-center
ls -l /etc/netplan/90-control-center.yaml 2>/dev/null || true
ls -ld /var/lib/control-center /var/lib/control-center-system /var/lib/control-center-root /var/lib/control-center-license
```
