# Обновление Control Center 1.0.5

## Архитектура

Web UI не запускает root-команды. Раздел **Настройки** записывает параметры в `/var/lib/control-center/update-settings.json`. Привилегированную проверку и установку выполняет `control-center-update.service`, запускаемый `control-center-update.timer`.

Статус updater хранится в защищённом system-state:

```text
/var/lib/control-center-system/update-status.json
```

Rollback приложения хранится в root-only state:

```text
/var/lib/control-center-root/rollback-<version>-<timestamp>/
```

## Настройки

- автоматическое обновление Control Center on/off;
- интервал от **5 до 10080 минут**;
- production-канал;
- ручная проверка доступной версии.

```json
{
  "automatic_updates": true,
  "interval_minutes": 60,
  "channel": "production"
}
```

Timer запускает worker раз в минуту, но GitHub проверяется только после истечения `interval_minutes`.

## Алгоритм

1. Получить production `deployment.json` из `main`.
2. Проверить канал и формат semver.
3. Сравнить с `/opt/control-center/VERSION` через `dpkg --compare-versions`.
4. Клонировать `release/<version>`.
5. Проверить обязательные payload-файлы.
6. Сверить `APP_VERSION` с metadata.
7. Создать root-only rollback-копию.
8. Запустить install script нового релиза.
9. Выполнить health-check.
10. При ошибке восстановить предыдущие приложение и systemd unit.

## Исправление аудита 1.0.5

Старый updater использовал слишком жёсткий шаблон строки `APP_VERSION`. Исправленная версия допускает пробелы вокруг `=`. Сам 1.0.5 также оформлен совместимо со старым parser, чтобы переход с 1.0.4 не блокировался.

Если уже установлен ранний updater, который отклоняет 1.0.5, один раз выполните ручную установку актуальной `release/1.0.5`; последующие релизы будут обрабатываться исправленным updater.

## Диагностика

```bash
systemctl status control-center-update.timer --no-pager
systemctl status control-center-update.service --no-pager
journalctl -u control-center-update.service -n 200 --no-pager
cat /var/lib/control-center/update-settings.json
sudo cat /var/lib/control-center-system/update-status.json
cat /opt/control-center/VERSION
sudo ls -ld /var/lib/control-center-root/rollback-* 2>/dev/null || true
```

Ручной запуск worker:

```bash
sudo systemctl start control-center-update.service
sudo journalctl -u control-center-update.service -n 100 --no-pager
```

## Важно

Обновление Control Center и обновление системных пакетов — независимые механизмы. Обновление ОС/пакетов описано в `docs/OS_UPDATES.md`.
