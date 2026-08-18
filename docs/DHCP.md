# DHCP Server

## Установка

DHCP Server устанавливается из **Маркет → DHCP Server → Установить**. Web UI создаёт запрос, а `control-center-market-apply.service` устанавливает пакет `dnsmasq` через APT.

После успешной установки появляется пункт меню **DHCP**. После удаления пункт исчезает.

## Настройки

Доступны:

- интерфейс;
- начало диапазона;
- конец диапазона;
- маска;
- шлюз;
- один или несколько DNS;
- срок аренды от 10 до 10080 минут.

## Двухуровневая проверка

Параметры проверяются Web API, а затем **повторно и независимо** root helper. Pending-файл находится в Web-writable state и поэтому не считается доверенным источником.

Root helper проверяет:

- реальное существование интерфейса и безопасный формат его имени;
- IPv4 начала и конца диапазона;
- CIDR/mask;
- принадлежность диапазона одной подсети;
- порядок `start <= end`;
- исключение network и broadcast;
- IPv4 шлюза и его принадлежность подсети;
- шлюз не должен входить в выдаваемый диапазон;
- каждый DNS-адрес;
- срок аренды 10–10080 минут.

## Применение

Web UI создаёт:

```text
/var/lib/control-center/dhcp-pending.json
```

После привилегированной повторной проверки helper формирует временный файл и заменяет:

```text
/etc/dnsmasq.d/control-center-dhcp.conf
```

После этого выполняются:

```bash
dnsmasq --test
systemctl restart dnsmasq
```

Rollback-копия находится в root-only state:

```text
/var/lib/control-center-root/control-center-dhcp.conf.rollback
```

Если `dnsmasq --test` или restart завершается ошибкой, прежняя конфигурация восстанавливается. Невалидный запрос удаляется и получает статус `rejected`.

## Состояние

```text
/var/lib/control-center/modules/dhcp.json
/var/lib/control-center/dhcp-config.json
/var/lib/control-center/dhcp-status.json
```

## Диагностика

```bash
systemctl status dnsmasq --no-pager
journalctl -u dnsmasq -n 100 --no-pager
journalctl -u control-center-market-apply.service -n 100 --no-pager
journalctl -u control-center-dhcp-apply.service -n 100 --no-pager
sudo dnsmasq --test
sudo cat /etc/dnsmasq.d/control-center-dhcp.conf
sudo ls -l /var/lib/control-center-root/
cat /var/lib/control-center/dhcp-status.json
```

## Удаление

Удаление из Маркета останавливает dnsmasq, удаляет конфигурацию Control Center и состояние DHCP, затем удаляет пакет `dnsmasq`.
