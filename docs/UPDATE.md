# Обновление Control Center 1.0.7

## Архитектура

Web UI не запускает installer от root. Проверку и установку выполняет `control-center-update.service`, запускаемый `control-center-update.timer`.

Настройки хранятся в PostgreSQL `control_center.settings`; compatibility mirror `/var/lib/control-center/update-settings.json` остаётся для root updater.

Результат worker:

```text
/var/lib/control-center-system/update-status.json
```

Rollback directory:

```text
/var/lib/control-center-root/rollback-<version>-<build>-<timestamp>/
```

Он может содержать application payload, systemd unit, `web.env`, `database.env` и PostgreSQL `pg_dump`.

## Version + build

Updater сравнивает и `release`, и `build`. Обновление требуется, если remote version выше либо version совпадает, но build отличается от `/opt/control-center/BUILD`.

Payload проверяется по `app/release.json` и `APP_VERSION` в `app/main.py`.

## PostgreSQL migrations

Installer запускает `app/db_migrate.py`. Migration выполняется транзакционно и регистрируется в `control_center.schema_migrations` вместе с SHA-256 checksum. Изменение уже применённого migration под прежним номером запрещено checksum-контролем.

## PostgreSQL rollback

Если перед обновлением БД `control_center` уже существует, updater **до запуска installer** создаёт:

```text
control-center-db.dump
```

формата `pg_dump -Fc` внутри root-only rollback directory.

Если installer нового релиза завершается ошибкой, updater:

1. останавливает новый Web runtime;
2. восстанавливает предыдущий application payload/systemd unit/Web env;
3. завершает соединения с изменённой БД;
4. пересоздаёт `control_center` с владельцем `control-center`;
5. выполняет `pg_restore` предыдущего dump;
6. запускает прежний Control Center.

Если PostgreSQL до обновления вообще не существовал, а неудачный installer создал БД/роль впервые, rollback удаляет созданную БД и, когда это была новая роль, роль `control-center`, возвращая состояние ближе к исходной 1.0.6.

Невозможность создать `pg_dump` **блокирует обновление до запуска installer** — обновление без DB backup не продолжается.

## Сохранение Web-порта

Updater/installer сохраняют `/etc/control-center/web.env`, поэтому выбранный порт сохраняется между релизами. При rollback возвращается прежний `web.env`.

## Алгоритм

1. Получить production `deployment.json`.
2. Проверить `channel`, `release`, `build`, `release_branch`.
3. Сравнить remote version/build с текущими VERSION/BUILD.
4. Клонировать точно указанную release branch.
5. Проверить payload metadata.
6. Создать root-only application backup и PostgreSQL dump, если БД уже существует.
7. Запустить installer.
8. Installer проверяет PostgreSQL, применяет migrations и запускает Web service на сохранённом порту.
9. Installer проверяет `/api/health` и `/api/database/status`.
10. При ошибке восстановить приложение, Web config и PostgreSQL state.

## Настройки

- automatic update on/off;
- interval 5–10080 минут;
- production channel.

## Диагностика

```bash
systemctl status control-center-update.timer --no-pager
journalctl -u control-center-update.service -n 200 --no-pager
cat /opt/control-center/VERSION
cat /opt/control-center/BUILD
sudo -u control-center psql -d control_center -c 'select * from control_center.schema_migrations order by version;'
sudo find /var/lib/control-center-root -maxdepth 2 -name 'control-center-db.dump' -ls
```

## Важно

Control Center updater и OS/package updater — независимые механизмы. Автоматический major PostgreSQL server upgrade между несовместимыми PostgreSQL major versions в 1.0.7 отдельно не реализован.
