# Установка SRV Control Center 1.0.0

## Чистая машина

Поддерживается Debian/Ubuntu с `apt-get` и systemd. Инсталлятор предназначен для машины, где `/opt/srv-control` ещё не содержит установленный Control Center.

```bash
curl -fL -o install.sh \
  https://raw.githubusercontent.com/filosoff31/srv-deployment/main/install.sh
chmod +x install.sh
sudo ./install.sh
```

Bootstrap скачивает только актуальный `main`. `installer/install.sh` читает `deployment.json`, поэтому приложение устанавливается непосредственно из полного payload активного релиза `releases/<version>/payload`; отдельной копии исходников в `installer/payload` больше нет.

Инсталлятор устанавливает зависимости, PostgreSQL, Python virtualenv, migrations, `srv-control.service`, Nginx, системные helper/unit-файлы из активного релиза и release-fingerprint updater.

Если TCP/80 уже занят, reverse proxy пробует 8080, затем 8880.

## Основные пути

```text
/opt/srv-control                         приложение
/etc/srv-control/control.toml            конфигурация
/var/lib/srv-control                     состояние Control Center
/var/lib/srv-deployment                  deployment state и rollback backups
/var/lib/srvcc-agent/deploy-repo         checkout GitHub main
/var/lib/srvcc-agent/last-deployed-sha   последний product deployment
/var/lib/srvcc-agent/last-seen-sha       последний проверенный main
/var/lib/srvcc-agent/last-release-fingerprint
/var/log/srvcc-agent.log                 журнал updater
```

## Автоматические обновления

По умолчанию после чистой установки включается проверка GitHub каждые 5 минут. Updater не переустанавливает приложение только из-за нового commit: он сравнивает fingerprint активного product-релиза.

Проверка:

```bash
systemctl status srv-control.service --no-pager -l
systemctl status srvcc-github-agent.timer --no-pager -l
curl -fsS http://127.0.0.1:8876/api/v1/health
cat /var/lib/srv-control/github-update-config.json
cat /var/lib/srv-control/github-update-status.json
tail -n 100 /var/log/srvcc-agent.log
```

## Обновление существующей версии 0.8.0+

```bash
curl -fL -o /tmp/srvcc-configure-auto-updates.sh \
  https://raw.githubusercontent.com/filosoff31/srv-deployment/main/bootstrap/configure-auto-updates.sh
sudo bash /tmp/srvcc-configure-auto-updates.sh \
  --mode automatic \
  --interval-minutes 5 \
  --check-now
```

Полное описание режимов updater: `docs/AUTO-UPDATES.md`.

## Повторный запуск clean installer

Clean installer намеренно завершается с ошибкой, если `/opt/srv-control` уже содержит файлы. Для действующего сервера используется updater, а не повторная чистая установка.

## server-state

`main` доступен для чтения без встроенного GitHub-секрета. Публикация фактического состояния в `server-state` требует отдельного write credential и не встраивается в публичный installer.
