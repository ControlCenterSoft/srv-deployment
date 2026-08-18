# DHCP Server Control Center 1.0.6

## Установка

DHCP Server устанавливается через **Маркет → DHCP Server → Установить**. Управляемый runtime:

```text
control-center-dhcp-server.service
```

Control Center не захватывает внешний `dnsmasq`, установленный и настроенный вне продукта.

## Загрузка уже настроенных параметров

При открытии раздела DHCP Web API формирует effective configuration из двух источников:

1. `/var/lib/control-center-system/dhcp-config.json` — последнее успешно применённое состояние;
2. `/etc/dnsmasq.d/control-center-dhcp.conf` — фактически используемый конфигурационный файл.

Фактический `dnsmasq`-файл имеет приоритет для отображения уже работающих значений. Поэтому после перезапуска или обновления формы сохраняют текущие параметры.

Считываются:

- интерфейс;
- начало и конец диапазона;
- IPv4 netmask/CIDR;
- шлюз;
- DNS;
- срок аренды;
- дополнительные numeric DHCP options.

## Основные параметры

- интерфейс;
- начало диапазона;
- конец диапазона;
- маска (`24` или `255.255.255.0` в форме);
- шлюз;
- DNS;
- срок аренды 10–10080 минут.

## Дополнительные DHCP параметры

В 1.0.6 можно добавлять произвольные numeric DHCP options в формате:

```text
код + значение
```

Пример:

```text
66 → 192.168.10.2
67 → bootx64.efi
252 → http://192.168.10.1/wpad.dat
```

Ограничения:

- код: `1..254`;
- максимум 32 дополнительных options;
- один код нельзя добавить дважды;
- значение не может содержать управляющие символы/переводы строк;
- options `1`, `3`, `6`, `51` зарезервированы за основными полями Control Center.

Root helper повторно валидирует additional options и генерирует строки:

```text
dhcp-option=66,192.168.10.2
```

Текущие дополнительные параметры отображаются таблицей и могут быть удалены из будущей конфигурации перед сохранением.

## Статус DHCP

В заголовке раздела показывается фактический systemd status:

```text
control-center-dhcp-server.service
```

Состояния интерфейса:

- `Работает` — service active;
- `Установлен · не настроен` — модуль установлен, но `dhcp-range` ещё отсутствует;
- `INACTIVE/FAILED` — конфигурация есть, но service не работает.

## Проверка конфигурации

Кнопка **Проверить конфигурацию** не изменяет сервер. Она выполняет:

```bash
dnsmasq --test --conf-file=/etc/dnsmasq.d/control-center-dhcp.conf
```

API:

```bash
curl -fsS -X POST http://127.0.0.1:8080/api/dhcp/check | python3 -m json.tool
```

При ошибке Web UI показывает диагностический вывод `dnsmasq`.

## Двухуровневая проверка и применение

Web API проверяет запрос и пишет:

```text
/var/lib/control-center/dhcp-pending.json
```

Root helper независимо повторяет проверку интерфейса, диапазона, netmask, gateway, DNS, lease и дополнительных options. Затем формирует временный конфиг, выполняет `dnsmasq --test` и только после успешной проверки перезапускает выделенный DHCP runtime.

Успешно применённое состояние:

```text
/var/lib/control-center-system/dhcp-config.json
/var/lib/control-center-system/dhcp-status.json
/var/lib/control-center-system/modules/dhcp.json
```

Rollback:

```text
/var/lib/control-center-root/control-center-dhcp.conf.rollback
```

## Диагностика

```bash
curl -fsS http://127.0.0.1:8080/api/dhcp/config | python3 -m json.tool
curl -fsS -X POST http://127.0.0.1:8080/api/dhcp/check | python3 -m json.tool
systemctl status control-center-dhcp-server.service --no-pager
journalctl -u control-center-dhcp-server.service -n 100 --no-pager
journalctl -u control-center-dhcp-apply.service -n 100 --no-pager
sudo cat /etc/dnsmasq.d/control-center-dhcp.conf
sudo cat /var/lib/control-center-system/dhcp-config.json
sudo cat /var/lib/control-center-system/dhcp-status.json
```
