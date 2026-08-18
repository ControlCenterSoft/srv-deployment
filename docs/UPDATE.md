# Обновление Control Center 1.0.6

## Архитектура

Web UI не запускает root-команды. Раздел **Настройки** хранит разрешённые параметры в `/var/lib/control-center/update-settings.json`. Проверку и установку выполняет `control-center-update.service`, запускаемый `control-center-update.timer`.

Результат worker хранится в защищённом state:

```text
/var/lib/control-center-system/update-status.json
```

Rollback приложения:

```text
/var/lib/control-center-root/rollback-<version>-<timestamp>/
```

## Настройки

- автоматическое обновление on/off;
- интервал 5–10080 минут;
- production channel;
- ручная проверка доступного релиза.

```json
{
  "automatic_updates": true,
  "interval_minutes": 60,
  "channel": "production"
}
```

Timer запускает лёгкий worker раз в минуту, но обращение к metadata выполняется только после истечения выбранного интервала.

## Metadata 1.0.6

`deployment.json` содержит и семантическую версию, и идентификатор сборки:

```json
{
  "release": "1.0.6",
  "build": "20260818.1",
  "channel": "production",
  "release_branch": "release/1.0.6"
}
```

Текущий updater принимает решение о переходе между релизами по semver `release`; `build` отображается в UI/API для точной идентификации установленной сборки.

## Алгоритм обновления

1. Получить production `deployment.json` из `main`.
2. Проверить канал и формат версии.
3. Сравнить `release` с `/opt/control-center/VERSION` через `dpkg --compare-versions`.
4. Клонировать `release/<version>`.
5. Проверить обязательные payload-файлы.
6. Сверить `APP_VERSION` с metadata.
7. Создать root-only rollback-копию.
8. Запустить installer нового релиза.
9. Installer выполняет health-check и проверяет, что API сообщает ожидаемую версию.
10. При ошибке восстановить предыдущие приложение и systemd unit.

## Переход 1.0.5 → 1.0.6

1.0.6 создана непосредственно от аудированной `release/1.0.5`, поэтому сохраняет protected-state, licensing, DHCP ownership/runtime и rollback архитектуру 1.0.5.

После обновления существующие применённые сетевые и DHCP параметры сохраняются и дополнительно считываются из фактических Control Center-managed Netplan/dnsmasq файлов.

## Диагностика

```bash
systemctl status control-center-update.timer --no-pager
systemctl status control-center-update.service --no-pager
journalctl -u control-center-update.service -n 200 --no-pager
cat /var/lib/control-center/update-settings.json
sudo cat /var/lib/control-center-system/update-status.json
cat /opt/control-center/VERSION
curl -fsS http://127.0.0.1:8080/api/health | python3 -m json.tool
sudo ls -ld /var/lib/control-center-root/rollback-* 2>/dev/null || true
```

## Важно

Обновление Control Center и обновление системных пакетов — независимые механизмы. Обновление ОС/пакетов описано в `docs/OS_UPDATES.md`.
