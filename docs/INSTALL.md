# Установка SRV Control Center на чистую машину

## Назначение

`install.sh` предназначен для новой Debian/Ubuntu-машины с systemd, на которой **ещё нет** `/opt/srv-control`.

Инсталлятор:

1. устанавливает системные зависимости;
2. разворачивает актуальный snapshot SRV Control Center из этого GitHub-репозитория;
3. создаёт системного пользователя `srv-control`;
4. создаёт Python virtualenv и устанавливает `requirements.lock`;
5. подготавливает PostgreSQL role/database и применяет Alembic migrations;
6. устанавливает и запускает `srv-control.service`;
7. настраивает Nginx reverse proxy;
8. записывает release/deployment metadata;
9. устанавливает `srvcc-github-agent.timer`, который примерно каждые 2 минуты проверяет `main` и применяет новые релизы;
10. выполняет финальный health/acceptance test.

## Требования

- Debian или Ubuntu с `apt-get`;
- systemd;
- доступ в Интернет к GitHub и APT-репозиториям;
- root/sudo;
- машина не должна содержать существующий `/opt/srv-control`.

## Рекомендуемый запуск

```bash
curl -fL -o install.sh \
  https://raw.githubusercontent.com/filosoff31/srv-deployment/main/install.sh

chmod +x install.sh

sudo ./install.sh
```

Альтернативно:

```bash
wget -O install.sh \
  https://raw.githubusercontent.com/filosoff31/srv-deployment/main/install.sh

chmod +x install.sh
sudo ./install.sh
```

В конце успешной установки будет выведено:

```text
SRV CONTROL CENTER: INSTALLED
release=...
git_sha=...
url=http://...
updater=srvcc-github-agent.timer
install_log=/var/log/srv-control-install.log
```

Если TCP/80 уже занят, инсталлятор автоматически попробует 8080, затем 8880.

## Основные пути

```text
/opt/srv-control                     приложение
/etc/srv-control/control.toml        конфигурация
/var/lib/srv-control                 runtime metadata/state
/var/log/srv-control                 журналы приложения
/var/cache/srv-control               cache
/var/lib/srv-deployment              deployment state/backups
/var/lib/srvcc-agent/deploy-repo     checkout GitHub main
/var/log/srvcc-agent.log             updater log
```

## Проверка после установки

```bash
systemctl status srv-control.service --no-pager -l
systemctl status srvcc-github-agent.timer --no-pager -l
curl -fsS http://127.0.0.1:8876/api/v1/health
tail -n 100 /var/log/srvcc-agent.log
```

## Автоматические обновления

`main` является authoritative deployment branch. Timer получает новый commit, запускает:

```text
deploy/deploy.sh
  → deploy/orchestrator.sh
    → preflight
    → apply
    → acceptance
    → deploy/healthcheck.sh
```

`last-deployed-sha` обновляется только после успешного release acceptance и общего healthcheck.

Начиная с 0.4.0 code-only обновления должны использовать graceful worker rotation (`deploy/reload-srv-control.sh`), чтобы не останавливать listener Uvicorn во время обновления.

## Ветка server-state

Чистая установка может **читать public `main` без GitHub credentials**, поэтому установка и автоматические обновления работают сразу.

Публикация обратно в `server-state` требует write-credential GitHub (PAT/deploy key/GitHub App credential). Секрет намеренно не встроен в публичный installer и репозиторий. На основном SRV уже используется отдельный state publisher; для новой машины его write-доступ настраивается отдельно.

## Повторный запуск

Инсталлятор намеренно остановится, если `/opt/srv-control` уже содержит файлы. Это защита от случайной перезаписи рабочей установки. Для действующего сервера используются обычные releases через `main`.
