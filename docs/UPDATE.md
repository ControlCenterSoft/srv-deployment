# Обновление Control Center 1.0.7

## Архитектура

Web UI не запускает installer от root. Проверку и установку выполняет `control-center-update.service`, запускаемый `control-center-update.timer`.

Настройки 1.0.7 хранятся в PostgreSQL `control_center.settings`. Для совместимости с root updater Web API одновременно поддерживает mirror:

```text
/var/lib/control-center/update-settings.json
```

Результат worker:

```text
/var/lib/control-center-system/update-status.json
```

Rollback приложения:

```text
/var/lib/control-center-root/rollback-<version>-<build>-<timestamp>/
```

## Version + build

Updater 1.0.7 сравнивает не только `release`, но и `build`.

Обновление требуется, если:

1. remote `release` выше установленного; или
2. `release` одинаковый, но remote `build` отличается от `/opt/control-center/BUILD`.

Это позволяет выпускать исправленную build-ревизию внутри одного production-релиза без искусственного изменения semver.

Payload дополнительно проверяется по:

```text
app/release.json
APP_VERSION в app/main.py
```

## PostgreSQL migrations

Installer каждого нового релиза запускает `app/db_migrate.py`. Migration выполняется транзакционно и регистрируется в `control_center.schema_migrations` вместе с SHA-256 checksum.

Уже применённый migration-файл нельзя изменять под прежним номером. Новое изменение схемы должно получать новый migration.

В 1.0.7 PostgreSQL впервые создаётся при переходе с 1.0.6. Существующие Linux/Netplan/DHCP параметры не удаляются; installer bootstrap переносит application-level значения в новую БД и оставляет compatibility state для root workers.

## Сохранение Web-порта

Updater/installer сохраняют текущий `/etc/control-center/web.env`. Поэтому после обновления Control Center продолжает слушать выбранный пользователем порт.

При rollback приложения updater также восстанавливает сохранённый `web.env`.

## Алгоритм

1. Получить production `deployment.json`.
2. Проверить `channel`, `release`, `build`, `release_branch`.
3. Сравнить remote version/build с `/opt/control-center/VERSION` и `/opt/control-center/BUILD`.
4. Клонировать точно указанную `release_branch`.
5. Проверить `app/release.json` и `APP_VERSION`.
6. Создать root-only application rollback.
7. Запустить installer.
8. Installer проверяет PostgreSQL, применяет migrations и запускает Web service на сохранённом порту.
9. Installer проверяет `/api/health` и `/api/database/status`.
10. При ошибке updater восстанавливает предыдущий application payload/systemd unit/web.env.

## Настройки

- automatic update on/off;
- interval 5–10080 минут;
- production channel.

## Диагностика

```bash
systemctl status control-center-update.timer --no-pager
systemctl status control-center-update.service --no-pager
journalctl -u control-center-update.service -n 200 --no-pager
cat /opt/control-center/VERSION
cat /opt/control-center/BUILD
sudo -u control-center psql -d control_center -c 'select * from control_center.schema_migrations order by version;'
PORT=$(sed -n 's/^CONTROL_CENTER_PORT=//p' /etc/control-center/web.env)
curl -fsS "http://127.0.0.1:${PORT}/api/health" | python3 -m json.tool
```

## Важно

Control Center updater и OS/package updater — независимые механизмы. PostgreSQL package также обновляется обычным системным package manager в рамках поддерживаемой версии ОС; автоматический major PostgreSQL migration между несовместимыми server majors в 1.0.7 отдельно не реализован.
