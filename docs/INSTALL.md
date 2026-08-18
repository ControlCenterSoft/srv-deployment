# Установка Control Center 1.0.8

## Целевая платформа

Ubuntu Server 26.04 LTS, systemd, Netplan, root/sudo и доступ к APT-репозиториям. Установщик автоматически устанавливает PostgreSQL из репозитория ОС.

Web UI по умолчанию слушает TCP/8080. Пользовательский порт из `/etc/control-center/web.env` сохраняется при обновлении.

## Установка

```bash
git clone --depth 1 --branch release/1.0.8 https://github.com/filosoff31/srv-deployment.git
cd srv-deployment
sudo bash install/install.sh
```

После чистой установки:

```text
http://IP_СЕРВЕРА:8080
```

## Что добавляет installer 1.0.8

Помимо PostgreSQL/Web/runtime архитектуры 1.0.7 installer включает:

- Market lifecycle 1.0.8;
- persistent service status/event history;
- исправленный DHCP installer;
- `control-center-update-now.path` для ручной установки обнаруженного обновления;
- сохранение зрелого version/build-aware updater с PostgreSQL rollback.

## PostgreSQL

Installer:

1. устанавливает `postgresql` и `postgresql-client`;
2. запускает локальный PostgreSQL;
3. создаёт непривилегированную роль `control-center`;
4. создаёт БД `control_center`, owner `control-center`;
5. проверяет local peer authentication;
6. создаёт Python venv с Psycopg 3;
7. применяет versioned SQL migrations;
8. выполняет DB health-check.

Runtime DSN:

```text
dbname=control_center user=control-center host=/var/run/postgresql
```

Пароль PostgreSQL в приложении не хранится. Внешний PostgreSQL listener installer не включает.

## State

```text
/var/lib/control-center
/var/lib/control-center-system
/var/lib/control-center-root
/var/lib/control-center-license
PostgreSQL database: control_center
```

Market 1.0.8 дополнительно использует:

```text
/var/lib/control-center-system/market-status.json
/var/lib/control-center-system/market-events.jsonl
/var/lib/control-center-system/market-last.log
```

## Проверка после установки

```bash
cat /opt/control-center/VERSION
cat /opt/control-center/BUILD
PORT=$(sed -n 's/^CONTROL_CENTER_PORT=//p' /etc/control-center/web.env)
curl -fsS "http://127.0.0.1:${PORT}/api/health" | python3 -m json.tool
curl -fsS "http://127.0.0.1:${PORT}/api/database/status" | python3 -m json.tool
curl -fsS "http://127.0.0.1:${PORT}/api/market" | python3 -m json.tool
curl -fsS "http://127.0.0.1:${PORT}/api/settings/update/check" | python3 -m json.tool
systemctl status control-center-update-now.path --no-pager
```

Ожидаемые version/build:

```text
1.0.8
20260819.1
```

## Acceptance

```bash
sudo bash scripts/acceptance-1.0.8.sh
```

Acceptance не устанавливает/удаляет DHCP. Реальный install/remove lifecycle отдельно проверяется в GitHub Actions release validation.

## Удаление

```bash
sudo bash install/uninstall.sh
```

С сохранением application state, PostgreSQL database и service identity:

```bash
sudo bash install/uninstall.sh --keep-data
```

1.0.8 uninstall также удаляет manual update path watcher и internal updater compatibility copy.

## Диагностика

```bash
journalctl -u control-center -n 200 --no-pager
journalctl -u control-center-market-apply.service -n 200 --no-pager
journalctl -u control-center-update.service -n 200 --no-pager
sudo tail -n 100 /var/lib/control-center-system/market-last.log 2>/dev/null || true
```

См. `docs/MARKET.md`, `docs/DHCP.md`, `docs/UPDATE.md`, `docs/POSTGRESQL.md`, `docs/WEB-PORT.md` и `docs/TROUBLESHOOTING.md`.
