# DHCP Server — Control Center 1.0.11

## Установка

DHCP Server устанавливается через Маркет и использует `dnsmasq` только как DHCP runtime (`port=0`). Рабочий unit:

```text
control-center-dhcp-server.service
```

Установка/удаление и ошибки отображаются в Маркете и колокольчике.

## Конфигурация

Считываются и применяются:

- interface;
- range start/end;
- IPv4 mask/CIDR;
- gateway;
- DNS;
- lease time;
- дополнительные numeric DHCP options 1..254.

Codes `1`, `3`, `6`, `51` управляются основными полями. Перед restart выполняется `dnsmasq --test`.

Основной managed config:

```text
/etc/dnsmasq.d/control-center-dhcp.conf
```

## DHCP-клиенты

1.0.11 добавляет `GET /api/dhcp/clients`, который объединяет фактические leases dnsmasq и reservations.

Таблица показывает:

- ONLINE/OFFLINE;
- hostname;
- MAC;
- текущий IPv4;
- expiry;
- reserved IPv4.

Список пагинируется по 10 строк.

## IP-бронирования

Из интерфейса можно:

- забронировать текущий адрес;
- изменить адрес бронирования;
- снять бронь.

`POST /api/dhcp/reservations` поддерживает `reserve` и `release`.

Web API и root worker независимо проверяют:

- MAC format;
- IPv4 format;
- принадлежность DHCP subnet;
- запрет network/broadcast/gateway;
- duplicate MAC/IP;
- конфликт с активной арендой другого MAC;
- hostname;
- запрет IP активного Domain Controller.

Reservations config:

```text
/etc/dnsmasq.d/control-center-dhcp-reservations.conf
```

Перед применением оба DHCP config проверяются совместно через `dnsmasq --test`. Ошибка вызывает rollback reservation config.

PostgreSQL migration 005 хранит текущие брони в:

```text
control_center.dhcp_reservations
```

## Дополнительные DHCP options

Поддерживаются numeric options, максимум 32 записи. Примеры:

```text
66 → 192.168.10.2
67 → bootx64.efi
252 → http://192.168.10.1/wpad.dat
```

## Domain DNS integration

Если DHCP обслуживает interface активного Domain Controller, DNS автоматически меняется на IPv4 самого AD-DC.

Последующие попытки выдать клиентам внешний DNS напрямую блокируются. Публичное разрешение выполняется Samba Internal DNS через configured forwarder.

## Диагностика

```bash
systemctl status control-center-dhcp-server.service --no-pager
sudo dnsmasq --test \
  --conf-file=/etc/dnsmasq.d/control-center-dhcp.conf \
  --conf-file=/etc/dnsmasq.d/control-center-dhcp-reservations.conf
sudo cat /var/lib/control-center-system/dhcp-config.json
sudo cat /var/lib/control-center-system/dhcp-reservations.json 2>/dev/null || true
sudo cat /var/lib/control-center-system/dhcp-reservations-status.json 2>/dev/null || true
sudo -u control-center psql -d control_center -c 'select * from control_center.dhcp_reservations order by ipv4;'
```
