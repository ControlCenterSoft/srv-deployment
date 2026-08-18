# Центр уведомлений — Control Center 1.0.8

## Назначение

Колокольчик агрегирует состояния сети, сервисов, лицензии, обновлений Control Center/ОС и смены Web-порта. Read/unread хранится server-side в PostgreSQL `control_center.notification_events`.

## Market lifecycle events 1.0.8

Установка/удаление сервиса теперь записывается не только как последнее состояние, а как история отдельных событий в protected journal:

```text
/var/lib/control-center-system/market-events.jsonl
```

Для DHCP сохраняются:

- start — например `Установка началась: DHCP Server`;
- success — `Установка успешно завершена: DHCP Server`;
- failure — сообщение об ошибке + diagnostic detail root worker.

У каждого события есть server timestamp. `/api/notifications` импортирует журнал в PostgreSQL, поэтому быстро завершившаяся установка не теряет событие «началась» и история сохраняется после обновления страницы.

## Цвет колокольчика

- **красный** — есть непрочитанное `severity=error`;
- **зелёный** — есть непрочитанные события без ошибок;
- **нейтральный** — всё прочитано либо событий нет.

## Прочитанность

```text
control_center.notification_events.is_read
```

Read-state общий для текущей установки Control Center, пока не реализована встроенная пользовательская authentication/session модель.

## API

Получить события:

```bash
curl -fsS http://127.0.0.1:PORT/api/notifications | python3 -m json.tool
```

Отметить выбранные:

```bash
curl -fsS -X POST -H 'Content-Type: application/json' \
  -d '{"ids":["EVENT_ID"]}' \
  http://127.0.0.1:PORT/api/notifications/read
```

Отметить все:

```bash
curl -fsS -X POST -H 'Content-Type: application/json' \
  -d '{"all":true}' \
  http://127.0.0.1:PORT/api/notifications/read
```

## Диагностика

```bash
sudo tail -n 50 /var/lib/control-center-system/market-events.jsonl
sudo -u control-center psql -d control_center -c \
  'select source,title,state,severity,is_read,last_seen_at,message from control_center.notification_events order by last_seen_at desc limit 50;'
```

Если PostgreSQL временно недоступен, API использует degraded aggregation; после восстановления БД Market events снова синхронизируются в PostgreSQL.
