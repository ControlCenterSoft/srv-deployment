# srv-deployment

Репозиторий управляемых релизов **SRV Control Center**.

Основная ветка `main` — источник обновлений для сервера. Ветка `server-state` используется рабочим сервером для публикации снимков фактического состояния.

## Быстрая установка на чистую машину

Для Debian/Ubuntu с systemd:

```bash
curl -fL -o install.sh \
  https://raw.githubusercontent.com/filosoff31/srv-deployment/main/install.sh
chmod +x install.sh
sudo ./install.sh
```

Полная инструкция: [`docs/INSTALL.md`](docs/INSTALL.md).

Инсталлятор не перезаписывает существующий `/opt/srv-control`: для уже установленного Control Center используется штатный GitHub deployment-канал.

## Правило журнала релизов

Этот раздел ведётся в режиме **append-only**: описание нового релиза добавляется ниже предыдущих записей. Старые записи не удаляются и не заменяются. Если к старому релизу требуется уточнение, оно добавляется отдельным дополнением к его записи.

## Журнал релизов

### 0001-channel-acceptance — проверка deployment-канала

Первый безопасный технический релиз. Проверял путь `GitHub main → SRV`, preflight/apply/acceptance/rollback и создание контрольного marker-файла, не изменяя рабочее приложение Control Center.

### 0.2.0 / 0002-ui-release-metadata — метаданные релиза

В нижней части навигации рядом со статусом Backend добавлены версия Control Center и дата последней успешно применённой синхронизации с GitHub. Backend начал публиковать `release.version`, `release.git_sha` и `release.synced_at` через `/api/v1/health`.

### 0.3.0 / 0003-system-overview — рабочий раздел «Система»

Заглушка «Система» заменена read-only панелью состояния сервера. Добавлены hostname, ОС, ядро, архитектура, uptime, CPU/load, RAM, хранилища, ключевые systemd-службы, версия релиза и GitHub sync.

После выпуска выявлена ошибка инфраструктуры обновлений: старый `deploy/healthcheck.sh` продолжал ожидать marker тестового `channel-probe`. Сам релиз успешно применялся, но внешний healthcheck возвращал ошибку, поэтому агент не записывал `last-deployed-sha` и повторял deployment на каждом цикле таймера. Это вызывало повторные перезапуски `srv-control.service`. Исправление добавило современный healthcheck и защиту от повторного apply/restart уже успешно принятого commit.

### 0.4.0 / 0004-deployment-reliability — устойчивые обновления

Релиз переводит Uvicorn на встроенный process manager с двумя workers и добавляет механизм graceful worker rotation через `SIGHUP` для следующих code-only обновлений. Uvicorn перезапускает workers по одному, поэтому listener остаётся доступным во время загрузки нового кода.

Также раздел «Система» получает блок «Канал обновлений»: результат deployment, стадия, commit, время завершения и последнего healthcheck. Generic deployment healthcheck больше не зависит от старого `DEPLOYMENT_STATUS.txt`, а orchestrator защищён от restart-loop: если exact commit/release уже прошёл acceptance, повторная попытка выполняет только revalidation без нового apply/restart.

В этот же этап добавлен clean-install installer из GitHub и инструкция по установке.

## Deployment safety

Каждый product-релиз содержит:

- `preflight.sh`;
- `apply.sh`;
- `acceptance.sh`;
- `rollback.sh`;
- `manifest.json` с SHA256 исполняемых release-скриптов.

Общий orchestrator проверяет manifest и контрольные суммы до применения релиза. Для code-only релизов после 0.4.0 следует использовать `deploy/reload-srv-control.sh` вместо жёсткого `systemctl restart`.

Подробности расследования restart-loop: [`docs/DEPLOYMENT-RELIABILITY.md`](docs/DEPLOYMENT-RELIABILITY.md).
