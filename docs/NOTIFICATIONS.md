# Центр уведомлений — Control Center 1.0.11

Operational alerts отображаются в **колокольчике**. Рабочие карточки показывают состояние и краткий feedback текущего действия, а длительные фоновые/root события сохраняются в notification center.

## Источники

`/api/notifications` агрегирует:

- Network apply / rollback / rejected;
- Market lifecycle;
- DHCP configuration/service;
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

## PostgreSQL

При доступной БД read/unread и events сохраняются server-side. При DB outage Control Center остаётся в degraded notification mode и не должен скрывать operational failures.

## API

```text
GET  /api/notifications
POST /api/notifications/read
```

## Диагностика

```bash
curl -fsS http://127.0.0.1:8080/api/notifications | python3 -m json.tool
sudo cat /var/lib/control-center-system/samba-status.json 2>/dev/null || true
sudo tail -n 100 /var/lib/control-center-system/samba-last.log 2>/dev/null || true
sudo tail -n 100 /var/lib/control-center-system/market-events.jsonl 2>/dev/null || true
sudo -u control-center psql -d control_center -c \
  'select source,title,state,severity,is_read,last_seen_at,message from control_center.notification_events order by last_seen_at desc limit 50;'
```
