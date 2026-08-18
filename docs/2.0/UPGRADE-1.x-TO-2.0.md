# Переход Control Center 1.x → 2.0

## Поддерживаемая исходная линия

Первичный production-переход 2.0.0 проверяется от опубликованного состояния 1.3.8. Все опубликованные изменения 1.x должны быть предком release/2.0.0. Неопубликованная работа 1.4 переносится выборочно в 2.0: функциональность сохраняется, но старые конфликтующие updater/backup-компоненты не накладываются поверх новой архитектуры.

## До переключения production

Обязательно выполнить:

1. CI `Control Center 2.0 validation`;
2. проверку shell/Python/JavaScript;
3. updater regression;
4. backup policy regression;
5. bulk backup delete contract;
6. Minecraft health/repair contract;
7. DHCP/PXE contracts;
8. upgrade/rollback simulation;
9. реальную транзакцию 1.3.8 → 2.0.0 и получение свежего server-state.

Пока эти проверки не завершены, `deployment.json` должен указывать на 1.3.8.

## Транзакция обновления

2.0 использует стадии preflight → apply → acceptance. До изменения production-файлов создаётся приватный rollback snapshot. Пользовательский backup перед обновлением создаётся только если `backup_before_update` строго равен `true`.

`apply-2.0.0.sh` заменяет application payload, устанавливает управляемые helpers/units, собирает перенесённые DHCP/PXE split-sources, применяет Alembic migration, восстанавливает выбранные режимы backup/OS update, выполняет Minecraft health-first repair и затем перезапускает Control Center.

После service rotation автоматический updater timer повторно проверяется на enabled/active.

## Rollback

Rollback должен восстанавливать application payload, system helpers/units, release metadata, updater configuration/status, timer state и защищённые Minecraft `server.properties` из приватного snapshot. Rollback не должен подменять историческое `last_successful_update_at` фиктивным успешным временем.

Если acceptance 2.0 не прошёл, production release не считается установленным даже если часть файлов уже была заменена.

## После успешного перехода

После подтверждённого server-state 2.0.0:

1. обновить production deployment pointer на 2.0.0;
2. зафиксировать release history;
3. убедиться, что updater timer продолжает работу;
4. убедиться, что backup timer соответствует настройке пользователя;
5. убедиться, что Minecraft healthy;
6. убедиться, что DHCP/PXE endpoints доступны и installation authorization закрыта по умолчанию;
7. удалить только устаревшие **неопубликованные** ветки разработки 1.x.

Опубликованные release-ветки 1.x сохраняются как frozen history и не удаляются.
