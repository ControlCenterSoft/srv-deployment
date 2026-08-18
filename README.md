# Control Center 1.0.9

Control Center — web-панель управления Linux-сервером. Текущая release-ветка: **1.0.9**, build **20260819.3**.

## Главное в 1.0.9

- единая пагинация для длинных перечней и таблиц;
- CPU dashboard: live chart + отдельный Top CPU;
- RAM dashboard: live chart + отдельный Top RAM;
- хранилище: круговая диаграмма заполнения + mount usage;
- LAN RX/TX вместо WAN-карточки на обзоре;
- в Web-настройках: **Стандартный порт** и **SSL / HTTPS**;
- standard HTTP → `80`, standard HTTPS → `443`, custom → `1024–65535`;
- self-signed TLS certificate с health-check/rollback;
- PostgreSQL migration `002` под будущий Samba AD-DC;
- `/api/samba/preflight` и UI проверки FQDN/LAN/time/DNS prerequisites;
- Samba AD-DC отображается в Маркете как **Подготовлено**, но provisioning пока отключён.

## Пагинация

Pager автоматически появляется только когда список не помещается на одну страницу. Он используется для сетевых интерфейсов, DHCP options, RBAC users/groups, уведомлений и Маркета.

## Web-порт и HTTPS

Control Center по-прежнему работает от системной УЗ `control-center`. Для bind на 80/443 systemd выдаёт только `CAP_NET_BIND_SERVICE`.

При первом включении HTTPS создаются:

```text
/etc/control-center/tls/server.crt
/etc/control-center/tls/server.key
```

Сертификат self-signed, поэтому браузер может показать предупреждение доверия. ACME/Let's Encrypt и пользовательские certificates будут отдельным этапом.

Изменение Web runtime проходит через root helper с проверкой порта, restart, HTTP/HTTPS health-check и rollback.

## PostgreSQL и Samba AD-DC preparation

PostgreSQL остаётся application data layer. Migration `002` создаёт `ad_dc_profiles`, `ad_dc_nodes`, `ad_dc_preflight_runs`. Пароли домена/Administrator не сохраняются в этих таблицах.

1.0.9 не выполняет `samba-tool domain provision` и не меняет DNS/realm автоматически. Это будет отдельный релиз после preflight/backup/rollback архитектуры.

## Установка

```bash
git clone --depth 1 --branch release/1.0.9 https://github.com/filosoff31/srv-deployment.git
cd srv-deployment
sudo bash install/install.sh
```

По умолчанию Web UI остаётся:

```text
http://SERVER_IP:8080
```

Далее в **Настройки → Web-панель** можно выбрать standard port и HTTPS.

## Acceptance

```bash
sudo bash scripts/acceptance-1.0.9.sh
```

Ожидаемо:

```text
VERSION 1.0.9
BUILD   20260819.3
PostgreSQL migration 002
```

## Наследование 1.0.8

Сохраняются persistent Market statuses, исправленный DHCP lifecycle, PostgreSQL notifications, update-install button, recovery старого 1.0.6/dpkg состояния, Home/Professional, protected state и version/build-aware updater.

## Безопасность

Встроенная Web-аутентификация административной панели пока не реализована. Даже при HTTPS Web UI необходимо ограничивать доверенной LAN/VPN/firewall и не публиковать напрямую в Интернет.

Подробности: `releases/1.0.9/README.md`, `docs/WEB-PORT.md`, `docs/SAMBA-AD-DC.md`, `docs/UI.md`.
