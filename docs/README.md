# Control Center — документация

Этот каталог содержит текущую эксплуатационную документацию, roadmap, release history и исторические release-specific материалы.

## С чего начать

- **`PRODUCT-MANUAL-RU.md`** — каноническое русскоязычное руководство пользователя и администратора.
- **`INSTALL.md`** — чистая установка.
- **`SYSTEM-ADMIN.md`** — authentication, PAM/NSS, RBAC и privileged administration.
- **`AUTO-UPDATES.md`** — automatic/manual GitHub product updater.
- **`DEPLOYMENT-RELIABILITY.md`** — preflight/apply/acceptance/rollback модель.
- **`ROADMAP.md`** — текущее направление разработки 2.x; roadmap не является инструкцией по production-функциям.

## Источники истины

При расхождении документов используйте следующий приоритет:

1. `../deployment.json` — активный production target;
2. `../releases/<active-version>` — frozen release implementation/manifest;
3. актуальный `server-state` — фактическое состояние конкретного сервера;
4. `RELEASE-HISTORY.md` — история публикаций и repair-релизов;
5. `PRODUCT-MANUAL-RU.md` — текущая пользовательская/административная инструкция;
6. `ROADMAP.md` — будущий scope и направление разработки.

## Production и development

Текущий production target определяется только `../deployment.json`. На момент перехода документации к 2.x production остаётся в линии **1.3.8**, а разработка нового major release ведётся отдельно как **2.0.0** до прохождения полного release gate.

Не следует считать наличие реализации в development branch или draft PR признаком production-доступности функции.

## Текущая и историческая документация

`RELEASE-*.md`, incident notes и implementation-specific документы сохраняются как исторические источники. Их нельзя автоматически трактовать как описание текущей production-линии.

Например, инструкции ранних 0.x релизов про отдельный bootstrap web-user/password не применимы к современной PAM/NSS/winbind/RBAC architecture.

Старые 1.x планы выпуска также не определяют порядок будущих релизов: актуальный roadmap переведён на линию **2.x**, а опубликованная история 1.x фиксируется в `RELEASE-HISTORY.md` и frozen manifests.

## Product planning

- `ROADMAP.md` — согласованное текущее направление разработки 2.x;
- `PRODUCT-EDITIONS.md` — редакции, licensing architecture и lifecycle;
- `RELEASE-HISTORY.md` — опубликованная release lineage.

Наличие функции в roadmap не означает её наличие в текущем production release.

## Правило обновления документации

При каждом новом опубликованном product release необходимо:

1. сверить `deployment.json` и manifest нового release;
2. обновить `RELEASE-HISTORY.md`;
3. обновить `PRODUCT-MANUAL-RU.md` для пользовательски значимых изменений;
4. обновить профильные документы (`SYSTEM-ADMIN.md`, `AUTO-UPDATES.md`, `INSTALL.md` и т. п.), если изменилась соответствующая архитектура;
5. обновить `ROADMAP.md`, если release изменил порядок или границы будущего scope;
6. проверить ссылки и отсутствие противоречий;
7. не изменять уже опубликованные frozen `releases/<version>`;
8. не добавлять secrets в документацию, diagnostics или примеры.

Документация является обязательной частью release acceptance: новый релиз не должен считаться полностью готовым, пока инструкция и release history не соответствуют фактической реализации.
