# Control Center 2.0.0

## Статус

Production pointer уже направлен на `releases/2.0.0`. Кодовые и CI release gates пройдены; окончательное подтверждение production acceptance требует успешного перехода реального сервера и свежего `server-state` с `release_version=2.0.0` и `release_id=2.0.0`.

Первая аварийная bootstrap-попытка 18.08.2026 корректно остановилась на стадии apply и полностью откатилась, когда выяснилось, что на реальном сервере Bedrock слушает UDP 19132, но исторические `/usr/local/sbin/srv-control-minecraft*` helpers никогда не были установлены. Этот случай добавлен как отдельная regression-модель 2.0, а не обходится отключением проверки.

## Интерфейс

Веб-интерфейс переведён на единую оболочку Control Center: левая навигация, верхняя строка состояния, адаптивный workspace, поиск, общие состояния загрузки/ошибок и согласованные модули. В навигацию 2.0 включены DHCP, PXE Windows и PXE Linux вместе с существующими сетью, доменом, сетевыми ресурсами, Minecraft, загрузками, AdGuard VPN, сервисами, пользователями и системой.

## Обновления

Старый механизм заменён транзакционным `srvcc-update-controller` с отдельными timestamp полями `last_check_at`, `last_update_attempt_at` и `last_successful_update_at`. Failed fingerprint не применяется автоматически бесконечно, но timer продолжает проверки. После service rotation автоматический timer повторно проверяется на enabled/active.

В интерфейсе используются подписи **Автоматическое обновление**, **Последняя проверка обновления** и **Последнее успешное обновление**. Историческое успешное время сохраняется и не заменяется простой проверкой или неудачной попыткой.

Аварийный bootstrap для сломанной 1.x-линии после принятой транзакции 2.0 восстанавливает каноническую конфигурацию **automatic · 5 min** через `srvcc-configure-auto-updates`, запускает немедленный updater cycle и повторно выполняет acceptance в уже финальном режиме. Это устраняет рассинхронизацию, когда timer мог быть включён отдельно от конфигурации/UI.

## Резервные копии

Добавлены выбор нескольких архивов и массовое удаление. Административная операция проходит через CSRF/RBAC и privileged action queue.

Исправлена ошибка 1.x, при которой apply мог создать pre-release backup даже при выключенном `backup_before_update`. В 2.0 пользовательский backup создаётся только при строгом boolean `true`. Приватный rollback snapshot остаётся обязательной частью транзакции и не считается пользовательским backup.

## Minecraft Bedrock

Добавлен health-first repair. Исправный сервер не трогается. Для неисправного сервера сначала создаётся safety backup, затем выполняются repair/update/restart. Новый recovery world допускается только если обычное восстановление не помогло и safety backup успешно создан.

После первой real-server bootstrap-попытки 2.0 получил self-contained compatibility backend для старых установок Bedrock без historical helpers. Backend определяет фактический `bedrock_server` через `/proc`, рабочий каталог через `/proc/<pid>/cwd`, systemd-unit через cgroup и читает реальный `server.properties`/world inventory.

Во время apply один backend устанавливается под пять legacy entrypoint-имён, которые использует Minecraft API: `srv-control-minecraft`, `srv-control-minecraft-worlds`, `srv-control-minecraft-players`, `srv-control-minecraft-restore` и `srv-control-minecraft-live`. Для пользователя `srv-control` создаётся минимальный `sudo -n` allowlist только на эти команды; sudoers проходит `visudo -cf`.

Acceptance теперь запускает все пять helper-путей тем же способом, что веб-приложение (`runuser -u srv-control -- sudo -n ...`), и требует активный Bedrock process, UDP listener, определённый активный мир и совпадение world inventory. Compatibility backend и sudoers входят в rollback snapshot.

## DHCP/PXE carry-forward

Неопубликованная 1.4 работа по DHCP/PXE перенесена в 2.0 без возврата старого backup worker. Перенесены migration, backend/core, PXE agent/probe, UI assets и contract tests. 2.0 installer собирает split-sources, устанавливает units, создаёт PXE directories и применяет Alembic migration.

DHCP/PXE router подключается после основного 2.0 UI router: поэтому новая оболочка и модули 2.0 остаются приоритетными, а перенесённый код добавляет отсутствующие DHCP/PXE страницы и API. PXE boot media публично доступно только через `/pxe/files`; приватные profiles не публикуются.

PXE installation запрещена без профиля и отдельного одноразового authorization.

## Совместимость и история 1.x

Текущий `main` и неопубликованная история 1.4 сохранены в ancestry 2.0. Прямое наложение конфликтующего дерева 1.4 не выполняется: нужная функциональность мигрируется выборочно. Опубликованные ветки 1.x сохраняются как frozen history.

После успешного real-server acceptance bootstrap публикует свежий `server-state`, затем удаляет только заранее определённые obsolete unpublished 1.x branches и только если `git merge-base --is-ancestor` подтверждает, что их история уже содержится в `main`.

## Release gates

Перед окончательным закрытием 2.0.0 обязательны:

1. успешный `Control Center 2.0 validation`;
2. успешный `Control Center 2.0 bootstrap validation`;
3. manifest SHA256 для preflight/apply/acceptance/rollback;
4. shell/Python/JavaScript checks;
5. updater/backup/Minecraft/DHCP/PXE contracts;
6. real-server Minecraft compatibility contract для случая «UDP 19132 работает, legacy helpers отсутствуют»;
7. реальная транзакция 1.3.8 → 2.0.0;
8. повторный acceptance после восстановления `automatic · 5 min`;
9. свежий `server-state`, подтверждающий 2.0.0 и health;
10. только после этого — очистка obsolete unpublished 1.x development branches.
