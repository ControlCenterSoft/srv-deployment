# Control Center — документация

Этот каталог содержит текущую эксплуатационную документацию, roadmap, release history и исторические release-specific материалы.

## С чего начать

- **`PRODUCT-MANUAL-RU.md`** — каноническое русскоязычное руководство пользователя и администратора.
- **`INSTALL.md`** — чистая установка.
- **`SYSTEM-ADMIN.md`** — authentication, PAM/NSS, RBAC и privileged administration.
- **`AUTO-UPDATES.md`** — automatic/manual GitHub product updater.
- **`DEPLOYMENT-RELIABILITY.md`** — preflight/apply/acceptance/rollback модель.
- **`ROADMAP.md`** — будущий scope после текущего production release.

## Источники истины

При расхождении документов используйте следующий приоритет:

1. `../deployment.json` — активный production target;
2. `../releases/<active-version>` — frozen implementation/manifest активного релиза;
3. актуальный `server-state` — фактическое состояние конкретного сервера;
4. `RELEASE-HISTORY.md` — история публикаций и repair-релизов;
5. `PRODUCT-MANUAL-RU.md` — текущая пользовательская/административная инструкция;
6. `ROADMAP.md` — будущий scope.

## Текущее состояние

`../deployment.json` сейчас публикует **Control Center 2.0.0**. Каталог `../releases/2.0.0` является frozen production payload и не должен редактироваться ради исправления документации.

Наличие реализации в development branch, draft PR или roadmap не означает production-доступность функции. И наоборот, после переключения `deployment.json` документация обязана быть синхронизирована с новым production release.

## Текущая и историческая документация

`RELEASE-*.md`, incident notes и implementation-specific документы сохраняются как исторические источники. Их нельзя автоматически трактовать как описание текущей production-линии.

Инструкции ранних 0.x релизов про отдельный bootstrap web-user/password не применимы к современной PAM/NSS/winbind/RBAC architecture. Исторические 1.x updater/Minecraft incident-документы сохраняются для трассируемости, но текущую эксплуатацию определяет 2.0.0.

## Product planning

- `ROADMAP.md` — будущие направления после 2.0.0;
- `PRODUCT-EDITIONS.md` — editions/licensing architecture и staged rollout;
- `RELEASE-HISTORY.md` — опубликованная release lineage.

Наличие функции в roadmap не означает её наличие в production. Для 2.0.0 реализованные возможности сверяются с manifest и frozen payload, а незавершённые требования прежнего 2.0 roadmap переносятся в будущий 2.x scope.

## Правило обновления документации

При каждом новом опубликованном product release необходимо:

1. сверить `deployment.json` и manifest нового release;
2. обновить `RELEASE-HISTORY.md`;
3. обновить `PRODUCT-MANUAL-RU.md` для пользовательски значимых изменений;
4. обновить профильные документы (`SYSTEM-ADMIN.md`, `AUTO-UPDATES.md`, `INSTALL.md` и т. п.), если изменилась соответствующая архитектура;
5. обновить `ROADMAP.md`, чтобы уже опубликованный scope не оставался описанным как будущий;
6. проверить ссылки и отсутствие противоречий;
7. не изменять опубликованные frozen `releases/<version>`;
8. не добавлять secrets в документацию, diagnostics или примеры.

Документация является обязательной частью release acceptance: новый релиз не должен считаться полностью документированным, пока инструкция и release history не соответствуют фактической реализации.
