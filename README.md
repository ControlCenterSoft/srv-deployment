# Control Center 1.0.5

Control Center — web-панель управления Linux-сервером. Текущая production-линия: **1.0.5**.

## Редакции

- **Home** — редакция по умолчанию, без активации.
- **Professional** — активируемая редакция с криптографически подписанной лицензией, привязанной к ID сервера.

Текущая редакция, версия, ID устройства и состояние лицензии отображаются в **Настройки**.

## Возможности 1.0.5

- dashboard: CPU, RAM, Top-3 процессов, заполнение хранилищ, WAN RX/TX;
- WAN/LAN: назначение интерфейсов, DHCP/Static, проверка IP/маски/шлюза/DNS, Netplan apply/rollback;
- Маркет: установка/удаление DHCP Server (`dnsmasq`);
- динамический пункт меню DHCP после установки модуля;
- DHCP: диапазон, маска, шлюз, DNS, срок аренды, проверка и rollback;
- RBAC: просмотр локальных Linux-пользователей и групп;
- обновление Control Center: production-канал, интервал 5–10080 минут, rollback приложения;
- обновление ОС/пакетов: ручное или автоматическое, интервал 60–10080 минут;
- Home/Professional и механизм активации Professional.

## Архитектура привилегий

Web UI работает от отдельной системной УЗ `control-center` без root-доступа. Привилегированные операции выполняются отдельными systemd helpers.

State разделён по уровню доверия:

```text
/var/lib/control-center          # Web-writable requests/settings/status
/var/lib/control-center-root     # root-only rollback state, mode 0700
/var/lib/control-center-license  # root-owned подтверждённая лицензия
```

Network и DHCP root helpers **повторно валидируют pending JSON** перед привилегированным применением и не полагаются только на Web/API-валидацию. Web service не имеет доступа к root rollback state и имеет только чтение подтверждённой лицензии.

Приватный ключ издателя **не хранится в GitHub и не устанавливается на клиентский сервер**.

## Обновления пакетов

Системный worker выполняет:

```bash
apt-get update
apt-get -y upgrade --with-new-pkgs
```

Он не выполняет upgrade Ubuntu на следующий релиз и не перезагружает сервер автоматически. При необходимости перезагрузки это отражается в статусе.

Пакетные операции Control Center используют общий lock `/run/control-center-apt.lock`, чтобы APT не запускался параллельно из установщика, Маркета и системного updater.

## Установка

```bash
git clone --depth 1 --branch release/1.0.5 https://github.com/filosoff31/srv-deployment.git
cd srv-deployment
sudo bash install/install.sh
```

После установки:

```text
http://SERVER_IP:8080
```

Проверка:

```bash
cat /opt/control-center/VERSION
curl -fsS http://127.0.0.1:8080/api/health && echo
systemctl status control-center --no-pager
```

## Документация

- `docs/README.md` — индекс документации;
- `docs/INSTALL.md` — установка, обновление существующей установки и удаление;
- `docs/UPDATE.md` — обновление самого Control Center;
- `docs/OS_UPDATES.md` — обновление ОС и системных пакетов;
- `docs/LICENSING.md` — Home/Professional и выпуск/активация лицензий;
- `docs/NETWORK.md` — WAN/LAN и Netplan;
- `docs/DHCP.md` — установка и настройка DHCP Server;
- `docs/SECURITY.md` — модель привилегий, zero-trust helpers и известные ограничения;
- `docs/TROUBLESHOOTING.md` — диагностика компонентов;
- `docs/AUDIT-1.0.5.md` — результаты аудита и acceptance checklist.

## Важное ограничение безопасности

В 1.0.5 ещё нет полноценной встроенной аутентификации Web UI. Порт `8080` необходимо ограничивать доверенной административной LAN/VPN/firewall и **не публиковать напрямую в Интернет**. Подробности: `docs/SECURITY.md`.

## Удаление

Полностью:

```bash
sudo bash install/uninstall.sh
```

С сохранением Web-state, root rollback-state и лицензии:

```bash
sudo bash install/uninstall.sh --keep-data
```

## Исправления текущего аудита

В рамках проверки 1.0.5 исправлены: защищённое root-only хранение Professional-лицензии и rollback state, повторная root-валидация network/DHCP requests, валидная пара ключей издателя, ошибка проверки `APP_VERSION` в updater, rollback DHCP-конфигурации, восстановление сохранённых WAN/LAN значений в Web UI, одновременное отображение RX/TX на WAN-графике, общий APT lock, полное удаление всех новых services/helpers, устаревшая документация и кэширование публичного bootstrap.
