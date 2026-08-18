# Control Center — документация

Этот каталог содержит текущую эксплуатационную документацию, roadmap, release history и исторические release-specific материалы.

## С чего начать

- **[`PRODUCT-MANUAL-RU.md`](PRODUCT-MANUAL-RU.md)** — каноническое русскоязычное руководство пользователя и администратора.
- [`INSTALL.md`](INSTALL.md) — чистая установка.
- [`SYSTEM-ADMIN.md`](SYSTEM-ADMIN.md) — PAM/NSS, domain identity, RBAC и privileged administration.
- [`AUTO-UPDATES.md`](AUTO-UPDATES.md) — automatic/manual GitHub product updater.
- [`DEPLOYMENT-RELIABILITY.md`](DEPLOYMENT-RELIABILITY.md) — preflight/apply/acceptance/rollback.
- [`RELEASE-HISTORY.md`](RELEASE-HISTORY.md) — опубликованная release lineage.
- [`ROADMAP.md`](ROADMAP.md) — будущая разработка; не инструкция по production-функциям.

## Источники истины

При расхождении используйте следующий приоритет:

1. `../deployment.json` — опубликованный production target;
2. `../releases/<active-version>` — frozen implementation, manifest и acceptance активной версии;
3. актуальный `server-state`/`release.json` — фактическое состояние конкретного сервера;
4. `RELEASE-HISTORY.md` — история публикаций/repairs;
5. `PRODUCT-MANUAL-RU.md` и профильные эксплуатационные документы;
6. `ROADMAP.md` — будущий scope;
7. release-specific incident/scope notes — исторический контекст.

Сейчас `deployment.json` публикует **2.1.0**. Наличие более новой реализации в branch/PR само по себе не означает production-доступность.

## Текущая и историческая документация

`RELEASE-*.md`, incident notes и implementation-specific документы сохраняются для трассируемости и не переписываются так, будто описывают текущую систему. Устаревшие утверждения (например, ранний bootstrap web-password) применимы только к соответствующей исторической версии.

## Правило обновления документации

При каждом новом product release необходимо сверить `deployment.json` и frozen manifest/acceptance, обновить release history и каноническое руководство, затем профильные документы и roadmap. Проверяются ссылки, версии и отсутствие противоречий. Опубликованные `releases/<version>` не изменяются, secrets в документацию и diagnostics не добавляются.

Документация является частью release acceptance: пользовательски значимые изменения должны быть отражены одновременно с публикацией версии.