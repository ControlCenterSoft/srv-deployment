# Установка Control Center

## Чистая машина

Clean installer предназначен для поддерживаемой Debian/Ubuntu-системы с `apt-get` и systemd, где `/opt/srv-control` ещё не содержит установленный Control Center.

```bash
curl -fL -o install.sh \
  https://raw.githubusercontent.com/filosoff31/srv-deployment/main/install.sh
chmod +x install.sh
sudo ./install.sh
```

Bootstrap получает актуальный `main`. `installer/install.sh` читает `deployment.json`, поэтому устанавливается self-contained payload активного `releases/<version>`. Сейчас production target — **2.0.0**.

Перед установкой проверьте сеть, DNS, время, доступ к GitHub, свободное место и root/sudo. При миграции существующего сервера предварительно создайте независимую резервную копию важных данных.

Установщик создаёт/настраивает PostgreSQL role/database, Python virtualenv, Alembic migrations, `srv-control.service`, reverse proxy, system helpers active release и GitHub updater согласно frozen implementation.

## Аутентификация после установки

Production 2.0.0 не создаёт отдельную базу web-паролей Control Center и не требует bootstrap web-user `admin`.

Вход использует системную identity chain:

- локальные Linux-учётные записи через NSS/PAM;
- доменные учётные записи через Samba/winbind + NSS/PAM;
- Kerberos/SPNEGO SSO при корректной доменной конфигурации;
- RBAC Control Center после успешной authentication.

Первый вход выполняется существующей локальной или доменной учётной записью с необходимыми правами. Страница управления правами работает с системными identities и не создаёт отдельный парольный каталог Control Center.

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
/var/lib/srv-deployment                   deployment/rollback state
/var/lib/srvcc-agent/deploy-repo          updater checkout GitHub main
/var/lib/srvcc-agent/accepted-release-fingerprint
/var/lib/srvcc-agent/last-release-fingerprint
/var/lib/srvcc-agent/blocked-release.json
/var/log/srvcc-agent.log
```

Точный набор files/units определяется frozen `releases/<active-version>`.

## GitHub updates

Режим обновления настраивается из «Система» либо конфигуратором:

```bash
sudo /usr/local/sbin/srvcc-configure-auto-updates \
  --repo https://github.com/filosoff31/srv-deployment.git \
  --mode automatic \
  --interval-minutes 5
```

Ручная проверка:

```bash
sudo /usr/local/sbin/srvcc-github-agent check --actor root
```

Применение доступного release:

```bash
sudo /usr/local/sbin/srvcc-github-agent apply --actor root
```

Если `backup_before_update` включён, updater должен выполнить обязательный пользовательский safety backup перед apply. Если policy отключена, такой backup не создаётся; внутренний rollback snapshot release transaction может сохраняться независимо.

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

При AD/SPNEGO дополнительно проверяйте winbind/NSS, Kerberos ticket/keytab, DNS/FQDN и Nginx authentication configuration.

Для 2.0.0 после установки также проверьте только реально используемые сервисы: Samba/shares, DHCP/PXE и Minecraft health, если эти модули включены в данной конфигурации.

## Определение активной версии

Сначала смотрите опубликованный production target:

```bash
cat deployment.json
```

На установленном сервере отдельно проверяйте:

```bash
cat /var/lib/srv-control/release.json
```

Эти значения могут временно различаться после failed update или rollback.

## Повторный clean install

Clean installer не должен безусловно перезаписывать существующий `/opt/srv-control`. Для установленной системы используется product updater. Destructive reinstall выполняется отдельным явно подтверждаемым процессом с резервной копией необходимых данных.

## server-state

`server-state` используется для публикации фактического состояния сервера и диагностики. Публикация требует отдельного write credential; secrets не должны встраиваться в installer или документацию.

После установки переходите к `PRODUCT-MANUAL-RU.md` и `SYSTEM-ADMIN.md`.
