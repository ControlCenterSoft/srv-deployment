# Центр уведомлений — Control Center 1.0.10

## Правило интерфейса

Operational alerts должны попадать в **колокольчик**, а не постоянно дублироваться длинными сообщениями внутри рабочих карточек.

В карточках остаются:

- фактические значения/статусы;
- краткий feedback сразу после нажатия кнопки;
- ошибки валидации пользовательского ввода.

Длительные состояния, предупреждения и результаты фоновых/root-операций идут в центр уведомлений.

## Источники 1.0.10

`/api/notifications` агрегирует:

- Network apply / rollback / rejected;
- Market lifecycle;
- DHCP configuration/service;
- лицензирование;
- Control Center updates;
- OS/package updates;
- Web runtime: порт, HTTP/HTTPS, certificate apply/rollback;
- PostgreSQL unavailable/degraded;
- переименование компьютера;
- Samba AD-DC readiness.

Market history дополнительно сохраняется в:

```text
/var/lib/control-center-system/market-events.jsonl
```

## PostgreSQL unavailable

Если PostgreSQL недоступен, уведомление `PostgreSQL unavailable` всё равно появляется через degraded aggregation.

В этот момент read/unread не может надёжно сохраняться server-side, однако сами operational alerts остаются видимыми. После восстановления PostgreSQL новые события снова синхронизируются в:

```text
control_center.notification_events
```

## Web runtime

После применения 80/443/custom port/SSL root helper пишет:

```text
/var/lib/control-center-system/web-status.json
```

Состояния `applied`, `rollback`, `rejected`, `error` конвертируются в события колокольчика.

При недоступной PostgreSQL Web runtime может успешно примениться; пользователь получает отдельное уведомление о degraded DB sync, а не откат порта.

## Hostname

Результат переименования хранится в:

```text
/var/lib/control-center-system/hostname-status.json
```

`applied` создаёт успешное событие, `rollback/rejected/error` — ошибку.

## Samba AD-DC readiness

После проверки readiness:

- blockers → error;
- только warnings → info;
- readiness без blocker/warning → ok.

Сам provisioning в 1.0.10 отключён, поэтому уведомление readiness не означает, что домен уже создан.

## Цвет колокольчика

- **красный** — непрочитанный `severity=error`;
- **зелёный** — непрочитанные события без ошибок;
- **нейтральный** — всё прочитано или событий нет.

## API

```text
GET  /api/notifications
POST /api/notifications/read
```

Пример:

```bash
curl -fsS http://127.0.0.1:PORT/api/notifications | python3 -m json.tool
```

Отметить все:

```bash
curl -fsS -X POST -H 'Content-Type: application/json' \
  -d '{"all":true}' \
  http://127.0.0.1:PORT/api/notifications/read
```

## Диагностика

```bash
sudo tail -n 50 /var/lib/control-center-system/market-events.jsonl 2>/dev/null || true
sudo cat /var/lib/control-center-system/web-status.json 2>/dev/null || true
sudo cat /var/lib/control-center-system/hostname-status.json 2>/dev/null || true
sudo cat /var/lib/control-center-system/samba-readiness.json 2>/dev/null || true
sudo -u control-center psql -d control_center -c \
  'select source,title,state,severity,is_read,last_seen_at,message from control_center.notification_events order by last_seen_at desc limit 50;'
```
