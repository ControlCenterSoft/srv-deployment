# Control Center 1.0.8

Статус: `production`.

GitHub Actions release validation успешно проверила Python/JavaScript/Bash, release metadata, PostgreSQL peer-auth/migration и **реальный DHCP lifecycle**: установка пакета `dnsmasq` тем же Market root helper, проверка module state, persistent Market status, start/success event history, `dnsmasq --test`, отсутствие дистрибутивного dnsmasq runtime и последующее удаление модуля.

## Что изменено

### Статусы сервисов в Маркете

В верхней правой части каждой карточки сервиса добавлен постоянный статус. Для DHCP доступны состояния:

- **Установка…** — root Market worker выполняет установку;
- **Работает** — пакет установлен и модуль зарегистрирован Control Center;
- **Ошибка** — установка либо работа настроенного DHCP завершилась ошибкой;
- **Не установлен** — модуль доступен для установки.

Для будущих сервисов остаётся состояние **Запланировано**.

Состояние формируется сервером из pending request, protected Market status, module state, пакета `dnsmasq` и фактического systemd status. Поэтому обновление страницы, переход в другой раздел или повторный вход в Маркет не сбрасывают состояние.

При статусе **Ошибка** полный diagnostic detail доступен через tooltip при наведении мыши.

## История установки в уведомлениях

Market root worker ведёт защищённый журнал:

```text
/var/lib/control-center-system/market-events.jsonl
```

Для установки/удаления сохраняются отдельные события start/success/failure с server timestamp. `/api/notifications` переносит эти события в PostgreSQL `notification_events`, поэтому в колокольчике остаются, например:

- `Установка началась: DHCP Server`;
- `Установка успешно завершена: DHCP Server`;
- `Установка DHCP Server завершилась ошибкой ...` + diagnostic detail.

Дата и время выводятся интерфейсом из server timestamp.

## Исправление установки DHCP

Установка DHCP переработана:

1. `dnsmasq` не запускается автоматически во время `apt` — используется временный `policy-rc.d` с обязательным восстановлением исходного файла.
2. После установки проверяются `dpkg-query`, наличие `dnsmasq` и `dnsmasq --test`.
3. Дистрибутивный `dnsmasq.service` отключается; дальнейшая DHCP-конфигурация управляется выделенной службой Control Center.
4. Если предыдущая установка Control Center оборвалась после установки пакета, 1.0.8 умеет безопасно восстановить модуль, но только если нет внешних DHCP directives и есть признаки предыдущей операции Control Center.
5. Активная внешняя DHCP-конфигурация по-прежнему не захватывается автоматически.
6. Полный вывод последней Market операции хранится в `market-last.log` и при ошибке попадает в protected status/tooltip/notification.

GitHub Actions 1.0.8 выполняет **реальную установку и удаление dnsmasq** через тот же root helper, которым пользуется сервер.

## Установка обновления Control Center

`GET /api/settings/update/check` возвращает `update_available` с учётом `release` и `build`.

В **Настройки → Обновления Control Center** добавляется кнопка **Установить обновление**. Она:

- отключена, если установлен актуальный Production build;
- автоматически активируется при обнаружении более новой версии/build;
- при нажатии создаёт `/var/lib/control-center/update-now`;
- `control-center-update-now.path` немедленно запускает root updater;
- ручной запрос выполняется даже при отключённых автоматических обновлениях и без ожидания интервала проверки.

Updater сохраняет Production metadata/payload validation, application rollback и PostgreSQL `pg_dump` rollback архитектуры 1.0.7.

## Acceptance

```bash
sudo bash scripts/acceptance-1.0.8.sh
```

Acceptance проверяет version/build, Market status API, update availability API, manual update path watcher, PostgreSQL notifications, UI overlay и DHCP consistency при установленном модуле.

## Безопасность

- PostgreSQL остаётся локальным application data layer через Unix socket/peer authentication.
- Системные конфигурации применяются только root helpers.
- Внешний существующий `dnsmasq` не захватывается без безопасного recovery-контекста.
- Встроенная Web-аутентификация административной панели пока не реализована; Web-порт необходимо ограничивать доверенной LAN/VPN/firewall.
