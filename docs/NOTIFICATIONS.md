# Центр уведомлений Control Center 1.0.7

## Назначение

Колокольчик в верхней панели агрегирует состояния основных операций Control Center.

Источники:

- Сеть — protected `network-status.json`;
- Маркет — `market-status.json`;
- DHCP apply — `dhcp-status.json`;
- фактический статус DHCP service;
- Professional activation — `license-status.json`;
- обновление Control Center — `update-status.json`;
- обновление ОС/пакетов — `os-update-status.json`;
- смена Web-порта — `web-status.json`.

Observed status сначала формируется из фактического/system state, затем синхронизируется в PostgreSQL `control_center.notification_events`.

## Цвет колокольчика

- **красный** — есть непрочитанное событие `severity=error`;
- **зелёный** — есть непрочитанные события, но ошибок среди них нет;
- **нейтральный** — всё прочитано либо событий нет.

## Прочитанность 1.0.7

Read/unread перенесён из browser `localStorage` в PostgreSQL:

```text
control_center.notification_events.is_read
```

Поэтому состояние сохраняется после очистки браузера и одинаково отображается с разных административных устройств.

Поскольку встроенная пользовательская аутентификация ещё не реализована, read-state в 1.0.7 **общий для установки**, а не отдельный для каждого администратора. После появления account/session модели схема может быть расширена отдельной таблицей user notification state.

## API

Получение:

```bash
curl -fsS http://127.0.0.1:PORT/api/notifications | python3 -m json.tool
```

Прочитать одно или несколько событий:

```bash
curl -fsS -X POST -H 'Content-Type: application/json' \
  -d '{"ids":["EVENT_ID"]}' \
  http://127.0.0.1:PORT/api/notifications/read
```

Прочитать всё:

```bash
curl -fsS -X POST -H 'Content-Type: application/json' \
  -d '{"all":true}' \
  http://127.0.0.1:PORT/api/notifications/read
```

Запись содержит:

```json
{
  "id": "...",
  "source": "dhcp",
  "title": "DHCP",
  "state": "applied",
  "severity": "ok",
  "message": "DHCP конфигурация применена",
  "timestamp": 0,
  "read": false
}
```

## PostgreSQL диагностика

```bash
sudo -u control-center psql -d control_center -c \
  'select source,title,state,severity,is_read,last_seen_at from control_center.notification_events order by last_seen_at desc limit 30;'
```

Удаление/архивирование старой истории в 1.0.7 автоматически ещё не выполняется; retention policy следует добавить при росте event history в следующих релизах.
