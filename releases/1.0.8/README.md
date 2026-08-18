# Control Center 1.0.8

Текущий build: **20260819.2**.

## Hotfix build 20260819.2

Build исправляет сценарий, обнаруженный на работающем сервере Control Center 1.0.6:

1. updater 1.0.6 проверяет `APP_VERSION` непосредственно в `app/main.py` до запуска installer;
2. первоначальный build 1.0.8 выставлял runtime version через release extension, из-за чего legacy updater не мог корректно подтвердить payload;
3. Market 1.0.6 временно маскировал `dnsmasq.service`; `apt-get install dnsmasq` мог вернуть **код 100 уже после установки пакета**, но до записи `modules/dhcp.json`;
4. после этого пакет существовал, а Control Center считал его внешним, и последующие package/update операции могли продолжать падать.

В build 20260819.2:

- `app/main.py` снова содержит явный `APP_VERSION = '1.0.8'` для совместимости с updater 1.0.6;
- фактическая application implementation сохранена в `main_base_107.py`, runtime остаётся единым;
- installer перед миграцией выполняет безопасный `dpkg/apt` preflight с `apt-get -f install`, не удаляя dnsmasq config;
- во время package repair запуск `dnsmasq` блокируется временным `policy-rc.d`;
- добавлен скрипт `scripts/repair-upgrade-1.0.6-to-1.0.8.sh`, который делает резервную диагностическую копию, принудительно запускает production updater и сохраняет rollback старого updater;
- если stale `dnsmasq` действительно является результатом неудачной установки Control Center 1.0.6 и внешняя конфигурация dnsmasq отсутствует, скрипт создаёт явный recovery marker и после обновления восстанавливает DHCP module state;
- внешний dnsmasq с активной пользовательской конфигурацией не захватывается и не удаляется;
- OS updater также ремонтирует half-configured packages и блокирует автозапуск обычного `dnsmasq.service` во время package transaction.

## Быстрое восстановление сервера 1.0.6

На проблемном сервере:

```bash
curl -fsSL \
  https://raw.githubusercontent.com/filosoff31/srv-deployment/release/1.0.8/scripts/repair-upgrade-1.0.6-to-1.0.8.sh \
  | sudo bash
```

Скрипт использует существующий updater 1.0.6, поэтому его штатный application rollback остаётся активным. До изменений создаётся каталог:

```text
/var/lib/control-center-root/manual-repair-<timestamp>/
```

с копиями update/Market status, журналов и dnsmasq config.

## Постоянные статусы сервисов

В Маркете карточка DHCP показывает server-side lifecycle status:

- **Установка…**;
- **Работает**;
- **Ошибка**;
- **Не установлен**.

Статус переживает reload/navigation. При `Ошибка` diagnostic detail доступен по наведению.

## Уведомления установки

Market root worker сохраняет start/success/failure events в:

```text
/var/lib/control-center-system/market-events.jsonl
```

События синхронизируются в PostgreSQL `notification_events` и отображаются в колокольчике с server timestamp.

## DHCP

Fresh install и legacy recovery проходят проверку `dnsmasq --test`. Рабочая DHCP-конфигурация по-прежнему запускается через `control-center-dhcp-server.service`, а не через дистрибутивный `dnsmasq.service`.

## Обновления Control Center

`GET /api/settings/update/check` сравнивает version/build. Кнопка **Установить обновление** активна только для более нового Production target. Ручной запуск идёт через `control-center-update-now.path` в root updater.

## Acceptance

```bash
sudo bash scripts/acceptance-1.0.8.sh
```

Ожидается:

```text
1.0.8
20260819.2
ACCEPTANCE: PASSED
```

GitHub Actions проверяет Python/JavaScript/Bash, legacy updater payload check, PostgreSQL peer migration, fresh DHCP install/remove и отдельный legacy DHCP recovery scenario.

## Безопасность

PostgreSQL остаётся локальным через Unix socket/peer authentication. Системные изменения выполняют root helpers. Встроенная Web-аутентификация пока не реализована, поэтому административный порт должен быть ограничен доверенной LAN/VPN/firewall.
