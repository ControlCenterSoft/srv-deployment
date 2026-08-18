# DHCP Server

## Установка из Маркета

DHCP Server устанавливается через **Маркет → DHCP Server → Установить**. Web UI создаёт ограниченный запрос, а `control-center-market-apply.service` выполняет пакетную операцию через APT.

Control Center **не захватывает существующий `dnsmasq`**, установленный вне продукта. Если пакет уже присутствует без защищённого ownership-state Control Center, установка модуля останавливается с ошибкой. Это предотвращает повреждение чужой DNS/DHCP-конфигурации.

После успешной установки появляется пункт меню **DHCP**. Сразу после установки DHCP ещё не раздаёт адреса: сначала нужно сохранить валидную конфигурацию.

## Отдельная служба DHCP

Управляемый DHCP работает через:

```text
control-center-dhcp-server.service
```

с командой:

```text
/usr/sbin/dnsmasq --keep-in-foreground --conf-file=/etc/dnsmasq.d/control-center-dhcp.conf
```

Дистрибутивный `dnsmasq.service` не используется как runtime Control Center и должен быть остановлен для управляемого модуля.

## Настройки

Доступны:

- интерфейс;
- начало диапазона;
- конец диапазона;
- маска (`24` или `255.255.255.0` в Web UI);
- шлюз;
- один или несколько DNS;
- срок аренды от 10 до 10080 минут.

## Двухуровневая проверка

Параметры проверяются Web API, а затем **повторно и независимо** root helper. Pending-файл находится в Web-writable state и не считается доверенным источником.

Root helper проверяет существование и имя интерфейса, IPv4 диапазона, CIDR, порядок start/end, network/broadcast, шлюз, DNS и срок аренды. Шлюз не может находиться внутри выдаваемого диапазона.

Перед записью `dnsmasq` CIDR prefix преобразуется в IPv4 netmask. Например, `/24` превращается в `255.255.255.0`.

## Применение и rollback

Web UI создаёт:

```text
/var/lib/control-center/dhcp-pending.json
```

Root helper проверяет, что DHCP зарегистрирован в защищённом ownership-state, повторно валидирует запрос и атомарно формирует:

```text
/etc/dnsmasq.d/control-center-dhcp.conf
```

Далее выполняется:

```bash
dnsmasq --test --conf-file=/etc/dnsmasq.d/control-center-dhcp.conf
systemctl restart control-center-dhcp-server.service
```

Rollback-копия хранится только в:

```text
/var/lib/control-center-root/control-center-dhcp.conf.rollback
```

При ошибке старый конфиг и предыдущее состояние runtime восстанавливаются.

## Защищённое состояние

```text
/var/lib/control-center-system/modules/dhcp.json
/var/lib/control-center-system/dhcp-config.json
/var/lib/control-center-system/dhcp-status.json
```

Ownership модуля хранится только в `root:control-center` system-state. Web UI не может подменить `package_owned`.

Для совместимости текущий Web API видит read-only ссылки из `/var/lib/control-center/` на эти файлы.

## Удаление

Удаление разрешено root-helper’ом только если модуль зарегистрирован в защищённом system-state. Пакет `dnsmasq` удаляется только когда `package_owned=true`, то есть когда он был установлен самим Control Center в доверенной новой схеме.

Legacy DHCP, мигрированный из старого Web-writable ownership-state, отмечается `package_owned=false`; удаление модуля не будет автоматически удалять пакет.

## Диагностика

```bash
systemctl status control-center-dhcp-server.service --no-pager
systemctl status control-center-dhcp-apply.path --no-pager
journalctl -u control-center-market-apply.service -n 100 --no-pager
journalctl -u control-center-dhcp-apply.service -n 100 --no-pager
sudo dnsmasq --test --conf-file=/etc/dnsmasq.d/control-center-dhcp.conf
sudo cat /etc/dnsmasq.d/control-center-dhcp.conf
sudo cat /var/lib/control-center-system/modules/dhcp.json
sudo cat /var/lib/control-center-system/dhcp-status.json
```
