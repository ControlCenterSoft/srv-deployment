# Control Center 1.0.6

Control Center — web-панель управления Linux-сервером. Текущая release-ветка: **1.0.6**.

## Редакции

- **Home** — редакция по умолчанию, без активации.
- **Professional** — активируемая RSA/SHA-256 подписанной лицензией, привязанной к ID сервера.

## Возможности 1.0.6

- Система: CPU/RAM-графики, Top-3 процессов, хранилища, WAN RX/TX;
- Сети: WAN/LAN и **полный перечень интерфейсов** с ролью, типом, состоянием, IPv4, шлюзом, DNS, MAC, MTU и скоростью;
- загрузка уже применённых WAN/LAN параметров из protected state и фактического Control Center Netplan;
- Маркет: установка/удаление DHCP Server;
- DHCP: загрузка существующей конфигурации из protected state и `control-center-dhcp.conf`;
- DHCP additional options: код 1–254 + значение, просмотр, добавление и удаление;
- статус `control-center-dhcp-server.service` и проверка `dnsmasq --test` из Web UI;
- RBAC: просмотр локальных Linux-пользователей и групп;
- общий **центр уведомлений**: сеть, Маркет, DHCP, лицензия, обновления Control Center и ОС;
- колокольчик: непрочитанная ошибка — красный, непрочитанные события без ошибок — зелёный, всё прочитано — нейтральный;
- увеличенная типографика и семантические SVG-ярлычки меню;
- полностью переработанная мобильная верстка с off-canvas sidebar;
- обновление Control Center и отдельное обновление ОС/пакетов;
- production Gunicorn WSGI, CSP без `unsafe-inline`.

## Источники параметров

Control Center 1.0.6 различает запросы Web UI и фактически применённое состояние:

```text
/var/lib/control-center          # настройки и pending requests
/var/lib/control-center-system   # applied config/status/module ownership
/var/lib/control-center-root     # root-only rollback
/var/lib/control-center-license  # подтверждённая Professional license
```

Дополнительно Web UI только читает:

```text
/etc/netplan/90-control-center.yaml
/etc/dnsmasq.d/control-center-dhcp.conf
/sys/class/net
ip / resolvectl / systemctl
```

Это позволяет после перезапуска или обновления показывать не пустые формы, а уже применённые параметры и live-состояние.

## DHCP additional options

Основные поля управляют стандартными параметрами сети. Дополнительные numeric DHCP options можно добавлять отдельно. Options `1`, `3`, `6`, `51` зарезервированы за основными полями Control Center и не допускаются в дополнительном списке.

## Установка

```bash
git clone --depth 1 --branch release/1.0.6 https://github.com/filosoff31/srv-deployment.git
cd srv-deployment
sudo bash install/install.sh
```

Web UI:

```text
http://SERVER_IP:8080
```

## Acceptance

```bash
sudo bash scripts/acceptance-1.0.6.sh
```

Проверяются API/version/build, Gunicorn/CSP, network inventory, protected state, Netplan, notification API и DHCP status/config check при установленном модуле.

## Документация

- `docs/README.md` — индекс;
- `docs/INSTALL.md` — установка/обновление/удаление;
- `docs/NETWORK.md` — WAN/LAN и перечень интерфейсов;
- `docs/DHCP.md` — DHCP, additional options, status и config check;
- `docs/NOTIFICATIONS.md` — центр уведомлений;
- `docs/UI.md` — типографика, меню и мобильная верстка;
- `docs/SECURITY.md` — модель доверия и ограничения;
- `docs/TROUBLESHOOTING.md` — диагностика;
- `releases/1.0.6/README.md` — release notes.

## Ограничение безопасности

В 1.0.6 ещё нет полноценной встроенной аутентификации Web UI. TCP/8080 необходимо ограничивать доверенной административной LAN/VPN/firewall и не публиковать напрямую в Интернет.
