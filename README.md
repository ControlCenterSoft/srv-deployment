# Control Center 1.0.5

Control Center — web-панель управления Linux-сервером. Текущая production-линия: **1.0.5**.

## Редакции

- **Home** — редакция по умолчанию, без активации.
- **Professional** — активируемая редакция с RSA/SHA-256 подписанной лицензией, привязанной к ID сервера.

Текущая редакция, версия, ID устройства и состояние лицензии отображаются в **Настройки**.

## Возможности 1.0.5

- dashboard: CPU, RAM, Top-3 процессов, заполнение хранилищ, WAN RX/TX;
- WAN/LAN: назначение интерфейсов, DHCP/Static, проверка IP/маски/шлюза/DNS, Netplan apply/rollback;
- Маркет: установка/удаление DHCP Server (`dnsmasq`) с защищённым ownership-state;
- отдельный runtime `control-center-dhcp-server.service` и динамический пункт меню DHCP;
- DHCP: диапазон, маска, шлюз, DNS, срок аренды, двойная проверка и rollback;
- RBAC: просмотр локальных Linux-пользователей и групп;
- обновление Control Center: production-канал, интервал 5–10080 минут, root-only rollback;
- обновление ОС/пакетов: ручное или автоматическое, интервал 60–10080 минут;
- Home/Professional и механизм активации Professional;
- production WSGI через Gunicorn и HTTP security headers.

## Архитектура состояния и привилегий

Web UI работает от отдельной системной УЗ `control-center` без root-доступа. Привилегированные операции выполняются отдельными systemd helpers.

```text
/var/lib/control-center          # Web-writable settings + pending requests
/var/lib/control-center-system   # root:control-center applied state/status/modules
/var/lib/control-center-root     # root:root 0700 rollback state
/var/lib/control-center-license  # root:control-center validated license
```

Network/DHCP root helpers повторно валидируют pending JSON непосредственно перед применением. Ownership DHCP-модуля, применённые конфигурации и root-worker statuses находятся вне Web-writable state.

Web service получает только чтение `/var/lib/control-center-system` и `/var/lib/control-center-license`, а `/var/lib/control-center-root` для него полностью недоступен.

Приватный ключ Professional **не хранится в GitHub и не устанавливается на клиентский сервер**.

## Web runtime и защита

Production Web UI запускается Gunicorn через `wsgi:app`. WSGI layer добавляет CSP/nosniff/frame protection, same-origin проверку browser write requests, request-size limit и collision-safe atomic JSON writes для нескольких workers. Динамические значения в `innerHTML` экранируются.

В 1.0.5 пока нет полноценной встроенной аутентификации Web UI. Поэтому TCP/8080 должен быть доступен только из доверенной административной LAN/VPN/firewall и **не должен публиковаться напрямую в Интернет**.

## DHCP ownership

Control Center не захватывает уже установленный внешним способом `dnsmasq`. Новый модуль запускается отдельным `control-center-dhcp-server.service`; дистрибутивный `dnsmasq.service` не используется как managed runtime. Пакет удаляется только если защищённый system-state подтверждает `package_owned=true`.

## Обновления пакетов

```bash
apt-get update
apt-get -y upgrade --with-new-pkgs
```

OS updater не выполняет upgrade Ubuntu на следующий релиз и не перезагружает сервер автоматически. Внутренние пакетные операции Control Center сериализованы через `/run/control-center-apt.lock`.

## Установка

```bash
git clone --depth 1 --branch release/1.0.5 https://github.com/filosoff31/srv-deployment.git
cd srv-deployment
sudo bash install/install.sh
```

Web UI:

```text
http://SERVER_IP:8080
```

## Acceptance после установки

```bash
sudo bash scripts/acceptance-1.0.5.sh
```

Скрипт не изменяет конфигурацию и проверяет версию/API, HTTP headers, Gunicorn, systemd units, protected state, Professional public key, Netplan и managed DHCP (если он настроен).

## Документация

- `docs/README.md` — индекс;
- `docs/INSTALL.md` — установка/переустановка/удаление;
- `docs/UPDATE.md` — обновление Control Center;
- `docs/OS_UPDATES.md` — обновление ОС и пакетов;
- `docs/LICENSING.md` — Home/Professional и активация;
- `docs/NETWORK.md` — WAN/LAN и Netplan;
- `docs/DHCP.md` — DHCP lifecycle;
- `docs/SECURITY.md` — модель доверия и ограничения;
- `docs/TROUBLESHOOTING.md` — диагностика;
- `docs/AUDIT-1.0.5.md` — полный отчёт аудита.

## Удаление

Полностью:

```bash
sudo bash install/uninstall.sh
```

С сохранением Web/system/root/license state и служебной УЗ:

```bash
sudo bash install/uninstall.sh --keep-data
```

## Аудит 1.0.5

Полный аудит исправил: хранение лицензии и ownership модулей, trust boundaries pending/system/root state, updater version parser, DHCP netmask/rollback/runtime ownership, гонки APT и JSON writes, WAN chart, восстановление сетевой формы, XSS-экранирование, production WSGI, security headers, uninstall lifecycle, stale website/bootstrap caching и устаревшую документацию. Для предотвращения регрессий добавлены GitHub Actions validation workflows и серверный acceptance script.
