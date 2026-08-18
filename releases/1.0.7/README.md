# Control Center 1.0.7

Статус: `production`.

GitHub Actions release validation успешно проверила Python/JavaScript/Bash, metadata consistency, публичный RSA key, обязательную документацию и **реальную PostgreSQL integration-схему**: service startup, peer authentication, создание БД/роли, SQL migration, settings, jobs, notifications/read state и cluster node registration.

## Основные изменения

1. **PostgreSQL стал базовым application data layer Control Center.** Installer автоматически устанавливает локальный PostgreSQL, создаёт БД `control_center` и непривилегированную роль `control-center`.
2. Локальное приложение подключается по Unix socket `/var/run/postgresql` с peer authentication. Пароль PostgreSQL в Web-приложении не хранится, TCP listener PostgreSQL наружу продуктом не открывается.
3. Добавлены versioned SQL migrations с SHA-256 checksum-контролем.
4. PostgreSQL хранит settings, notifications/read state, audit events, jobs, module inventory и service configs.
5. Добавлена таблица `cluster_nodes` и регистрация локального standalone node как архитектурный задел будущего **Professional Cluster**. Кластерный runtime/replication/HA в 1.0.7 ещё не реализованы.
6. Настройки обновлений Control Center и ОС сохраняются в PostgreSQL; JSON поддерживается как compatibility mirror для существующих root workers.
7. Центр уведомлений хранит read/unread server-side в PostgreSQL вместо browser `localStorage`.
8. **Настройки → Web-панель**: изменение TCP-порта Control Center в диапазоне 1024–65535, проверка занятости, root apply, restart Gunicorn, health-check и rollback.
9. Порт хранится в PostgreSQL и `/etc/control-center/web.env`; installer/updater сохраняют выбранный порт.
10. Updater стал version/build-aware и поддерживает build hotfix внутри той же версии.
11. Перед будущим обновлением существующей PostgreSQL БД updater создаёт root-only `pg_dump`; неудачный installer восстанавливает DB dump вместе с приложением и Web-port state.
12. Добавлен API/карточка состояния PostgreSQL и graceful read-only degraded mode для части настроек при временной недоступности БД.

## PostgreSQL schema

```text
control_center.schema_migrations
control_center.settings
control_center.notification_events
control_center.audit_events
control_center.jobs
control_center.module_inventory
control_center.service_configs
control_center.cluster_nodes
```

Системные конфигурации Linux **не заменяются БД**: Netplan, systemd и dnsmasq остаются фактическими источниками состояния инфраструктуры.

## Web port apply

```text
/api/settings/web
  -> /var/lib/control-center/web-pending.json
  -> control-center-web-apply.path
  -> control-center-web-apply.service
  -> /usr/local/sbin/control-center-web-apply
  -> /etc/control-center/web.env
```

Helper проверяет порт, синхронизирует PostgreSQL, перезапускает Control Center, проверяет `/api/health` на новом порту и при ошибке возвращает предыдущий порт.

## Acceptance

```bash
sudo bash scripts/acceptance-1.0.7.sh
```

Проверка является non-destructive и включает PostgreSQL, migration, peer connection, database API, version/build, Web-port wiring, notification persistence, network inventory и DHCP при установленном модуле.

## Ограничения

- Professional Cluster подготовлен на уровне модели данных, но не активирован как пользовательская HA/replication функция.
- PostgreSQL используется локально; автоматическое открытие PostgreSQL TCP listener отсутствует.
- Встроенная Web-аутентификация ещё не реализована. Административный порт должен оставаться в доверенной LAN/VPN/firewall.
