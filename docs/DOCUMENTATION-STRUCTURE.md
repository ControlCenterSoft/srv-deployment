# Control Center — структура и правила документации

Этот документ задаёт классификацию текстовой документации репозитория. Он не является описанием product-функций.

## Классы документов

### Current / canonical

Документы, которые должны соответствовать активному production release:

- `../README.md`;
- `README.md`;
- `PRODUCT-MANUAL-RU.md`;
- `INSTALL.md`;
- `SYSTEM-ADMIN.md`;
- `AUTO-UPDATES.md`;
- `DEPLOYMENT-RELIABILITY.md`;
- `BRANDING.md`;
- `PRODUCT-EDITIONS.md` — только в части действующей product/licensing policy.

### Version-specific

Документы в `2.0/` относятся к major/release baseline 2.0 и должны явно указывать свою версионную область.

### Release history

`RELEASE-HISTORY.md` фиксирует опубликованную lineage. Исторический факт не переписывается как текущая инструкция.

### Planning

`ROADMAP.md` описывает будущий scope. Он не подтверждает наличие функции в production.

### Historical

`RELEASE-*-SCOPE.md`, incident notes, старые migration/diagnostic материалы и документы прошлых архитектур сохраняются для истории. При необходимости в их начале добавляется явная пометка `Historical` без переписывания самого исторического содержания.

### Machine/runtime text

Shell/Python/YAML/JSON и другие текстовые файлы реализации не являются пользовательской документацией. Их комментарии, help-тексты и сообщения должны использовать актуальную терминологию, но frozen `releases/*` после публикации не редактируются.

## Нормализация терминов

Публичное имя продукта — **Control Center**. Устаревшие названия допустимы только внутри исторических цитат, legacy identifiers, путей, systemd unit names, package/script names и других технических идентификаторов, изменение которых нарушило бы совместимость.

Термины должны различать:

- authentication и authorization/RBAC;
- production target и runtime installed version;
- release existence и release publication;
- product update и OS package update;
- scheduled backup и backup-before-update;
- current functionality и roadmap scope.

## Версионность

Если current-документ содержит конкретный номер production release, при каждом релизе он проверяется против `deployment.json`. Предпочтительно формулировать долгоживущие правила без жёстко зашитой версии, а конкретный номер использовать там, где он действительно помогает пользователю.

## Безопасность

Запрещено помещать в документацию реальные passwords, tokens, cookies, session secrets, private keys, recovery secrets и содержимое backup archives. Примеры должны использовать очевидные placeholders.

## Frozen policy

`releases/<published-version>` не редактируется для исправления текста, комментариев или документации. Ошибка frozen payload исправляется новым release; ошибка внешней документации исправляется в `docs/`/README отдельным documentation change.

## Release documentation gate

Перед публикацией нового release проверяются:

1. production metadata;
2. canonical manual;
3. documentation index;
4. release history;
5. version-specific docs;
6. профильные administration/update/install docs;
7. roadmap;
8. ссылки и терминология;
9. отсутствие секретов;
10. отсутствие изменений предыдущих frozen releases.
