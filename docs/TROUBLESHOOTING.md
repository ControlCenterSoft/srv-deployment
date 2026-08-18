# Диагностика Control Center 1.0.6

## Быстрый acceptance

```bash
sudo bash scripts/acceptance-1.0.6.sh
```

Если вывод заканчивается `ACCEPTANCE: FAILED`, исправляйте указанные `FAIL` сверху вниз.

## Общая проверка

```bash
cat /opt/control-center/VERSION
curl -fsS http://127.0.0.1:8080/api/health | python3 -m json.tool
systemctl status control-center --no-pager
systemctl cat control-center
ss -ltnp | grep ':8080'
```

Ожидаемая версия: `1.0.6`.

## Web UI не открывается или выглядит как старая версия

```bash
journalctl -u control-center -n 200 --no-pager
systemctl restart control-center
curl -v http://127.0.0.1:8080/api/health
```

В 1.0.6 CSS/JS подключаются как:

```text
/static/app.css?v=1.0.6
/static/app.js?v=1.0.6
```

Если API уже 1.0.6, а браузер показывает старую верстку, выполните обычное обновление страницы; query-version должен исключить повторное использование старых static assets.

## Мобильное меню отображается неправильно

Проверьте, что установлена именно 1.0.6 и `/opt/control-center/app/static/app.css` содержит `mobile-nav-open` и media query `max-width:900px`.

```bash
grep -n 'mobile-nav-open\|max-width:900px' /opt/control-center/app/static/app.css
```

На мобильном sidebar должен открываться поверх контента, а не сжимать страницу.

## Список сетевых интерфейсов пуст

```bash
ip -br link
ip -j -4 addr
curl -fsS http://127.0.0.1:8080/api/networks | python3 -m json.tool
ls -l /sys/class/net
```

`lo` намеренно не отображается. Остальные интерфейсы должны появляться в API и таблице **Сети → Сетевые интерфейсы**.

## WAN/LAN форма не подгружает уже настроенные параметры

```bash
curl -fsS http://127.0.0.1:8080/api/network/config | python3 -m json.tool
sudo cat /var/lib/control-center-system/network-config.json 2>/dev/null || true
sudo cat /etc/netplan/90-control-center.yaml 2>/dev/null || true
ls -l /etc/netplan/90-control-center.yaml 2>/dev/null || true
ip -4 addr
ip route
resolvectl status
```

Для Control Center-managed Netplan ожидаются права:

```text
root:control-center 0640
```

Applied-state имеет приоритет назначения ролей, а Netplan/live state используется для сверки и заполнения фактических параметров.

## Сеть не применяется

```bash
sudo cat /var/lib/control-center-system/network-status.json
journalctl -u control-center-network-apply.service -n 200 --no-pager
sudo netplan generate
sudo cat /etc/netplan/90-control-center.yaml
ip -br addr
ip route
```

Статус `rejected` означает, что root helper повторно проверил запрос и отказался его применять.

## DHCP не устанавливается

```bash
sudo cat /var/lib/control-center-system/market-status.json 2>/dev/null || true
journalctl -u control-center-market-apply.service -n 200 --no-pager
sudo cat /var/lib/control-center-system/modules/dhcp.json 2>/dev/null || true
```

Если `dnsmasq` уже установлен вне Control Center, автоматический захват намеренно запрещён.

## DHCP форма пустая, хотя сервер уже настроен

```bash
curl -fsS http://127.0.0.1:8080/api/dhcp/config | python3 -m json.tool
sudo cat /var/lib/control-center-system/dhcp-config.json 2>/dev/null || true
sudo cat /etc/dnsmasq.d/control-center-dhcp.conf
```

1.0.6 читает и protected applied-state, и фактический `control-center-dhcp.conf`. Поле `source` в API показывает, откуда получены текущие значения.

## DHCP установлен, но не работает

```bash
systemctl status control-center-dhcp-server.service --no-pager
journalctl -u control-center-dhcp-server.service -n 150 --no-pager
sudo cat /var/lib/control-center-system/dhcp-status.json
sudo cat /etc/dnsmasq.d/control-center-dhcp.conf
sudo dnsmasq --test --conf-file=/etc/dnsmasq.d/control-center-dhcp.conf
```

Managed DHCP должен работать через `control-center-dhcp-server.service`, не через дистрибутивный `dnsmasq.service`.

## Проверка DHCP из Web UI возвращает ошибку

Повторите ту же read-only проверку вручную:

```bash
curl -sS -X POST http://127.0.0.1:8080/api/dhcp/check | python3 -m json.tool
sudo dnsmasq --test --conf-file=/etc/dnsmasq.d/control-center-dhcp.conf
```

Web-кнопка **Проверить конфигурацию** не изменяет файл и не перезапускает DHCP.

## Дополнительные DHCP параметры не сохраняются

Проверьте ограничения:

- код `1..254`;
- codes `1`, `3`, `6`, `51` зарезервированы;
- один код нельзя добавить дважды;
- максимум 32 дополнительных options.

После успешного применения:

```bash
sudo grep '^dhcp-option=' /etc/dnsmasq.d/control-center-dhcp.conf
sudo cat /var/lib/control-center-system/dhcp-config.json | python3 -m json.tool
```

Несохранённые изменения формы больше не должны перезаписываться фоновым polling: 1.0.6 обновляет в фоне только status/runtime, а полную форму перечитывает при входе в раздел и после успешного сохранения.

## Колокольчик не показывает события

```bash
curl -fsS http://127.0.0.1:8080/api/notifications | python3 -m json.tool
sudo find /var/lib/control-center-system -maxdepth 1 -name '*status.json' -ls
```

Read/unread хранится локально в браузере. Если нужно сбросить только прочитанность, очистите site data/localStorage для адреса Control Center. Server-side статусы при этом не меняются.

Логика цвета:

- красный — непрочитанная ошибка;
- зелёный — есть непрочитанные события без ошибок;
- серый/нейтральный — текущие события прочитаны.

## Control Center не обновляется

```bash
cat /var/lib/control-center/update-settings.json
sudo cat /var/lib/control-center-system/update-status.json 2>/dev/null || true
systemctl status control-center-update.timer --no-pager
sudo systemctl start control-center-update.service
journalctl -u control-center-update.service -n 200 --no-pager
```

## Обновление ОС не запускается

```bash
cat /var/lib/control-center/os-update-settings.json
sudo cat /var/lib/control-center-system/os-update-status.json 2>/dev/null || true
systemctl status control-center-os-update.timer --no-pager
journalctl -u control-center-os-update.service -n 200 --no-pager
```

## Professional не активируется

```bash
curl -fsS http://127.0.0.1:8080/api/license | python3 -m json.tool
sudo cat /var/lib/control-center-system/license-status.json 2>/dev/null || true
journalctl -u control-center-license-apply.service -n 100 --no-pager
ls -ld /var/lib/control-center-license
ls -l /var/lib/control-center-license/license.json 2>/dev/null || true
```

## Все компоненты

```bash
systemctl list-unit-files | grep '^control-center'
systemctl list-timers --all | grep control-center
systemctl list-units --type=path | grep control-center
ls -l /usr/local/sbin/control-center-*
```

## Ошибки последнего часа

```bash
journalctl -p warning..alert --since '1 hour ago' --no-pager
```
