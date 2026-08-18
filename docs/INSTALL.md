# Установка Control Center 1.0.7

## Целевая платформа

Ubuntu Server 26.04 LTS, systemd, Netplan, root/sudo и доступ к APT-репозиториям. Установщик автоматически устанавливает PostgreSQL из репозитория ОС.

Web UI по умолчанию слушает TCP/8080, но начиная с 1.0.7 порт можно изменить в **Настройки → Web-панель**.

## Установка

```bash
git clone --depth 1 --branch release/1.0.7 https://github.com/filosoff31/srv-deployment.git
cd srv-deployment
sudo bash install/install.sh
```

После чистой установки:

```text
http://IP_СЕРВЕРА:8080
```

При обновлении существующей 1.0.7+ установки текущий порт берётся из `/etc/control-center/web.env` и сохраняется.

## PostgreSQL

Installer:

1. устанавливает `postgresql` и `postgresql-client`;
2. запускает локальный PostgreSQL;
3. создаёт непривилегированную роль `control-center`;
4. создаёт БД `control_center`, owner `control-center`;
5. проверяет локальное peer authentication от Linux УЗ `control-center`;
6. создаёт Python venv с Psycopg 3;
7. применяет versioned SQL migrations;
8. выполняет DB health-check до запуска релиза.

Runtime DSN:

```text
dbname=control_center user=control-center host=/var/run/postgresql
```

Он записывается в `/etc/control-center/database.env` с правами root:root `0600`. Пароля PostgreSQL в приложении нет.

Установщик не включает внешнее прослушивание PostgreSQL и не настраивает межузловой кластер в 1.0.7.

## Состояние

Сохраняются существующие каталоги:

```text
/var/lib/control-center
/var/lib/control-center-system
/var/lib/control-center-root
/var/lib/control-center-license
```

и новая application database:

```text
PostgreSQL database: control_center
```

`--keep-data` сохраняет БД, state и Linux service identity.

## Live configuration read access

Web service по-прежнему имеет только чтение фактических конфигураций:

```text
/etc/netplan/90-control-center.yaml
/etc/dnsmasq.d/control-center-dhcp.conf
```

Запись выполняют root helpers. PostgreSQL не заменяет Netplan/dnsmasq/systemd как источник фактического состояния ОС.

## Web runtime

```text
Gunicorn -> wsgi:app -> Flask application -> Psycopg -> PostgreSQL
```

Systemd читает:

```text
/etc/control-center/database.env
/etc/control-center/web.env
```

Gunicorn bind использует `${CONTROL_CENTER_PORT}`.

## Проверка после установки

```bash
cat /opt/control-center/VERSION
cat /opt/control-center/BUILD
cat /etc/control-center/web.env
PORT=$(sed -n 's/^CONTROL_CENTER_PORT=//p' /etc/control-center/web.env)
curl -fsS "http://127.0.0.1:${PORT}/api/health" | python3 -m json.tool
curl -fsS "http://127.0.0.1:${PORT}/api/database/status" | python3 -m json.tool
systemctl status postgresql --no-pager
systemctl status control-center --no-pager
```

Ожидаемая версия/build:

```text
1.0.7
20260818.2
```

## Acceptance

```bash
sudo bash scripts/acceptance-1.0.7.sh
```

Проверка не меняет конфигурацию. Она тестирует PostgreSQL peer connection/schema migration, database API, version/build, Web port, Gunicorn/systemd wiring, notifications, network inventory и DHCP при установленном модуле.

## Удаление

Полное:

```bash
sudo bash install/uninstall.sh
```

Полное удаление удаляет **только** БД `control_center` и роль PostgreSQL `control-center`, созданные продуктом. Пакет/служба PostgreSQL не удаляются, чтобы не повредить другие приложения сервера.

С сохранением application state, PostgreSQL database и service identity:

```bash
sudo bash install/uninstall.sh --keep-data
```

## Диагностика

```bash
PORT=$(sed -n 's/^CONTROL_CENTER_PORT=//p' /etc/control-center/web.env)
journalctl -u control-center -n 200 --no-pager
journalctl -u postgresql -n 100 --no-pager
ss -ltnp | grep ":${PORT}"
sudo -u control-center psql -d control_center -c 'select current_user, current_database();'
```

См. `docs/POSTGRESQL.md`, `docs/WEB-PORT.md` и `docs/TROUBLESHOOTING.md`.
