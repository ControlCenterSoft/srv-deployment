# Control Center 1.0.2

Control Center — web-панель управления Linux-сервером.

## Что нового в 1.0.2

- раздел **Система** переработан в стиле предыдущего проекта Control Center;
- в разделе **Сети** добавлены логические роли **WAN** и **LAN**;
- WAN и LAN можно назначать на обнаруженные сетевые интерфейсы;
- для каждой роли доступны режимы IPv4 **DHCP** и **Static**;
- в Static активируются IP, маска, шлюз и DNS;
- добавлена серверная проверка корректности сетевой конфигурации;
- WAN и LAN не могут использовать один интерфейс;
- проверяется IPv4, маска, шлюз, DNS, принадлежность шлюза подсети и пересечение статических WAN/LAN подсетей;
- применение выполняется отдельным root-helper через Netplan;
- при ошибке Netplan выполняется rollback предыдущей конфигурации.

## Сетевое управление

Web UI работает без root. После успешной проверки он создает `/var/lib/control-center/network-pending.json`. Systemd path-unit запускает `/usr/local/sbin/control-center-network-apply`, который повторно формирует Netplan-конфигурацию, выполняет `netplan generate`, затем `netplan apply`.

Службы:

- `control-center-network-apply.path`;
- `control-center-network-apply.service`.

Файл Netplan Control Center:

- `/etc/netplan/90-control-center.yaml`.

## Установка

```bash
sudo bash install/install.sh
```

Web UI:

```text
http://SERVER_IP:8080
```

Проверка:

```bash
systemctl status control-center --no-pager
systemctl status control-center-network-apply.path --no-pager
systemctl status control-center-update.timer --no-pager
curl http://127.0.0.1:8080/api/health
```

## Важно

Изменение адреса интерфейса, через который открыт Web UI/SSH, может оборвать текущую сессию. Поэтому перед применением Static необходимо убедиться, что новый адрес доступен из административной сети.
