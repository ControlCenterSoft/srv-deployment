# Переход Control Center 1.x → 2.0

## Поддерживаемая исходная линия

Первичный production-переход 2.0.0 проверяется от опубликованного состояния 1.3.8. Все опубликованные изменения 1.x должны быть предком release/2.0.0. Неопубликованная работа 1.4 переносится выборочно в 2.0: функциональность сохраняется, но старые конфликтующие updater/backup-компоненты не накладываются поверх новой архитектуры.

## Release gates до активации

Перед переключением production обязательны:

1. CI `Control Center 2.0 validation`;
2. проверка shell/Python/JavaScript;
3. updater regression;
4. backup policy regression;
5. bulk backup delete contract;
6. Minecraft health/repair contract;
7. DHCP/PXE contracts;
8. upgrade/rollback simulation;
9. проверка manifest SHA256.

После прохождения этих gate `deployment.json` переводится на 2.0.0. Фактический переход реального сервера считается завершённым только после свежего `server-state`, где `release_version=2.0.0` и `release_id=2.0.0`.

## Транзакция обновления

2.0 использует стадии preflight → apply → acceptance. До изменения production-файлов создаётся приватный rollback snapshot. Пользовательский backup перед обновлением создаётся только если `backup_before_update` строго равен `true`.

`apply-2.0.0.sh` заменяет application payload, устанавливает управляемые helpers/units, собирает перенесённые DHCP/PXE split-sources, применяет Alembic migration, восстанавливает выбранные режимы backup/OS update, выполняет Minecraft health-first repair и затем перезапускает Control Center.

После service rotation автоматический updater timer повторно проверяется на enabled/active.

## Аварийный bootstrap при сломанном updater 1.x

Известный отказ старой линии 1.x мог оставить `srvcc-github-agent.service` в состоянии `failed`, а `srvcc-github-agent.timer` — `disabled/inactive`. В таком состоянии сервер больше не увидит даже исправленный release 2.0.0, поэтому ожидание очередной автоматической проверки бессмысленно.

Для этого случая в репозитории есть `tools/bootstrap-control-center-2.0.sh`. Он не использует сломанный transport 1.x как механизм установки. Скрипт:

1. клонирует текущую ветку `main` во временный каталог;
2. проверяет, что production target — ровно 2.0.0;
3. запускает штатный hash-validating `deploy/deploy.sh`;
4. тем самым выполняет `preflight → apply → acceptance` с автоматическим rollback при ошибке;
5. проверяет `/var/lib/srv-control/release.json`;
6. сбрасывает failed-state updater, включает и запускает новый timer;
7. выполняет немедленный updater cycle;
8. требует status schema 4 и успешный healthcheck.

Запуск с сервера от root:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/filosoff31/srv-deployment/main/tools/bootstrap-control-center-2.0.sh)
```

Если `curl` отсутствует, допустим эквивалент через временный `git clone` текущего `main` и запуск `tools/bootstrap-control-center-2.0.sh` из клона.

Bootstrap является одноразовым recovery-механизмом. После успешного перехода дальнейшие обновления выполняет только штатный 2.x updater.

## Rollback

Rollback должен восстанавливать application payload, system helpers/units, release metadata, updater configuration/status, timer state, DHCP/PXE agents и защищённые Minecraft `server.properties` из приватного snapshot. Rollback не должен подменять историческое `last_successful_update_at` фиктивным успешным временем.

Если acceptance 2.0 не прошёл, production release не считается установленным даже если часть файлов уже была заменена.

## После успешного перехода

После подтверждённого server-state 2.0.0:

1. убедиться, что updater timer продолжает работу;
2. убедиться, что update status использует schema 4 и содержит `last_check_at`;
3. убедиться, что backup timer соответствует настройке пользователя;
4. убедиться, что Minecraft healthy;
5. убедиться, что DHCP/PXE endpoints доступны и installation authorization закрыта по умолчанию;
6. зафиксировать production acceptance в release history;
7. удалить только устаревшие **неопубликованные** ветки разработки 1.x.

Опубликованные release-ветки 1.x сохраняются как frozen history и не удаляются.
