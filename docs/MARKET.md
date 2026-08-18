# Маркет и жизненный цикл сервисов — Control Center 1.0.8

## Постоянные статусы

Карточка каждого сервиса содержит server-side статус в верхней правой части. Статус не хранится в DOM браузера и не сбрасывается после обновления страницы.

Для DHCP используются:

- `installing` → **Установка…**;
- `running` → **Работает**;
- `error` → **Ошибка**;
- `available` → **Не установлен**;
- `removing` → **Удаление…**.

Запланированные сервисы имеют `planned` → **Запланировано**.

`GET /api/market` возвращает для каждой карточки:

```json
{
  "id": "dhcp",
  "state": "installed",
  "status": {
    "code": "running",
    "label": "Работает",
    "detail": "DHCP Server установлен и готов к настройке.",
    "timestamp": 0
  }
}
```

`detail` используется как tooltip. Для ошибки там хранится диагностическая причина root worker.

## Protected state

```text
/var/lib/control-center-system/market-status.json
/var/lib/control-center-system/market-events.jsonl
/var/lib/control-center-system/market-last.log
/var/lib/control-center-system/modules/<module>.json
```

`market-status.json` — последнее состояние операции. `market-events.jsonl` — последние 200 start/success/failure событий. `market-last.log` — вывод последнего root worker.

## Уведомления

Market events импортируются `/api/notifications` в PostgreSQL. Начало и завершение — разные события, поэтому быстро завершившаяся установка не теряет notification `Установка началась`.

## DHCP

DHCP остаётся первым реально installable модулем Маркета. Подробности безопасной установки и восстановления — `DHCP.md`.
