# Безопасность Control Center 1.0.5

## Разделение привилегий

Основной Web-процесс работает от системной УЗ `control-center` без root-доступа. Привилегированные действия выполняются отдельными systemd workers: сеть, Market/DHCP, лицензирование, обновление Control Center и обновление ОС/пакетов.

Web UI создаёт запросы в Web-writable state, но root helpers **не считают их доверенными**. Network и DHCP helpers независимо повторно проверяют интерфейсы, типы значений, IPv4, маски, шлюзы, DNS, диапазоны и ограничения непосредственно перед применением.

## Четыре уровня state

```text
/var/lib/control-center
```
Web-writable: настройки и pending requests.

```text
/var/lib/control-center-system
```
`root:control-center 0750`: применённые конфигурации, статусы и ownership модулей. Web-процесс имеет только чтение.

```text
/var/lib/control-center-root
```
`root:root 0700`: rollback-копии приложения, Netplan и DHCP. Web service получает `InaccessiblePaths=/var/lib/control-center-root`.

```text
/var/lib/control-center-license
```
`root:control-center 0750`, файл лицензии `0640`: подтверждённая Professional-лицензия. Web service может читать, но не изменять её.

Compatibility symlinks внутри `/var/lib/control-center` используются только для чтения текущим Web API. Root helpers всегда обращаются к защищённым оригиналам и не доверяют этим ссылкам.

## Production Web runtime

Web UI запускается Gunicorn через `wsgi:app`, а не Flask development server. Production entrypoint добавляет:

- `Content-Security-Policy`;
- `X-Content-Type-Options: nosniff`;
- `X-Frame-Options: DENY`;
- `Referrer-Policy`;
- `Permissions-Policy`;
- `Cross-Origin-Opener-Policy`;
- `Cache-Control: no-store` для HTML/API;
- same-origin проверку браузерных POST/PUT/PATCH/DELETE запросов;
- лимит request body 64 KiB;
- уникальные атомарные temp-файлы для JSON writes при нескольких Gunicorn workers.

Динамические строки, вставляемые JavaScript через `innerHTML`, экранируются перед отображением.

Текущий CSP временно содержит `script-src 'unsafe-inline'`, поскольку JavaScript 1.0.5 ещё находится в шаблоне HTML. В следующей архитектурной итерации рекомендуется вынести script в отдельный static-файл и убрать `unsafe-inline`.

## Лицензирование

Professional-лицензия проверяется RSA/SHA-256. Root helper проверяет подпись, `edition`, `device_id`, `license_id` и срок действия. Приватный ключ издателя никогда не должен храниться в GitHub или на клиентском сервере.

## DHCP ownership

Control Center не захватывает `dnsmasq`, уже установленный вне продукта. Управляемый DHCP работает отдельным `control-center-dhcp-server.service`; дистрибутивный `dnsmasq.service` не используется как runtime модуля. Ownership пакета хранится только в защищённом system-state.

## APT/dpkg

Установщик, OS/package updater и Маркет используют общий `/run/control-center-apt.lock`, чтобы внутренние пакетные операции не выполнялись одновременно.

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
ReadOnlyPaths=/var/lib/control-center-system /var/lib/control-center-license
InaccessiblePaths=/var/lib/control-center-root
```

## Известное ограничение 1.0.5

В 1.0.5 ещё **нет полноценной встроенной аутентификации Web UI**. Поэтому TCP/8080 нельзя публиковать напрямую в Интернет или недоверенную сеть. Same-origin/CSP уменьшают браузерные риски, но не являются заменой authentication/authorization.

До внедрения аутентификации доступ должен ограничиваться доверенной административной LAN/VPN и firewall/reverse proxy с аутентификацией.

## Рекомендации

- разрешать TCP/8080 только с административных адресов;
- не публиковать порт через WAN/NAT;
- использовать VPN для удалённого администрирования;
- хранить приватный ключ Professional offline и в зашифрованном хранилище;
- регулярно проверять журналы привилегированных workers;
- выполнять `scripts/acceptance-1.0.5.sh` после установки/обновления.

## Проверка прав

```bash
id control-center
systemctl cat control-center
ls -ld /var/lib/control-center /var/lib/control-center-system /var/lib/control-center-root /var/lib/control-center-license
find /var/lib/control-center-system -maxdepth 2 -ls
ls -l /var/lib/control-center-license 2>/dev/null || true
```
