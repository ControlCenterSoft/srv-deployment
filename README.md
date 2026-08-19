# Control Center 1.0.10

Control Center — web-панель управления Linux-сервером. Текущий Production release: **1.0.10**, build **20260819.4**, audit `passed`.

## Главное в 1.0.10

- Samba AD-DC: расширенный readiness, migration `003` и воспроизводимый dry-run change plan;
- реальный provisioning Samba намеренно отключён до **1.0.11**;
- переименование компьютера из Настроек через отдельный root-helper с backup/rollback;
- исправлена смена Web-порта и SSL при недоступной PostgreSQL;
- стандартный HTTP → `80`, стандартный HTTPS → `443`, custom → `1024–65535`;
- фактический Web runtime хранится независимо от PostgreSQL и автоматически синхронизируется в БД после её восстановления;
- operational alerts консолидированы в центр уведомлений;
- WAN и LAN можно выключать по отдельности;
- поддерживаются WAN+LAN, только WAN и только LAN;
- dashboard показывает только графики активных сетевых ролей.

## Web runtime

Control Center работает от системной УЗ `control-center`. Для портов 80/443 systemd выдаёт только:

```text
CAP_NET_BIND_SERVICE
```

При включении HTTPS используются:

```text
/etc/control-center/tls/server.crt
/etc/control-center/tls/server.key
```

Self-signed certificate может вызвать предупреждение браузера. Изменение Web runtime проходит через privileged helper с проверкой порта, restart, HTTP/HTTPS health-check и rollback.

В 1.0.10 PostgreSQL больше не является обязательным условием применения порта/SSL. Если БД временно недоступна, Web runtime всё равно применяется, а факт degraded-состояния попадает в колокольчик. После восстановления БД настройки reconciled автоматически.

## Сети

В WAN и LAN доступен пункт **«Выключен»**. Допустимы:

```text
WAN + LAN
только WAN
только LAN
```

Обе роли одновременно выключить нельзя. При включённом WAN LAN не создаёт второй default route; в LAN-only режиме LAN может использовать gateway/default route.

## Samba AD-DC

Migration `003` добавляет readiness history и change plans. Проверяются hostname/FQDN, статический IPv4, NTP, обязательные APT-пакеты, свободное место, порты 53/88/389/445 и существующая Samba-конфигурация.

API:

```text
GET/POST /api/samba/readiness
GET/POST /api/samba/plan
```

1.0.10 **не выполняет** `samba-tool domain provision`. Production provisioning, DNS/Kerberos cutover, backup/rollback и acceptance будут включены только в следующем релизе после проверки подготовленного плана.

## Установка

```bash
git clone --depth 1 --branch release/1.0.10 https://github.com/filosoff31/srv-deployment.git
cd srv-deployment
sudo bash install/install.sh
```

Для чистой установки Web UI стартует на:

```text
http://SERVER_IP:8080
```

## Acceptance

```bash
sudo bash scripts/acceptance-1.0.10.sh
```

Ожидаемо:

```text
VERSION 1.0.10
BUILD   20260819.4
PostgreSQL migration 003
ACCEPTANCE 1.0.10: PASSED
```

## Наследование

Сохраняются пагинация 1.0.9, CPU/RAM Top, storage visualization, TLS, persistent Market statuses, DHCP lifecycle/recovery, PostgreSQL notifications, Update Center, Home/Professional, protected state и version/build-aware updater.

## Безопасность

Встроенная Web-аутентификация административной панели пока не реализована. Даже при HTTPS Web UI необходимо ограничивать доверенной LAN/VPN/firewall и не публиковать напрямую в Интернет.
