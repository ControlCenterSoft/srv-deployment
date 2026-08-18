# Сети Control Center 1.0.6

## Перечень интерфейсов

В разделе **Сети** снова отображается полный перечень обнаруженных интерфейсов. Для каждого показываются:

- назначенная роль WAN/LAN;
- имя интерфейса;
- тип: ethernet / wifi / virtual;
- link state;
- текущие IPv4 адреса;
- текущий default gateway;
- DNS интерфейса, если доступен через `resolvectl`;
- MAC;
- MTU;
- скорость интерфейса, если её сообщает kernel/sysfs.

Источники live-данных:

```text
/sys/class/net
ip -j -4 addr
ip -j -4 route
resolvectl dns
```

## Загрузка уже настроенных WAN/LAN параметров

Control Center не должен показывать пустую форму после рестарта. В 1.0.6 GET `/api/network/config` формирует effective configuration из:

1. защищённого applied-state `/var/lib/control-center-system/network-config.json`;
2. фактического `/etc/netplan/90-control-center.yaml`;
3. live IPv4/gateway/DNS/link state интерфейсов.

Если сохранённая роль отсутствует, WAN может быть определён по интерфейсу с default route. LAN при наличии Control Center Netplan выбирается из оставшихся настроенных интерфейсов.

Netplan-файл Control Center имеет права:

```text
root:control-center 0640
```

Web service может его читать, но не изменять.

## Назначение интерфейсов

- `WAN` — внешний интерфейс;
- `LAN` — локальный интерфейс.

Один интерфейс нельзя назначить обеим ролям одновременно.

## DHCP / Static

При DHCP адрес получается автоматически. Для LAN DHCP-client default route не используется.

При Static доступны:

- IP;
- маска CIDR или dotted netmask;
- шлюз;
- DNS.

WAN Static требует шлюз. Для LAN шлюз необязателен.

## Проверка и применение

Web API валидирует запрос и записывает:

```text
/var/lib/control-center/network-pending.json
```

Root helper повторно проверяет все критичные поля, генерирует `/etc/netplan/90-control-center.yaml`, выполняет:

```bash
netplan generate
netplan apply
```

Успешно применённая конфигурация сохраняется в:

```text
/var/lib/control-center-system/network-config.json
```

Rollback:

```text
/var/lib/control-center-root/90-control-center.yaml.rollback
```

## Диагностика

```bash
curl -fsS http://127.0.0.1:8080/api/network/config | python3 -m json.tool
curl -fsS http://127.0.0.1:8080/api/networks | python3 -m json.tool
sudo cat /var/lib/control-center-system/network-config.json
sudo cat /var/lib/control-center-system/network-status.json
sudo cat /etc/netplan/90-control-center.yaml
ip -br addr
ip route
resolvectl status
journalctl -u control-center-network-apply.service -n 100 --no-pager
```

## Удалённое управление

Изменение активного адреса или интерфейса может оборвать Web/SSH-сессию. При удалённой настройке сети рекомендуется иметь резервный административный канал.
