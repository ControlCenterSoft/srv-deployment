# Безопасность Control Center 1.0.5

## Разделение привилегий

Основной Web-процесс работает от системной УЗ `control-center` без root-доступа. Привилегированные действия выполняются отдельными systemd workers:

- применение сети;
- установка/удаление DHCP;
- применение DHCP-конфигурации;
- проверка Professional-лицензии;
- обновление Control Center;
- обновление ОС и пакетов.

Web UI формирует JSON-запросы в `/var/lib/control-center`, но **root helpers не считают эти файлы доверенными**. Сетевой и DHCP helpers повторно проверяют интерфейсы, типы значений, IPv4, маски, шлюзы, DNS, диапазоны и другие ограничения уже непосредственно перед привилегированным применением. Это защищает от обхода Web/API-валидации при компрометации Web-процесса.

## Разделение state

```text
/var/lib/control-center
```

Web-writable состояние: настройки UI, pending requests и публичные статусы.

```text
/var/lib/control-center-root
```

Root-only (`0700`) состояние: rollback-копии приложения, Netplan и DHCP. Web service получает `InaccessiblePaths=/var/lib/control-center-root`.

```text
/var/lib/control-center-license
```

Root-owned каталог подтверждённой Professional-лицензии. Web service получает только чтение.

Таким образом, Web-процесс не может подменить rollback-копию приложения или подтверждённую лицензию.

## Лицензирование

Professional-лицензия проверяется RSA/SHA-256. Root helper проверяет подпись, `edition`, `device_id`, `license_id` и срок действия перед записью `/var/lib/control-center-license/license.json`.

Приватный ключ издателя никогда не должен храниться в GitHub или на сервере клиента.

## Systemd hardening

`control-center.service` использует, в частности:

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
ReadOnlyPaths=/var/lib/control-center-license
InaccessiblePaths=/var/lib/control-center-root
```

## APT/dpkg

Установщик, OS/package updater и Маркет используют общий `/run/control-center-apt.lock`, чтобы внутренние пакетные операции Control Center не выполнялись одновременно.

## Известное ограничение 1.0.5

В текущей линии ещё **нет полноценной аутентификации Web UI**. Поэтому TCP/8080 нельзя публиковать напрямую в Интернет или недоверенную сеть. До появления встроенной аутентификации доступ должен ограничиваться доверенной административной LAN/VPN и внешним firewall/reverse proxy с аутентификацией.

Особенно важно ограничить доступ, потому что Web UI может создавать запросы на изменение сети, установку DHCP и обновление системных пакетов.

## Рекомендации

- разрешать TCP/8080 только с административных адресов;
- не публиковать порт через WAN/NAT;
- использовать VPN для удалённого администрирования;
- регулярно проверять `journalctl` для привилегированных workers;
- хранить приватный ключ Professional offline и в зашифрованном хранилище;
- делать резервную копию сетевой конфигурации до удалённых изменений;
- не изменять вручную root-only state.

## Проверка прав

```bash
id control-center
systemctl cat control-center
ls -ld /var/lib/control-center /var/lib/control-center-root /var/lib/control-center-license
ls -l /var/lib/control-center-license 2>/dev/null || true
```
