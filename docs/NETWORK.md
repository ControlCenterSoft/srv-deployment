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

## Проверки до применения

Control Center проверяет:

- существование выбранных интерфейсов;
- отсутствие одного интерфейса одновременно в WAN и LAN;
- корректность IPv4 и маски;
- корректность DNS;
- принадлежность шлюза указанной подсети;
- отсутствие совпадения IP и шлюза;
- отсутствие пересечения статических подсетей WAN и LAN.

## Применение

После проверки Web UI записывает `/var/lib/control-center/network-pending.json`. Root helper создаёт:

```text
/etc/netplan/90-control-center.yaml
```

и выполняет:

```bash
netplan generate
netplan apply
```

Перед заменой текущий файл Control Center сохраняется как rollback-копия. При ошибке предыдущий файл восстанавливается и Netplan применяется повторно.

## Важно при удалённом управлении

Изменение IP или интерфейса, через который открыты SSH/Web UI, может оборвать текущую сессию. До применения Static убедитесь, что новый адрес доступен из административной сети.

## Диагностика

```bash
cat /var/lib/control-center/network-config.json
cat /var/lib/control-center/network-status.json
sudo cat /etc/netplan/90-control-center.yaml
sudo netplan generate
ip -br addr
ip route
journalctl -u control-center-network-apply.service -n 100 --no-pager
```
