# Автоматическое обновление Control Center 1.0.1

## Архитектура

Web UI не выполняет root-команды. Раздел **Настройки** сохраняет только разрешенные параметры в `/var/lib/control-center/update-settings.json`.

Привилегированную часть выполняет `control-center-update.service`, запускаемый `control-center-update.timer`.

## Настройки

В Web UI доступны:

- включить/выключить автоматические обновления;
- периодичность: каждый час, раз в день, раз в неделю;
- канал: Production.

## Алгоритм обновления

1. Проверить `deployment.json` в production.
2. Сравнить доступную версию с `/opt/control-center/VERSION`.
3. Получить ветку `release/<version>`.
4. Проверить наличие установщика и соответствие версии payload.
5. Создать rollback-копию текущего приложения и systemd unit.
6. Запустить установщик нового релиза.
7. Проверить health endpoint.
8. При успехе сохранить статус обновления.
9. При ошибке восстановить предыдущую версию и перезапустить службу.

## Диагностика

```bash
systemctl status control-center-update.timer --no-pager
systemctl status control-center-update.service --no-pager
journalctl -u control-center-update.service -n 200 --no-pager
cat /var/lib/control-center/update-settings.json
cat /var/lib/control-center/update-status.json
```

Для ручного запуска root-проверки:

```bash
sudo systemctl start control-center-update.service
```
