# Центр уведомлений — Control Center 1.0.11

Operational alerts отображаются в **колокольчике**. Рабочие карточки показывают состояние и краткий feedback текущего действия, а длительные фоновые/root события сохраняются в notification center.

## Источники

`/api/notifications` агрегирует:

- Network apply / rollback / rejected;
- Market lifecycle;
- DHCP configuration/service и IP reservations;
- DNS lifecycle;
- Network Storage lifecycle;
- Domain/DNS/Storage cleanup-audits;
- лицензирование;
- Control Center updates;
- OS/package updates;
- Web runtime и SSL;
- PostgreSQL unavailable/degraded;
- hostname operations;
- **Samba AD-DC readiness/provisioning/active/error/rollback**.

## Samba AD-DC

Provisioning публикует события:

```text
started   → создание домена началось
active    → provisioning и acceptance успешно завершены
error     → запрос/операция отклонены или завершились ошибкой
rollback  → предыдущее состояние восстановлено
```

Market worker history использует `module=samba`, поэтому связанные lifecycle events также видны как `market-samba`.

Основной status-файл:

```text
/var/lib/control-center-system/samba-status.json
```

Последний root log:

```text
/var/lib/control-center-system/samba-last.log
```

В уведомления не записываются Administrator password и одноразовый approval code.

## DNS

Standalone DNS публикует lifecycle-события установки, применения конфигурации, удаления и ошибки. При переходе в Domain mode источник DNS остаётся видимым, но provider меняется с Unbound на Samba Internal DNS.

Основной status-файл:

```text
/var/lib/control-center-system/dns-status.json
```

После штатного удаления создаётся отдельное cleanup-событие. Оно считается успешным только при `clean=true` в cleanup-audit.

## Сетевое хранилище

Storage публикует события установки, перехода standalone ↔ domain mode, удаления и ошибки. Пользовательские файлы при удалении самой службы не удаляются; cleanup notification отражает очистку управляемых runtime/config artifacts, а не уничтожение данных.

Основной status-файл:

```text
/var/lib/control-center-system/storage-status.json
```

## DHCP и IP-бронирования

DHCP публикует:

```text
install/remove        → lifecycle DHCP Server
applied/error         → применение основной DHCP-конфигурации
reserve/release       → применение IP-бронирования
rollback/error        → откат неуспешной reservation-конфигурации
```

Status-файлы:

```text
/var/lib/control-center-system/dhcp-status.json
/var/lib/control-center-system/dhcp-reservations-status.json
```

Секретных данных DHCP notification не содержит.

## Cleanup-audit

После удаления Domain, DNS и Storage Control Center сохраняет отдельное operational событие cleanup. Источники имеют префикс `cleanup-` и позволяют отличить «команда удаления завершилась» от «доказано отсутствие управляемых артефактов».

Для Domain успешный cleanup дополнительно означает:

- совпали deterministic pre-state fingerprints;
- generated `sam.ldb` удалён, если его не было до provisioning;
- generated SYSVOL удалён, если его не было до provisioning;
- восстановлен точный package pre-state;
- standalone DNS/Storage возвращены, если существовали до Domain.

История cleanup доступна также через:

```text
GET /api/services/cleanup/audits
```

## PostgreSQL

При доступной БД read/unread и events сохраняются server-side. При DB outage Control Center остаётся в degraded notification mode и не должен скрывать operational failures.

## API

```text
GET  /api/notifications
POST /api/notifications/read
GET  /api/services/cleanup/audits
```

## Диагностика

```bash
curl -fsS http://127.0.0.1:8080/api/notifications | python3 -m json.tool
curl -fsS http://127.0.0.1:8080/api/services/cleanup/audits | python3 -m json.tool
sudo cat /var/lib/control-center-system/samba-status.json 2>/dev/null || true
sudo cat /var/lib/control-center-system/dns-status.json 2>/dev/null || true
sudo cat /var/lib/control-center-system/storage-status.json 2>/dev/null || true
sudo cat /var/lib/control-center-system/dhcp-status.json 2>/dev/null || true
sudo cat /var/lib/control-center-system/dhcp-reservations-status.json 2>/dev/null || true
sudo tail -n 100 /var/lib/control-center-system/samba-last.log 2>/dev/null || true
sudo tail -n 100 /var/lib/control-center-system/market-events.jsonl 2>/dev/null || true
sudo find /var/lib/control-center-system/cleanup-audits -maxdepth 1 -type f -print -exec cat {} \; 2>/dev/null || true
sudo -u control-center psql -d control_center -c \
  'select source,title,state,severity,is_read,last_seen_at,message from control_center.notification_events order by last_seen_at desc limit 50;'
```
