# Сетевые настройки WAN/LAN

## Назначение интерфейсов

В разделе **Сети** назначаются две логические роли:

- `WAN` — внешний интерфейс;
- `LAN` — локальный интерфейс.

Один физический интерфейс нельзя одновременно назначить WAN и LAN.

## DHCP

При выборе DHCP интерфейс получает IPv4 автоматически. Для LAN DHCP-клиента default route не используется, чтобы локальный интерфейс не перехватывал маршрут WAN.

## Static

Активируются поля:

- IP-адрес;
- маска (`24` или `255.255.255.0`);
- шлюз;
- DNS.

Для WAN Static шлюз обязателен. Для LAN шлюз может отсутствовать.

## Двухуровневая проверка

Проверка выполняется дважды: сначала Web API, затем независимо root helper непосредственно перед генерацией Netplan. Root helper не доверяет содержимому Web-writable pending-файла.

Проверяются:

- реальное существование интерфейса в `/sys/class/net`;
- безопасный формат имени интерфейса и отсутствие `lo`;
- отсутствие одного интерфейса одновременно в WAN и LAN;
- допустимый режим DHCP/Static;
- IPv4, CIDR/mask и запрещённые loopback/multicast/unspecified адреса;
- DNS;
- принадлежность шлюза указанной подсети;
- отсутствие совпадения IP и шлюза;
- обязательный шлюз WAN Static;
- отсутствие пересечения статических подсетей WAN и LAN.

## Применение

Web UI записывает:

```text
/var/lib/control-center/network-pending.json
```

Root helper повторно проверяет запрос, формирует временный файл, а затем атомарно заменяет:

```text
/etc/netplan/90-control-center.yaml
```

После этого выполняются:

```bash
netplan generate
netplan apply
```

Rollback-копия хранится только в root-only каталоге:

```text
/var/lib/control-center-root/90-control-center.yaml.rollback
```

При ошибке предыдущий Netplan восстанавливается и применяется повторно. Невалидный pending request удаляется и получает статус `rejected`.

## Важно при удалённом управлении

Изменение IP или интерфейса, через который открыты SSH/Web UI, может оборвать текущую сессию. До применения Static убедитесь, что новый адрес доступен из административной сети.

## Диагностика

```bash
cat /var/lib/control-center/network-config.json
cat /var/lib/control-center/network-status.json
sudo cat /etc/netplan/90-control-center.yaml
sudo ls -l /var/lib/control-center-root/
sudo netplan generate
ip -br addr
ip route
journalctl -u control-center-network-apply.service -n 100 --no-pager
```
