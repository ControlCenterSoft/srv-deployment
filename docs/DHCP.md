# DHCP Server — Control Center 1.0.8

## Установка из Маркета

DHCP Server устанавливается через **Маркет → DHCP Server → Установить**. Карточка показывает server-side lifecycle status и не теряет его после обновления страницы:

- **Установка…** — root worker выполняет пакетную операцию;
- **Работает** — `dnsmasq` установлен и модуль зарегистрирован Control Center;
- **Ошибка** — операция завершилась ошибкой; полный diagnostic detail доступен по наведению на статус;
- **Не установлен** — модуль доступен для установки.

Управляемый DHCP runtime после настройки:

```text
control-center-dhcp-server.service
```

Дистрибутивный `dnsmasq.service` не используется для рабочего DHCP Control Center.

## Исправленная установка 1.0.8

Пакет `dnsmasq` может пытаться стартовать во время `apt install`, ещё до появления конфигурации Control Center. В 1.0.8 Market worker временно устанавливает `policy-rc.d`, который запрещает только старт `dnsmasq` во время package transaction и обязательно восстанавливает предыдущий `policy-rc.d`, если он существовал.

После установки worker выполняет:

```bash
dpkg-query -W -f='${Status}' dnsmasq
command -v dnsmasq
dnsmasq --test --conf-file=/etc/dnsmasq.d/control-center-dhcp.conf
systemctl disable --now dnsmasq.service
```

До пользовательской настройки создаётся безопасный placeholder:

```text
/etc/dnsmasq.d/control-center-dhcp.conf
```

с `port=0` и без `dhcp-range`, поэтому модуль считается установленным, но ещё не выдаёт адреса.

## Recovery предыдущей неудачной установки

Если более ранняя операция Control Center успела установить пакет, но не записала module state, 1.0.8 может восстановить установку. Recovery разрешён только если одновременно выполняются условия безопасности:

1. есть признаки предыдущей операции Control Center (`market-status.json` либо managed DHCP config);
2. пакет `dnsmasq` уже установлен;
3. в чужих конфигурационных файлах нет DHCP directives `dhcp-range`, `dhcp-host` или `dhcp-option`.

Если обнаружена внешняя DHCP-конфигурация, Control Center **не захватывает** её автоматически.

Старая маска `/etc/systemd/system/dnsmasq.service -> /dev/null`, оставшаяся от прежней незавершённой попытки Control Center, удаляется только при подтверждённом recovery-контексте.

## Protected lifecycle state

```text
/var/lib/control-center-system/market-status.json
/var/lib/control-center-system/market-events.jsonl
/var/lib/control-center-system/market-last.log
/var/lib/control-center-system/modules/dhcp.json
```

`market-last.log` содержит вывод последней Market операции. При ошибке последние строки попадают в `detail` статуса, tooltip и notification failure event.

## Уведомления установки

Каждая установка создаёт отдельные события:

```text
Установка началась: DHCP Server
Установка успешно завершена: DHCP Server
```

или:

```text
Установка DHCP Server завершилась ошибкой (...)
<diagnostic detail>
```

События имеют server timestamp и синхронизируются в PostgreSQL-центр уведомлений.

## Настройка DHCP после установки

Форма DHCP формирует effective configuration из:

1. `/var/lib/control-center-system/dhcp-config.json` — последнее успешно применённое состояние;
2. `/etc/dnsmasq.d/control-center-dhcp.conf` — фактический managed config.

Считываются:

- интерфейс;
- начало/конец диапазона;
- IPv4 netmask/CIDR;
- шлюз;
- DNS;
- срок аренды;
- дополнительные numeric DHCP options.

## Основные параметры

- интерфейс;
- начало и конец диапазона;
- маска (`24` или `255.255.255.0`);
- шлюз;
- DNS;
- аренда 10–10080 минут.

## Дополнительные DHCP options

Поддерживаются numeric options `1..254`, максимум 32 записи. Codes `1`, `3`, `6`, `51` зарезервированы основными полями. Дубли и управляющие символы запрещены.

Пример:

```text
66 → 192.168.10.2
67 → bootx64.efi
252 → http://192.168.10.1/wpad.dat
```

## Проверка конфигурации

Кнопка **Проверить конфигурацию** выполняет read-only:

```bash
dnsmasq --test --conf-file=/etc/dnsmasq.d/control-center-dhcp.conf
```

## Двухуровневое применение

Web API проверяет запрос и пишет `/var/lib/control-center/dhcp-pending.json`. Root helper повторно валидирует интерфейс, диапазон, netmask, gateway, DNS, lease и additional options, генерирует временный config, выполняет `dnsmasq --test` и только затем перезапускает `control-center-dhcp-server.service`.

## Диагностика установки

```bash
PORT=$(sed -n 's/^CONTROL_CENTER_PORT=//p' /etc/control-center/web.env)
curl -fsS "http://127.0.0.1:${PORT}/api/market" | python3 -m json.tool
sudo cat /var/lib/control-center-system/market-status.json | python3 -m json.tool
sudo tail -n 100 /var/lib/control-center-system/market-last.log
sudo tail -n 30 /var/lib/control-center-system/market-events.jsonl
journalctl -u control-center-market-apply.service -n 200 --no-pager
dpkg-query -W -f='${Status}\n' dnsmasq
sudo dnsmasq --test --conf-file=/etc/dnsmasq.d/control-center-dhcp.conf
```

## Диагностика работающего DHCP

```bash
systemctl status control-center-dhcp-server.service --no-pager
journalctl -u control-center-dhcp-server.service -n 100 --no-pager
curl -fsS "http://127.0.0.1:${PORT}/api/dhcp/config" | python3 -m json.tool
sudo cat /var/lib/control-center-system/dhcp-config.json 2>/dev/null || true
sudo cat /var/lib/control-center-system/dhcp-status.json 2>/dev/null || true
```
