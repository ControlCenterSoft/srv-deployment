# Установка SRV Control Center

## Чистая машина

Поддерживается Debian/Ubuntu с `apt-get` и systemd. Clean installer предназначен для машины, где `/opt/srv-control` ещё не содержит установленный Control Center.

```bash
curl -fL -o install.sh \
  https://raw.githubusercontent.com/filosoff31/srv-deployment/main/install.sh
chmod +x install.sh
sudo ./install.sh
```

Bootstrap скачивает актуальный `main`. `installer/install.sh` читает `deployment.json`, поэтому устанавливается полный payload активного `releases/<version>/payload`.

Установщик создаёт PostgreSQL role/database, Python virtualenv, применяет Alembic migrations, устанавливает `srv-control.service`, Nginx, system helpers активного релиза и GitHub updater. Если TCP/80 уже занят, reverse proxy выбирает свободный резервный порт из поддерживаемых installer вариантов.

## Авторизация 1.1.0

В 1.1.0 отдельная пользовательская база Control Center не создаётся. Вход использует системный PAM/NSS:

- локальные Linux-учётные записи входят своим системным паролем;
- при настроенной доменной интеграции доступны доменные учётные записи через системный PAM/NSS;
- root и пользователи серверных административных групп получают полный доступ;
- остальные права определяются RBAC-группами Control Center;
- пользовательские пароли не записываются в БД Control Center или state-файлы.

При наличии Samba AD DC установщик создаёт/экспортирует HTTP Kerberos keytab и добавляет SPNEGO location в Nginx. Доменный клиент, способный получить Kerberos ticket для HTTP/FQDN сервера, использует SSO. Если SSO не сработал, остаётся интерактивный вход доменной учётной записью.

Страница «Права пользователей» читает локальные данные через NSS и доменный каталог через доступные server-domain tools; она не создаёт отдельные учётные записи Control Center.

## Основные пути

```text
/opt/srv-control                         приложение
/etc/srv-control/control.toml            конфигурация
/etc/pam.d/srv-control                    PAM service
/var/lib/srv-control                     состояние Control Center
/var/lib/srv-control/backups             резервные копии
/var/lib/srv-control/session.key          ключ web-сессий
/var/lib/srv-control/http.keytab          HTTP keytab SSO при наличии
/var/lib/srv-deployment                  deployment state и rollback backups
/var/lib/srvcc-agent/deploy-repo         checkout GitHub main
/var/lib/srvcc-agent/last-deployed-sha   последний product deployment
/var/lib/srvcc-agent/last-seen-sha       последний проверенный main
/var/lib/srvcc-agent/last-release-fingerprint
/var/log/srvcc-agent.log                 журнал updater
```

## GitHub updates

Режим обновления настраивается из «Система» или командой:

```bash
sudo /usr/local/sbin/srvcc-configure-auto-updates \
  --repo https://github.com/filosoff31/srv-deployment.git \
  --mode automatic \
  --interval-minutes 5
```

Ручная проверка без применения:

```bash
sudo /usr/local/sbin/srvcc-github-agent check --actor root
```

Применение доступного product release:

```bash
sudo /usr/local/sbin/srvcc-github-agent apply --actor root
```

Если включена политика backup-before-update, updater сначала создаёт резервную копию и блокирует deployment при ошибке backup.

Полное описание: `docs/AUTO-UPDATES.md`.

## Проверка установки

```bash
systemctl status srv-control.service --no-pager -l
systemctl status srvcc-github-agent.timer --no-pager -l
curl -fsS http://127.0.0.1:8876/api/v1/health
cat /var/lib/srv-control/github-update-config.json
cat /var/lib/srv-control/github-update-status.json
```

Для 1.1.0 дополнительно:

```bash
getent passwd root
pamtester srv-control <local-user> authenticate acct_mgmt
systemctl status srv-control-system-agent.path --no-pager -l
ls -ld /var/lib/srv-control/backups
```

При настроенном AD/SPNEGO:

```bash
klist -k /var/lib/srv-control/http.keytab
nginx -T | grep -A8 -B2 'auth_gss on'
```

## Повторный clean install

Clean installer намеренно не перезаписывает существующий `/opt/srv-control`. Для установленной системы используется product updater. Полная destructive reinstall выполняется только отдельным явно подтверждаемым reinstall-процессом.

## server-state

`main` доступен для чтения без встроенного GitHub-секрета. Публикация фактического состояния в `server-state` требует отдельного write credential и не встраивается в публичный installer.
