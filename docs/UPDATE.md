# Обновление Control Center 1.0.5

## Архитектура

Web UI не запускает root-команды. Раздел **Настройки** записывает разрешённые параметры в `/var/lib/control-center/update-settings.json`. Привилегированную проверку и установку выполняет `control-center-update.service`, который запускается `control-center-update.timer`.

## Настройки

В Web UI доступны:

- включить/выключить автоматическое обновление Control Center;
- вручную задать интервал от **5 до 10080 минут**;
- выполнить проверку доступной production-версии вручную.

Формат настроек:

```json
{
  "automatic_updates": true,
  "interval_minutes": 60,
  "channel": "production"
}
```

Timer запускает лёгкий worker раз в минуту. GitHub проверяется только когда истёк `interval_minutes`.

## Алгоритм

1. Получить `deployment.json` из `main`.
2. Проверить production-канал и формат версии.
3. Сравнить версию с `/opt/control-center/VERSION` через `dpkg --compare-versions`.
4. Клонировать `release/<version>`.
5. Проверить наличие `install/install.sh` и `app/main.py`.
6. Проверить соответствие `APP_VERSION` версии релиза.
7. Создать rollback-копию текущего приложения.
8. Запустить установщик нового релиза.
9. Установщик выполняет health-check `http://127.0.0.1:8080/api/health`.
10. При ошибке восстановить предыдущую версию приложения и systemd unit.

## Исправление аудита 1.0.5

В раннем updater использовался слишком жёсткий шаблон `APP_VERSION = ...`. Из-за различий в пробелах корректная версия могла быть отклонена. В исправленной 1.0.5 проверка допускает любое количество пробелов вокруг `=`.

Для перехода с установки, где старый updater уже отклоняет 1.0.5, выполните один ручной запуск актуального bootstrap/install. После этого последующие обновления используют исправленный updater.

## Диагностика

```bash
systemctl status control-center-update.timer --no-pager
systemctl status control-center-update.service --no-pager
journalctl -u control-center-update.service -n 200 --no-pager
cat /var/lib/control-center/update-settings.json
cat /var/lib/control-center/update-status.json
cat /opt/control-center/VERSION
```

Ручной запуск root-worker:

```bash
sudo systemctl start control-center-update.service
sudo journalctl -u control-center-update.service -n 100 --no-pager
```

## Важно

Обновление Control Center и обновление системных пакетов — разные механизмы. Системные APT-обновления описаны в `docs/OS_UPDATES.md`.
