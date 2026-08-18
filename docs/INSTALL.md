# Установка Control Center

## Чистая машина

Clean installer предназначен для поддерживаемой Debian/Ubuntu-системы с `apt-get` и systemd, где `/opt/srv-control` ещё не содержит установленный Control Center.

```bash
curl -fL -o install.sh \
  https://raw.githubusercontent.com/filosoff31/srv-deployment/main/install.sh
chmod +x install.sh
sudo ./install.sh
```

Bootstrap получает актуальный `main`. `installer/install.sh` читает `deployment.json`, поэтому устанавливается self-contained payload активного `releases/<version>`.

Перед установкой проверьте сеть, DNS, время, доступ к GitHub, свободное место и наличие root/sudo. При миграции существующего сервера предварительно создайте независимую резервную копию важных данных.

Установщик создаёт/настраивает PostgreSQL role/database, Python virtualenv, Alembic migrations, `srv-control.service`, reverse proxy, system helpers активного release и GitHub updater согласно фактической release implementation.

## Аутентификация после установки

Современная production-линия не создаёт отдельную базу web-паролей Control Center и не требует bootstrap web-user `admin`.

Вход использует системную identity chain:

- локальные Linux-учётные записи через NSS/PAM;
- доменные учётные записи через Samba/winbind + NSS/PAM;
- Kerberos/SPNEGO SSO при корректной доменной конфигурации;
- RBAC Control Center после успешной authentication.

Первый вход выполняется существующей локальной или доменной учётной записью с необходимыми правами.

При наличии Samba AD DC release installation может настраивать HTTP Kerberos keytab/SPNEGO integration. Если SSO недоступен, интерактивный PAM/winbind login остаётся отдельным путем при условии корректной системной интеграции.

Страница управления правами работает с доступными локальными/доменными identity и RBAC; она не создаёт отдельный парольный каталог Control Center.

## Основные пути

Типовые пути production-линии:

```text
/opt/srv-control                         приложение
/etc/srv-control/control.toml            конфигурация
/etc/pam.d/srv-control                    PAM service
/var/lib/srv-control                     состояние Control Center
/var/lib/srv-control/backups             резервные копии
/var/lib/srv-control/session.key          ключ web-сессий
/var/lib/srv-control/http.keytab          HTTP keytab SSO при наличии
/var/lib/srv-deployment                   deployment state/rollback state
/var/lib/srvcc-agent/deploy-repo          updater checkout GitHub main
/var/lib/srvcc-agent/last-deployed-sha
/var/lib/srvcc-agent/last-seen-sha
/var/lib/srvcc-agent/last-release-fingerprint
/var/log/srvcc-agent.log
```

Точный набор файлов/units конкретной версии определяется frozen `releases/<active-version>`.

## GitHub updates

Режим обновления настраивается из «Система» либо конфигуратором:

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

Если включена `backup_before_update`, updater сначала создаёт safety backup и блокирует deployment при ошибке backup. Подробности: `AUTO-UPDATES.md`.

## Проверка установки

Минимальная проверка:

```bash
systemctl status srv-control.service --no-pager -l
systemctl status srvcc-github-agent.timer --no-pager -l
curl -fsS http://127.0.0.1:8876/api/v1/health
cat /var/lib/srv-control/release.json
cat /var/lib/srv-control/github-update-config.json
cat /var/lib/srv-control/github-update-status.json
```

Проверка identity/admin path:

```bash
getent passwd <local-user>
systemctl status srv-control-system-agent.path --no-pager -l
ls -ld /var/lib/srv-control/backups
```

Если установлен `pamtester`, PAM можно проверять отдельно без публикации пароля в shell history/logs.

При настроенном AD/SPNEGO дополнительно проверяйте winbind/NSS, Kerberos ticket/keytab, DNS/FQDN и соответствующую Nginx authentication configuration.

## Определение активной версии

Не полагайтесь на номер версии в старой инструкции. Сначала смотрите опубликованный production target:

```bash
# в checkout репозитория
cat deployment.json
```

На установленном сервере отдельно проверяйте:

```bash
cat /var/lib/srv-control/release.json
```

Эти значения могут временно различаться после failed update и rollback.

## Повторный clean install

Clean installer намеренно не должен безусловно перезаписывать существующий `/opt/srv-control`. Для установленной системы используется product updater. Destructive reinstall выполняется отдельным явно подтверждаемым процессом с резервной копией необходимых данных.

## server-state

`server-state` используется для публикации фактического состояния сервера и диагностики. Публикация требует отдельного write credential; секреты не должны встраиваться в публичный installer или документацию.

После установки переходите к `PRODUCT-MANUAL-RU.md` и `SYSTEM-ADMIN.md`.
