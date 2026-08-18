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

## Проверки

До передачи root helper проверяются:

- существование интерфейса;
- корректность начала/конца диапазона;
- принадлежность обоих адресов одной подсети;
- порядок `start <= end`;
- исключение адреса сети и broadcast;
- корректность шлюза и его принадлежность подсети;
- шлюз не должен входить в выдаваемый DHCP-диапазон;
- корректность DNS;
- срок аренды.

## Применение

Web UI создаёт:

```text
/var/lib/control-center/dhcp-pending.json
```

Root helper формирует:

```text
/etc/dnsmasq.d/control-center-dhcp.conf
```

После этого выполняются:

```bash
dnsmasq --test
systemctl restart dnsmasq
```

В исправленной 1.0.5 перед заменой создаётся rollback-копия. Если `dnsmasq --test` или restart завершается ошибкой, прежний конфигурационный файл восстанавливается.

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
cat /var/lib/control-center/dhcp-status.json
```

## Удаление

Удаление из Маркета останавливает dnsmasq, удаляет конфигурацию Control Center и состояние DHCP, затем удаляет пакет `dnsmasq`.
