# Control Center 2.0.0

## Статус

2.0.0 готовится в `release/2.0.0`. До прохождения всех release gates production pointer остаётся на опубликованной версии 1.3.8.

## Интерфейс

Веб-интерфейс переведён на единую оболочку Control Center: левая навигация, верхняя строка состояния, адаптивный workspace, поиск, общие состояния загрузки/ошибок и согласованные модули. В навигацию 2.0 включены DHCP, PXE Windows и PXE Linux вместе с существующими сетью, доменом, сетевыми ресурсами, Minecraft, загрузками, AdGuard VPN, сервисами, пользователями и системой.

## Обновления

Старый механизм заменён транзакционным `srvcc-update-controller` с отдельными timestamp полями `last_check_at`, `last_update_attempt_at` и `last_successful_update_at`. Failed fingerprint не применяется автоматически бесконечно, но timer продолжает проверки. После service rotation автоматический timer повторно проверяется на enabled/active.

В интерфейсе используются подписи **Автоматическое обновление**, **Последняя проверка обновления** и **Последнее успешное обновление**. Историческое успешное время сохраняется и не заменяется простой проверкой или неудачной попыткой.

## Резервные копии

Добавлены выбор нескольких архивов и массовое удаление. Административная операция проходит через CSRF/RBAC и privileged action queue.

Исправлена ошибка 1.x, при которой apply мог создать pre-release backup даже при выключенном `backup_before_update`. В 2.0 пользовательский backup создаётся только при строгом boolean `true`. Приватный rollback snapshot остаётся обязательной частью транзакции и не считается пользовательским backup.

## Minecraft Bedrock

Добавлен health-first repair. Исправный сервер не трогается. Для неисправного сервера сначала создаётся safety backup, затем выполняются repair/update/restart через проверенный single-server management path. Новый recovery world допускается только если обычное восстановление не помогло и safety backup успешно создан.

## DHCP/PXE carry-forward

Неопубликованная 1.4 работа по DHCP/PXE перенесена в 2.0 без возврата старого backup worker. Перенесены migration, backend/core, PXE agent/probe, UI assets и contract tests. 2.0 installer собирает split-sources, устанавливает units, создаёт PXE directories и применяет Alembic migration.

DHCP/PXE router подключается после основного 2.0 UI router: поэтому новая оболочка и модули 2.0 остаются приоритетными, а перенесённый код добавляет отсутствующие DHCP/PXE страницы и API. PXE boot media публично доступно только через `/pxe/files`; приватные profiles не публикуются.

PXE installation запрещена без профиля и отдельного одноразового authorization.

## Совместимость и история 1.x

Текущий `main` и неопубликованная история 1.4 сохранены в ancestry 2.0. Прямое наложение конфликтующего дерева 1.4 не выполняется: нужная функциональность мигрируется выборочно. Опубликованные ветки 1.x сохраняются как frozen history.

## Release gates

Перед production activation обязательны:

1. успешный `Control Center 2.0 validation`;
2. shell/Python/JavaScript checks;
3. updater/backup/Minecraft/DHCP/PXE contracts;
4. simulation перехода 1.3.8 → 2.0.0 и rollback;
5. реальная транзакция на production server;
6. свежий `server-state`, подтверждающий 2.0.0 и health;
7. только после этого — удаление obsolete unpublished 1.x development branches.
