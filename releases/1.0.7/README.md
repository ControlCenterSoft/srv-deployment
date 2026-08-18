# Control Center 1.0.7

Статус: `production candidate` до завершения GitHub Actions и release acceptance.

## Основные изменения

1. **PostgreSQL становится базовым application data layer Control Center.** Установщик автоматически устанавливает локальный PostgreSQL, создаёт БД `control_center` и непривилегированную роль `control-center`.
2. Локальное приложение подключается по Unix socket `/var/run/postgresql` с peer authentication. Пароль PostgreSQL в Web-приложении не хранится, TCP listener PostgreSQL наружу продуктом не открывается.
3. Добавлены versioned SQL migrations с checksum-контролем.
4. В PostgreSQL перенесены/подготовлены application-level сущности: settings, notifications/read state, audit events, jobs, module inventory, service configs.
5. Добавлена таблица `cluster_nodes` и node registration как архитектурный задел под будущий **Professional Cluster**. Кластерный runtime/репликация/HA в 1.0.7 ещё не реализованы.
6. Настройки обновлений Control Center и ОС сохраняются в PostgreSQL; JSON-файлы пока поддерживаются как compatibility mirror для существующих root workers.
7. Центр уведомлений теперь хранит read/unread на сервере в PostgreSQL вместо browser `localStorage`.
8. В **Настройки → Web-панель** добавлена смена TCP-порта Control Center: диапазон 1024–65535, проверка занятости, root apply, restart Gunicorn, health-check и rollback при ошибке.
9. Порт сохраняется в PostgreSQL и `/etc/control-center/web.env`; установщик и updater сохраняют выбранный порт при обновлении.
10. Updater стал version/build-aware и способен устанавливать новую build-ревизию внутри одинаковой версии.
11. Добавлен API состояния PostgreSQL и карточка БД в Web UI.

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

Системные конфигурации Linux **не заменяются БД**: Netplan, systemd и dnsmasq остаются фактическими источниками состояния инфраструктуры. PostgreSQL хранит application state, историю и данные управления.

## Web port apply

Web UI создаёт `/var/lib/control-center/web-pending.json`. Далее `control-center-web-apply.path` запускает root helper, который проверяет порт, обновляет `/etc/control-center/web.env`, синхронизирует PostgreSQL, перезапускает `control-center.service`, проверяет `/api/health` на новом порту и при ошибке возвращает старый порт.

## Ограничения

- Professional Cluster в 1.0.7 подготовлен на уровне модели данных, но ещё не активирован как пользовательская функция.
- PostgreSQL в 1.0.7 используется локально; автоматическое открытие PostgreSQL TCP listener или настройка межузловой репликации отсутствуют.
- Полноценная встроенная аутентификация Web UI ещё не реализована. Административный порт должен оставаться в доверенной LAN/VPN/firewall.
