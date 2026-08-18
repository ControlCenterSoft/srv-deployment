# Control Center — документация

Этот каталог содержит текущую эксплуатационную документацию, roadmap, release history и исторические release-specific материалы.

## С чего начать

- **`PRODUCT-MANUAL-RU.md`** — каноническое русскоязычное руководство пользователя и администратора.
- **`INSTALL.md`** — чистая установка.
- **`SYSTEM-ADMIN.md`** — authentication, PAM/NSS, RBAC и privileged administration.
- **`AUTO-UPDATES.md`** — automatic/manual GitHub product updater.
- **`DEPLOYMENT-RELIABILITY.md`** — preflight/apply/acceptance/rollback модель.

## Источники истины

При расхождении документов используйте следующий приоритет:

1. `../deployment.json` — активный production target;
2. `../releases/<active-version>` — frozen release implementation/manifest;
3. актуальный `server-state` — фактическое состояние конкретного сервера;
4. `RELEASE-HISTORY.md` — история публикаций и repair-релизов;
5. `PRODUCT-MANUAL-RU.md` — текущая пользовательская/административная инструкция;
6. `ROADMAP.md` — будущий scope.

## Текущая и историческая документация

`RELEASE-*.md`, incident notes и implementation-specific документы сохраняются как исторические источники. Их нельзя автоматически трактовать как описание текущей production-линии.

Например, инструкции ранних 0.x релизов про отдельный bootstrap web-user/password не применимы к современной PAM/NSS/winbind/RBAC architecture.

## Product planning

- `ROADMAP.md` — согласованное направление будущей разработки;
- `PRODUCT-EDITIONS.md` — редакции, licensing architecture и lifecycle;
- `RELEASE-HISTORY.md` — опубликованная release lineage.

Наличие функции в roadmap не означает её наличие в текущем production release.

## Правило обновления документации

При каждом новом опубликованном product release необходимо:

1. сверить `deployment.json` и manifest нового release;
2. обновить `RELEASE-HISTORY.md`;
3. обновить `PRODUCT-MANUAL-RU.md` для пользовательски значимых изменений;
4. обновить профильные документы (`SYSTEM-ADMIN.md`, `AUTO-UPDATES.md`, `INSTALL.md` и т. п.), если изменилась соответствующая архитектура;
5. проверить ссылки и отсутствие противоречий;
6. не изменять уже опубликованные frozen `releases/<version>`;
7. не добавлять secrets в документацию, diagnostics или примеры.
