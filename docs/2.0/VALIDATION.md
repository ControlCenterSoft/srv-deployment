# Control Center 2.x — validation и release gates

## CI gate

Обязательные workflow:

- **Control Center 2.0 validation** — полный release contract;
- **Control Center 2.0 bootstrap validation** — аварийный переход со сломанной 1.x-линии.

Основной release workflow должен проверять:

- что текущий `main` является предком проверяемого 2.0 дерева;
- точное совпадение SHA256 manifest для preflight/apply/acceptance/rollback;
- синтаксис preflight/apply/acceptance/rollback;
- Python helpers и application modules;
- JavaScript;
- тексты и поля update-center;
- bulk backup deletion API/UI;
- строгую backup-before-update policy;
- восстановление updater после ошибок;
- DHCP/PXE carry-forward и четыре PXE contract tests;
- Minecraft health-first repair, compatibility backend и rollback safety;
- release identity 2.0.0;
- production activation pointer на 2.0.0.

## Updater acceptance

Проверить сценарии:

1. update available → successful apply/acceptance;
2. no update → меняется только last check;
3. apply failure → фиксируется attempt/failure, timer не должен быть навсегда потерян;
4. повторная проверка того же failed fingerprint → проверка выполняется, автоматическое применение подавляется;
5. новый fingerprint → снова допускается к оценке;
6. successful update → обновляет `last_successful_update_at` только после принятой транзакции;
7. аварийный bootstrap из состояния `service=failed`, `timer=disabled/inactive` → после принятого 2.0 конфигурация становится schema 4, `mode=automatic`, `interval_minutes=5`;
8. после восстановления automatic mode выполняется ещё один полный acceptance, а не только `systemctl enable`.

## Backup acceptance

Проверить независимо:

- scheduled backup ON/OFF;
- backup-before-Control-Center-update ON/OFF;
- backup-before-OS-update ON/OFF;
- single delete;
- bulk delete;
- отказ удаления несуществующего/недопустимого backup id;
- отсутствие пользовательского pre-release backup при `backup_before_update=false`;
- наличие приватного rollback snapshot независимо от пользовательской настройки.

## Minecraft acceptance

Обязательны два класса проверки.

### Health-first recovery

Проверить healthy path без переустановки, unhealthy repair path, backup failure, update/restart recovery и replacement-world path. Замена мира допускается только после safety backup и только если сервер остаётся unhealthy.

### Real-server legacy compatibility regression

Отдельно воспроизводится фактический сценарий перехода 1.3.8 → 2.0.0: процесс `bedrock_server` и UDP 19132 существуют, но исторические `/usr/local/sbin/srv-control-minecraft*` helpers отсутствуют.

Release должен:

1. установить self-contained `srv-control-minecraft-legacy` до запуска repair;
2. создать пять ожидаемых API entrypoints;
3. создать минимальный sudoers allowlist и проверить его через `visudo -cf`;
4. определять process/runtime через `/proc`, а не фиксированный каталог;
5. считать server healthy только при active process + UDP listener + `level-name` + существующем каталоге активного мира;
6. выполнять destructive operations только после safety backup;
7. включать compatibility backend, пять entrypoints и sudoers в rollback snapshot;
8. в acceptance выполнить все пять helper-путей от пользователя `srv-control` через `sudo -n`, как это делает веб API;
9. сопоставить `status.level_name` с `worlds.active_world` и world inventory.

Contract test: `releases/2.0.0/tests/minecraft_legacy_compat_contract.py`.

## DHCP/PXE acceptance

Проверить installation deny без профиля, deny без authorization, одноразовый consume, DHCP next-server для правильной LAN-подсети, UEFI/BIOS/architecture gates, Windows WIM/index validation до disk erase, Linux Secure Boot guard, explicit disk selection и приватность `/srv/pxe/profiles`.

## Real-server gate

CI и simulation не заменяют production acceptance. Перед удалением unpublished 1.x веток требуется свежий server-state реального сервера, подтверждающий:

- release/version 2.0.0;
- health Control Center;
- `github-update-config.json`: schema 4, automatic, 5 min;
- updater timer enabled/active;
- свежий `last_check_at`;
- корректный backup timer по настройке;
- Minecraft healthy и доступность compatibility backend через web execution path;
- отсутствие failed acceptance stage.

Первая неуспешная попытка не считается провалом rollback, если apply останавливается и предыдущая версия полностью восстанавливается. Такой отказ должен превращаться в отдельный regression contract до повторной production-попытки.

## Branch cleanup gate

Удалять можно только unpublished feature/hotfix/release branches 1.x после подтверждённого real-server acceptance. Перед удалением каждой ветки требуется `git merge-base --is-ancestor <branch> main`; если история не содержится в `main`, автоматическое удаление запрещено. Опубликованные release branches 1.x сохраняются как frozen history.
