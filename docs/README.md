# Control Center — индекс документации

Этот каталог разделяет текущую эксплуатационную документацию, документацию major-линии, историю релизов, планы и исторические материалы. Цель структуры — не смешивать production-инструкции с roadmap и документами старых релизов.

## 1. Начать здесь

- **`PRODUCT-MANUAL-RU.md`** — каноническое русскоязычное руководство пользователя и администратора.
- **`INSTALL.md`** — чистая установка и первичная проверка.
- **`SYSTEM-ADMIN.md`** — authentication, NSS/PAM/winbind, RBAC и privileged administration.
- **`AUTO-UPDATES.md`** — обновления Control Center.
- **`DEPLOYMENT-RELIABILITY.md`** — preflight/apply/acceptance/rollback.

## 2. Текущая major-линия 2.x

Каталог **`2.0/`** содержит version-specific материалы baseline 2.0:

- `2.0/README.md` — индекс линии 2.x;
- `2.0/ADMIN-GUIDE.md` — административные операции 2.0;
- `2.0/RELEASE-2.0.0.md` — состав и ограничения 2.0.0;
- `2.0/UPGRADE-1.x-TO-2.0.md` — миграция с 1.x;
- `2.0/VALIDATION.md` — release/acceptance validation.

Эти документы дополняют каноническое руководство, но не заменяют `deployment.json` и frozen manifest как технический источник истины.

## 3. Production, runtime и development

Текущий production target определяется **только `../deployment.json`**. Сейчас опубликован **Control Center 2.0.0**.

Нужно различать:

- **production target** — версия из `deployment.json`;
- **frozen implementation** — `../releases/<active-version>`;
- **runtime version** — реально установленная версия конкретного сервера из `server-state`/`release.json`;
- **development** — ветки `release/*`, draft PR и будущий scope из roadmap.

Наличие кода или документа в development branch не делает функцию production-функцией.

## 4. История и планирование

- `RELEASE-HISTORY.md` — опубликованная история версий и repairs;
- `ROADMAP.md` — будущая разработка;
- `PRODUCT-EDITIONS.md` — редакции, licensing architecture и lifecycle;
- `BRANDING.md` — правила публичного имени и бренда продукта.

Roadmap не является эксплуатационной инструкцией и не подтверждает наличие функции в production.

## 5. Исторические документы

`RELEASE-1.1.0-SCOPE.md`, `RELEASE-1.2.0-SCOPE.md`, `RELEASE-1.3.0-SCOPE.md`, старые incident/diagnostic notes и аналогичные материалы сохраняются как исторические свидетельства соответствующих релизов.

Они могут содержать устаревшие названия, временные ограничения, старые deployment paths или исправленные дефекты. Такие сведения нельзя переносить в текущую эксплуатацию без проверки по active release.

В частности, ранние инструкции про отдельного bootstrap web-user/password и `admin-bootstrap.txt` не применимы к современной цепочке NSS/PAM/winbind → authentication → RBAC.

## 6. Источники истины

При противоречии используйте следующий приоритет:

1. `../deployment.json` — опубликованный production target;
2. `../releases/<active-version>` — frozen manifest и реализация;
3. актуальный `server-state` — runtime конкретного сервера;
4. `RELEASE-HISTORY.md` — release lineage;
5. `PRODUCT-MANUAL-RU.md` и профильные current docs;
6. `ROADMAP.md` — будущий scope;
7. release-specific и incident documents — исторический контекст.

## 7. Правила для текстовых файлов

Текущие документы должны:

- использовать публичное имя **Control Center**;
- явно указывать, если материал исторический, version-specific или future/planning;
- не дублировать secrets, tokens, passwords, private keys и содержимое backup;
- не объявлять roadmap-функцию production-функцией без подтверждения active frozen payload;
- не фиксировать номер «текущей версии» без необходимости; если номер указан, он должен совпадать с `deployment.json`;
- ссылаться на каноническое руководство вместо создания конкурирующих общих инструкций;
- отделять authentication от RBAC authorization;
- отделять product update от OS package maintenance;
- отделять scheduled backup от backup-before-update;
- сохранять frozen `releases/*` неизменными.

## 8. Обновление документации при релизе

Для каждого нового production release обязательно:

1. сверить `deployment.json` и frozen manifest;
2. обновить `RELEASE-HISTORY.md`;
3. обновить `PRODUCT-MANUAL-RU.md`;
4. обновить version-specific release docs;
5. обновить профильные current docs, если изменилось поведение;
6. убрать выпущенный scope из будущего roadmap;
7. проверить внутренние ссылки, названия, версии и термины;
8. проверить отсутствие секретов;
9. не изменять frozen payload предыдущих релизов.

Документация является частью release acceptance.
