# Control Center 1.0.4

## Что нового

- оформление Web UI переработано по утвержденному образцу: компактный левый sidebar, верхняя служебная панель, темная плотная сетка карточек и статусные элементы;
- **DHCP Server** стал первым реально устанавливаемым модулем Маркета;
- установка DHCP выполняется отдельным привилегированным Market helper и устанавливает пакет `dnsmasq`;
- после установки в левом меню автоматически появляется пункт **DHCP**;
- после удаления DHCP пункт меню автоматически исчезает;
- DHCP настраивается из Web UI: интерфейс, начало/конец диапазона, маска, шлюз, DNS и срок аренды;
- конфигурация проверяется Web API и применяется отдельным root helper;
- системный Web-процесс по-прежнему не получает root-доступ.

## DHCP lifecycle

Web UI создает запрос `/var/lib/control-center/market-pending.json`. Systemd path unit запускает `control-center-market-apply`, который устанавливает или удаляет `dnsmasq` и обновляет состояние модуля.

После установки настройки доступны в меню **DHCP**. При сохранении создается `/var/lib/control-center/dhcp-pending.json`; helper `control-center-dhcp-apply` формирует `/etc/dnsmasq.d/control-center-dhcp.conf`, выполняет `dnsmasq --test` и перезапускает службу.

## Службы 1.0.4

- `control-center.service`
- `control-center-update.timer`
- `control-center-network-apply.path`
- `control-center-market-apply.path`
- `control-center-dhcp-apply.path`

## Установка

```bash
sudo bash install/install.sh
```

Проверка:

```bash
cat /opt/control-center/VERSION
curl -fsS http://127.0.0.1:8080/api/health
systemctl status control-center --no-pager
systemctl status control-center-market-apply.path --no-pager
systemctl status control-center-dhcp-apply.path --no-pager
```

Web UI: `http://SERVER_IP:8080`
