# Установка Control Center

> **Назначение:** чистая установка текущего production release на новую Debian/Ubuntu-систему. Активная версия всегда определяется `../deployment.json`; на момент этой редакции production target — **2.0.0**.

## Требования к новой системе

Clean installer рассчитан на Debian/Ubuntu-систему с `apt-get` и systemd, где `/opt/srv-control` ещё не содержит установленный Control Center.

Перед запуском проверьте:

- рабочее сетевое подключение и DNS;
- корректное системное время;
- доступ к GitHub;
- свободное место для пакетов, Python virtualenv, PostgreSQL, резервных копий и управляемых сервисов;
- root/sudo доступ;
- отсутствие существующей установки в `/opt/srv-control`.

Installer намеренно прекращает работу, если `/opt/srv-control` уже содержит файлы. Для установленного продукта используется product updater, а не clean install поверх существующей системы.

## Запуск

```bash
curl -fL -o install.sh \
  https://raw.githubusercontent.com/filosoff31/srv-deployment/main/install.sh
chmod +x install.sh
sudo ./install.sh
```

Внешний `install.sh` устанавливает минимальные bootstrap-зависимости, клонирует текущий `main` во временный каталог и передаёт управление `installer/install.sh` из того же checkout.

## Что делает clean installer

Clean installer больше не ограничивается копированием web application payload. Он выполняет полный contract активного frozen release.

Последовательность:

```text
bootstrap main
  → validate deployment.json + manifest
  → verify active apply/acceptance SHA-256
  → install OS dependencies
  → create srv-control identity/state
  → install base application + venv + PostgreSQL
  → configure Control Center service + nginx
  → install PAM/NSS/auth bootstrap state
  → run active frozen release apply
  → run active frozen release acceptance
  → final health/systemd acceptance
```

Для production 2.0.0 это принципиально важно: полный release apply устанавливает не только web-файлы, но и updater controller, backup policy/retention, Samba agents, DHCP/PXE agent, Minecraft compatibility/recovery helpers и соответствующие systemd units. Поэтому успешный HTTP health-check сам по себе больше не считается достаточным доказательством полноценной установки.

## Проверка release metadata до изменения системы

Installer читает `deployment.json`, затем manifest активного `releases/<version>` и проверяет как минимум:

- `release_id`;
- `release_path`;
- `release_version`;
- отсутствие выхода release/script paths за пределы repository/release directory;
- SHA-256 активных `apply` и `acceptance` scripts по manifest.

Если metadata противоречива или hash не совпадает, установка прекращается до запуска release apply.

Опубликованные `releases/<version>` являются frozen и installer их не изменяет.

## Устанавливаемые системные зависимости

Базовый clean installer устанавливает через `apt-get`:

```text
ca-certificates
curl
git
nginx
postgresql
postgresql-client
python3
python3-pip
python3-venv
sudo
```

Дополнительные пакеты/сервисы могут устанавливаться или настраиваться active release contract в зависимости от версии и включённых модулей.

## Аутентификация и первый вход

Production 2.0.0 не создаёт отдельную базу web-паролей Control Center и не создаёт bootstrap web-user `admin` с отдельным паролем.

Identity chain:

- локальные Linux identities через NSS/PAM;
- доменные identities через Samba/winbind + NSS/PAM;
- Kerberos/SPNEGO SSO при корректной доменной конфигурации;
- Control Center RBAC после successful authentication.

Первый вход выполняется существующей локальной или доменной учётной записью, которой назначены необходимые права. Если authentication проходит, но модуль недоступен, проверяйте RBAC.

Файл `/var/lib/srv-control/admin-bootstrap.txt` относится к исторической архитектуре и не используется текущим clean installer.

## Основные пути

```text
/opt/srv-control                         application
/etc/srv-control/control.toml            configuration
/etc/pam.d/srv-control                    PAM service
/var/lib/srv-control                     product state
/var/lib/srv-control/backups             backups
/var/lib/srv-control/session.key          web session key
/var/lib/srv-control/http.keytab          HTTP Kerberos keytab, если настроен
/var/lib/srv-deployment                   deployment/rollback state
/var/lib/srvcc-agent                      product updater state
/var/log/srv-control-install.log          clean-install log
```

Точный набор helpers, units и state files определяется active frozen release.

## Product updater после установки

Для 2.0.0 active release apply разворачивает актуальный updater controller/configurator и восстанавливает штатный automatic mode с 5-минутным интервалом для новой установки.

Проверка:

```bash
systemctl is-enabled srvcc-github-agent.timer
systemctl is-active srvcc-github-agent.timer
cat /var/lib/srv-control/github-update-config.json
cat /var/lib/srv-control/github-update-status.json
```

Ручная проверка без применения:

```bash
sudo /usr/local/sbin/srvcc-github-agent check --actor root
```

Ручное применение доступного product release:

```bash
sudo /usr/local/sbin/srvcc-github-agent apply --actor root
```

Подробнее: `AUTO-UPDATES.md`.

## Backup policy

`backup_before_update` относится к последующим product/OS updates и не заменяет rollback snapshot release transaction.

На чистой системе installer создаёт необходимое начальное state/config, после чего active release нормализует backup policy. Плановый backup и backup-before-update остаются независимыми настройками.

## Acceptance после установки

Installer запускает **frozen acceptance script активного release**, а затем дополнительный clean-install health check.

Минимально должны подтверждаться:

```bash
systemctl is-active srv-control.service
systemctl is-active nginx.service
systemctl is-enabled srvcc-github-agent.timer
systemctl is-active srvcc-github-agent.timer
systemctl is-active srv-control-system-agent.path
curl -fsS http://127.0.0.1:8876/api/v1/health
cat /var/lib/srv-control/release.json
```

Для 2.0.0 frozen acceptance дополнительно проверяет release-specific UI/API/assets/helpers/systemd contracts, включая updater, backups, DHCP/PXE и Minecraft compatibility path.

Если release acceptance завершается ошибкой, installation не должна сообщать `INSTALL PASS`.

## Где смотреть лог

```bash
sudo less /var/log/srv-control-install.log
```

При диагностике не публикуйте session keys, Kerberos key material, passwords, access tokens, private keys или содержимое backup archives.

## Определение версии

Production target репозитория:

```bash
cat deployment.json
```

Версия установленного сервера:

```bash
cat /var/lib/srv-control/release.json
```

Эти значения могут различаться после failed update/rollback, поэтому при диагностике фиксируйте оба.

## Повторная установка

Не запускайте clean installer поверх существующего `/opt/srv-control`.

Для обычного обновления используйте product updater. Полная destructive reinstall допустима только как отдельная явно подтверждённая процедура с предварительной резервной копией необходимых данных.

После clean install переходите к `PRODUCT-MANUAL-RU.md`, `SYSTEM-ADMIN.md` и version-specific `2.0/ADMIN-GUIDE.md`.
