# Сети Control Center 1.0.10

## Сетевые роли

Control Center поддерживает три рабочих схемы:

```text
WAN + LAN
только WAN
только LAN
```

В выпадающем списке каждой роли есть пункт **«Выключен»**. Обе роли одновременно выключить нельзя.

Состояние выключенной роли сохраняется явно как:

```json
{"enabled": false, "interface": "", "method": "disabled"}
```

Это важно: после перезапуска Control Center не пытается автоматически назначить выключенную роль другому интерфейсу.

## Маршрутизация

- WAN Static требует gateway.
- При включённом WAN поле gateway для LAN запрещено, чтобы не создавать второй default route.
- LAN DHCP при включённом WAN получает `dhcp4-overrides.use-routes: false`.
- Если WAN выключен и LAN является единственной сетью, LAN может использовать DHCP default route или Static gateway.

Таким образом одноинтерфейсный сервер не вынужден искусственно иметь две роли.

## Dashboard

`/api/system` возвращает для WAN и LAN поле `enabled`.

Web UI:

- показывает графики WAN и LAN, если включены обе роли;
- скрывает LAN-карточку, если LAN выключен;
- скрывает WAN-карточку, если WAN выключен.

## Перечень интерфейсов

В разделе **Сети** отображаются:

- роль WAN/LAN или отсутствие роли;
- имя интерфейса;
- ethernet / wifi / virtual;
- link state;
- IPv4;
- gateway;
- DNS;
- MAC;
- MTU;
- скорость.

Live-источники:

```text
/sys/class/net
ip -j -4 addr
ip -j -4 route
resolvectl dns
```

Длинный перечень интерфейсов использует пагинацию.

## Effective configuration

GET `/api/network/config` использует applied-state:

```text
/var/lib/control-center-system/network-config.json
```

Если applied-state уже существует, `enabled=false` имеет приоритет над автоматическим обнаружением. Для старых установок без applied-state сохраняется legacy auto-detection WAN по default route.

## Проверка и применение

POST `/api/network/config` сначала валидирует запрос в Web API, затем записывает:

```text
/var/lib/control-center/network-pending.json
```

Root helper повторно проверяет роли и генерирует только активные интерфейсы в:

```text
/etc/netplan/90-control-center.yaml
```

После этого выполняются:

```bash
netplan generate
netplan apply
```

При успехе applied-state сохраняется в:

```text
/var/lib/control-center-system/network-config.json
```

Rollback Netplan:

```text
/var/lib/control-center-root/90-control-center.yaml.rollback
```

## Валидация Static

Для активной роли проверяются:

- существующий интерфейс;
- уникальность интерфейса между WAN/LAN;
- IPv4 и маска;
- gateway;
- DNS;
- пересечение статических WAN/LAN подсетей.

WAN Static требует gateway. LAN Static может иметь gateway только когда WAN выключен.

## Диагностика

```bash
curl -fsS http://127.0.0.1:8080/api/network/config | python3 -m json.tool
sudo cat /var/lib/control-center-system/network-config.json
sudo cat /var/lib/control-center-system/network-status.json
sudo cat /etc/netplan/90-control-center.yaml
ip -br addr
ip route
resolvectl status
journalctl -u control-center-network-apply.service -n 100 --no-pager
```

Изменение интерфейса или адреса может оборвать Web/SSH-сессию. Root helper сохраняет rollback Netplan, но внешний firewall/NAT и физический доступ находятся вне контроля приложения.
