# Control Center 2.x — validation и release gates

## CI gate

Обязательный workflow: **Control Center 2.0 validation**.

Он должен проверять:

- что текущий `main` является предком release/2.0.0;
- синтаксис preflight/apply/acceptance/rollback;
- Python helpers и application modules;
- JavaScript;
- тексты и поля update-center;
- bulk backup deletion API/UI;
- строгую backup-before-update policy;
- восстановление updater после ошибок;
- DHCP/PXE carry-forward и четыре PXE contract tests;
- Minecraft health-first repair и rollback safety;
- release identity 2.0.0;
- защиту от преждевременного переключения production pointer.

## Updater acceptance

Проверить сценарии:

1. update available → successful apply/acceptance;
2. no update → меняется только last check;
3. apply failure → фиксируется attempt/failure, timer остаётся активным;
4. повторная проверка того же failed fingerprint → проверка выполняется, автоматическое применение подавляется;
5. новый fingerprint → снова допускается к оценке;
6. successful update → обновляет `last_successful_update_at` только после принятой транзакции.

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

Проверить healthy path без переустановки, unhealthy repair path, backup failure, update/restart recovery и replacement-world path. Замена мира допускается только после safety backup и только если сервер остаётся unhealthy.

## DHCP/PXE acceptance

Проверить installation deny без профиля, deny без authorization, одноразовый consume, DHCP next-server для правильной LAN-подсети, UEFI/BIOS/architecture gates, Windows WIM/index validation до disk erase, Linux Secure Boot guard, explicit disk selection и приватность `/srv/pxe/profiles`.

## Real-server gate

CI и simulation не заменяют production acceptance. Перед удалением unpublished 1.x веток требуется свежий server-state реального сервера, подтверждающий:

- release/version 2.0.0;
- health Control Center;
- updater timer enabled/active в automatic mode;
- корректный backup timer по настройке;
- Minecraft healthy;
- отсутствие failed acceptance stage.

## Branch cleanup gate

Удалять можно только unpublished feature/hotfix/release branches 1.x, когда их нужная функциональность уже является предком/частью 2.x и production server-state подтвердил 2.0.0. Опубликованные release branches 1.x не удаляются.
