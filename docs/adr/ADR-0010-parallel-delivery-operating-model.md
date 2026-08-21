# ADR-0010: Параллельная операционная модель разработки Control Center

- Статус: принято
- Дата: 2026-08-21
- Область: engineering operating model / delivery governance / автономная разработка

## Контекст

Control Center развивается одновременно как серверная платформа, инфраструктурный продукт, основной Admin Web, публичный сайт, клиентский кабинет, административный кабинет сайта, Android-клиенты, набор внешних интеграций и управляемый серверный контур.

Максимальная скорость достигается не простым увеличением числа параллельных веток, а строгим разделением владельцев кода, последовательным прохождением quality/security/release gates и минимизацией пересечения файлов. Отдельные feature-потоки должны выпускать небольшие законченные vertical slices, а не создавать широкие незавершённые инициативы.

Пользователь разрешил максимально автономную работу через все фактически доступные подключения к GitHub, сайту, тестовому серверу и связанным системам, включая самостоятельный запуск безопасных скриптов, диагностики, тестов, staging, обновлений и rollback. Это разрешение не отменяет требования защиты секретов, минимальных привилегий и обязательного recovery path.

Разработка iOS исключена. Мобильное направление Control Center ограничено Android до отдельного нового решения.

## Решение

Постоянный operating model состоит из 15 независимых контуров. Каждый контур имеет собственную зону владения, WIP-лимит и запрет на скрытое расширение области ответственности.

### 1. Core A — Platform / Identity / Operations

- Приоритет: P0.
- Владеет Native Authentication, Identity, RBAC, users/roles/scopes, sessions, CSRF/origin policy, Audit, Health, Notifications, Change/Jobs, Desired/Actual State, Automation foundation, Licensing/Entitlements, Fleet/multi-server foundation, Search, Operations/Incidents и общими platform contracts.
- Не реализует основной пользовательский UI, кроме минимального технического покрытия, необходимого для проверки контракта.
- Не изменяет инфраструктурные модули Core B без отдельного shared-contract change.

### 2. Core B — Infrastructure

- Приоритет: P0/P1.
- Владеет Network shared model, DNS, DHCP↔DNS orchestration, IPAM, File Services, Storage, Backup/Restore, VPN, Reverse Proxy/App Gateway и Firewall.
- Использует общие Identity/RBAC/Jobs/Audit/Secrets contracts Core A.
- Не создаёт собственные параллельные RBAC, Scheduler, Secret Store, Notification System или State Model.
- Любая потенциально разрывающая управление сетью или хранилищем операция требует preview, preflight, verify и rollback/recovery path.

### 3. Experience — Control Center Admin Web

- Приоритет: P0.
- Владеет пользовательской функциональностью основного Web-интерфейса Control Center.
- Подключает только принятые или явно согласованные Core contracts.
- Не дублирует серверную логику и не создаёт параллельные клиентские модели состояния.
- Для каждого Core slice поддерживает связь: Core capability → Web workflow → acceptance evidence.

### 4. Website Product / UX / CRO

- Приоритет: P1.
- Владеет публичным сайтом: информационной архитектурой, контентом, CTA, pricing/offer presentation, onboarding funnel, trust blocks, SEO semantics и конверсионными маршрутами.
- Не владеет клиентским кабинетом, административным кабинетом сайта и крупным визуальным рефакторингом.
- Изменяет UI только в объёме, необходимом для конкретного UX/CRO vertical slice.

### 5. Client Portal

- Приоритет: P1.
- Владеет клиентским личным кабинетом сайта: регистрацией/профилем, лицензиями и entitlements presentation, привязанными продуктами/серверами, downloads, support entry points, notifications/preferences, security/session UX и безопасными self-service workflows.
- Не выполняет финансовые или привилегированные операции вне существующих серверных контрактов.
- Не изобретает отдельную backend-модель при отсутствии контракта; вместо этого создаёт точный contract request с evidence.

### 6. Website Admin

- Приоритет: P1.
- Владеет административным кабинетом сайта: пользователями/клиентами, лицензиями/entitlements, контентом/предложениями, support/admin workflows, moderation, audit/status views и операционными действиями сайта.
- Все административные операции обязаны использовать действующие RBAC/auth/audit/CSRF/security boundaries.
- Запрещены обходные privileged endpoints и client-side-only проверки доступа.

### 7. Android Platform & Client

- Приоритет: P1.
- Владеет `control-center-android-sdk` и `control-center-android-client`.
- Поддерживает стабильные typed contracts, session handling, read-only/low-risk client workflows и пользовательское Android-приложение.
- Не изменяет server contracts самостоятельно. Изменение server contract проходит через владельца Core и shared-contract process.
- Является владельцем изменений общего Android SDK; Android Admin передаёт запросы на SDK через contract request.

### 8. Android Admin

- Приоритет: P1.
- Владеет `control-center-android-admin`.
- Реализует административные Android-сценарии только поверх принятого SDK и серверных RBAC contracts.
- Не дублирует сложную Web-конфигурацию, если безопасный мобильный сценарий не обоснован.
- Не изменяет общий SDK напрямую при наличии активной ветки Android Platform & Client.

### 9. Integrations & AI Gateway

- Приоритет: P1.
- Владеет OpenAI, Gemini, Perplexity, Яндекс и другими внешними API через единый integration layer.
- Централизует provider adapters, timeouts, retries, quotas, audit, secret references и degraded-mode behavior.
- Не помещает provider-specific логику в Core-модули и пользовательские интерфейсы.
- Любые внешние ответы считаются недоверенными данными и проходят schema validation и output sanitization.

### 10. Website Visual / Layout

- Приоритет: P1.
- Владеет дизайн-системой и визуальной реализацией публичного сайта, Client Portal и Website Admin: typography, spacing/grid, responsive layout, graphics/assets, cards, forms, tables, navigation и micro-interactions.
- Не меняет содержание, CTA/CRO strategy и бизнес-семантику.
- Работает после стабилизации структуры feature-изменения и не ведёт массовый рефакторинг одновременно с активной feature-веткой в тех же файлах.

### 11. Control Center Visual UI

- Приоритет: P1.
- Владеет Calm Infrastructure design language основного Control Center: shared tokens/components, data-dense tables, forms, navigation, status/health visualization, charts/graphics, empty/loading/error states и responsive desktop/tablet layout.
- Не меняет бизнес-логику и Core contracts.
- Улучшает уже существующие или стабилизированные Experience workflows, чтобы не конкурировать за одни и те же файлы.

### 12. Contract & Regression QA

- Приоритет: P0-GATE.
- Владеет contract/integration/regression/negative-path coverage, permission/RBAC matrices, idempotency, rollback, Desired/Actual-state checks, fixtures и acceptance evidence.
- Предпочитает test/fixture/evidence-only изменения и минимальные test hooks.
- При регрессии создаёт воспроизводимый failing test и передаёт исправление владельцу функциональности.
- Не переписывает продуктовую семантику параллельно с feature-потоком.

### 13. Security Review

- Приоритет: P0-GATE.
- Является независимым обязательным security gate для всех потоков.
- Выполняет threat modeling, risk-based security diff review для security-sensitive изменений, secret/dependency/supply-chain checks, validation находок и attack-path analysis.
- Для release candidate выполняет scoped repository scan затронутых компонентов.
- Подтверждённые Critical/High findings блокируют обычный релиз до исправления и повторной проверки. Medium блокирует при реальном exploitable path или существенном бизнес-риске.
- Security-fix выполняется отдельной минимальной backward-compatible веткой с регрессионным тестом.

### 14. Ops / Test Server

- Приоритет: P0-ENABLER.
- Владеет `control-center-server-diagnostics`, remote agent/control plane, CI/CD, real staging, test-server preparation, update/rollback, health/readiness, bounded diagnostics, Nginx/systemd/runtime checks и безопасными серверными скриптами.
- Если агент, transport или staging блокирует продуктовый slice, blocker временно получает P0 и устраняется первым.
- Любое изменение сервера требует preflight и recovery path; после изменения проверяются version, health, readiness, services, agent state и rollback readiness.
- Запрещено расширять arbitrary shell/caller-controlled privileged surface.

### 15. Integrator / Release / Documentation

- Приоритет: P0-GATE.
- Единственный контур, выполняющий финальную интеграцию, merge, release promotion и синхронизацию canonical documentation.
- Не создаёт feature scope.
- Перед merge сверяет exact head SHA, mergeability, required CI, security evidence, regression evidence, Web/Android acceptance, real staging и test-server identity.
- После фактической интеграции обновляет README, current-state, architecture, security docs, ADR, user/admin manuals, release notes, changelog и Google Drive references.
- Frozen release records не изменяются.

## Репозитории и исключения

К модели относятся:

- `ControlCenterSoft/srv-deployment`;
- `ControlCenterSoft/control-center-website`;
- `ControlCenterSoft/control-center-server-diagnostics`;
- `ControlCenterSoft/control-center-android-sdk`;
- `ControlCenterSoft/control-center-android-client`;
- `ControlCenterSoft/control-center-android-admin`.

`ControlCenterSoft/chat_gpt_mobile_client` является отдельным проектом мониторинга задач ChatGPT и не входит в Control Center delivery model.

iOS-репозитории, iOS CI, App Store workflows, iOS parity, iOS documentation и iOS release gates отсутствуют.

## WIP, ветки и защита от конфликтов

- Каждый feature-поток поддерживает WIP=1 на один репозиторий: один небольшой законченный vertical slice до Definition of Done.
- Используются короткие ветки вида `feature/<area>-<slice>`, `fix/<area>-<defect>`, `security/<area>-<finding>` или `docs/<topic>`.
- Для одновременной локальной работы используются отдельные worktrees/isolated checkouts.
- Перед изменением выполняются fetch, проверка актуальной base branch, открытых PR и изменяемых путей.
- Прямой push и force-push в `main`, release branches и общие ветки запрещён.
- Feature-потоки создают PR, но финальный merge выполняет Integrator.
- При пересечении активных файлов поток выбирает другой slice либо создаёт contract request; параллельное редактирование одного shared component запрещено.
- Shared-contract PR минимален, backward-compatible, содержит consumer tests и явный список зависимых потоков.
- Visual-потоки работают после стабилизации структуры feature-ветки; QA/Security преимущественно работают в tests/evidence или отдельных fix-ветках.

## Definition of Done

Законченный product slice включает применимые:

- object/API contract;
- RBAC/permissions metadata;
- audit semantics;
- validation и стабильную error model;
- Desired/Actual state;
- preview/apply/verify/recovery для изменяющих операций;
- health/diagnostics;
- UI или Android workflow;
- unit/contract/integration/regression tests;
- security review evidence;
- staging/acceptance evidence;
- upgrade/rollback compatibility;
- release notes и пользовательскую документацию после интеграции.

Код без законченного пользовательского или административного workflow не считается завершённым feature scope.

## Security pipeline

1. До реализации определяется security impact и актуализируется threat model затрагиваемой границы.
2. Каждый PR проходит secret, dependency, policy и релевантные static checks.
3. Security-sensitive diff проходит независимый risk-based review всех изменённых и удалённых файлов с переходом в supporting code.
4. Кандидаты проходят validation; подтверждённые reportable findings — attack-path analysis.
5. Release candidate проходит scoped repository audit затронутой attack surface.
6. Исправление подтверждается regression test и повторным review на exact fix SHA.
7. Runtime/staging проверяет auth/RBAC/CSRF/session behavior, privileged operations, update/rollback и отсутствие утечки секретов в логах.

## Автономная работа и серверные операции

Все контуры используют без дополнительного запроса доступные безопасные подключения к GitHub, Google Drive, сайту, тестовому серверу, агенту, CI и observability systems.

Разрешены автономные обратимые действия: branches, commits, PR, CI reruns, тесты, диагностика, staging, backup, migrations с rollback, server scripts, service reload/restart в пределах recovery plan, test-server update и acceptance.

Пользователь привлекается только когда:

1. требуется интерактивная OAuth/MFA-авторизация, недоступная подключённым инструментам;
2. отсутствует фактическое подключение или необходимое разрешение;
3. действие необратимо или не имеет проверенного recovery path;
4. требуется бизнес-решение с существенным необратимым эффектом.

Запрещено раскрывать credentials, помещать secrets в код/PR/логи, обходить защитные границы или ослаблять auth/RBAC ради автоматизации.

## Модельная политика

Каждый автономный контур использует максимально сильную доступную для среды модель с наивысшим оправданным reasoning/coding уровнем. Выбор модели динамический: при появлении более сильной совместимой модели она становится предпочтительной без изменения этого ADR.

- Core, Integrations, Security, Ops и Integrator используют максимальный reasoning.
- Web, Android и кабинеты используют максимальную coding capability с высоким reasoning.
- Visual-потоки используют наиболее сильную доступную мультимодальную capability.
- QA использует максимальный reasoning и воспроизводимые deterministic checks.

Модель не заменяет CI, security review, staging и exact-SHA release gates.

## Порядок общего цикла

Логическая последовательность цикла:

1. Core A и Core B производят независимые contracts/capabilities.
2. Integrations, Website, Client Portal, Website Admin и Android развиваются в своих репозиториях и границах.
3. Experience покрывает принятые Core capabilities в Admin Web.
4. Visual-потоки улучшают стабилизированные workflows.
5. Contract & Regression QA формирует regression evidence.
6. Security Review проверяет релевантный diff и release surface.
7. Ops выполняет real staging/test-server evidence.
8. Integrator проверяет exact heads, интегрирует, выпускает и синхронизирует документацию.

Потоки не обязаны ждать полного завершения предыдущего пункта для независимой работы, но merge/release следует указанной dependency chain.

## Release governance

Обычный product release разрешён только если:

- содержит минимум одну завершённую User-facing improvement;
- пользовательский workflow реально доступен в Admin Web, сайте, Client Portal, Website Admin или Android;
- required CI зелёный на exact head;
- contract/regression evidence пройдено;
- нет подтверждённых блокирующих security findings;
- staging и health/readiness успешны;
- rollback/recovery проверен;
- установленная версия соответствует release metadata и exact commit SHA;
- документация и release notes синхронизированы.

Android acceptance обязателен только для релиза, содержащего Android-изменения. Отсутствие iOS никогда не является blocker.

Emergency maintenance/security/hotfix допускается без новой user-facing функции только при объективном production/security риске и с явной маркировкой.

## Отчётность

Рутинные отдельные сообщения каждого потока не отправляются. Integrator формирует одну общую фактическую сводку завершённого цикла. Отдельно немедленно сообщаются только:

- подтверждённый Critical/High security blocker;
- release-blocking regression;
- недоступность критического внешнего ресурса;
- необходимость интерактивного действия пользователя;
- новый успешно выпущенный релиз.

## Следствия

- Владение кодом становится явным, а количество конфликтующих PR уменьшается.
- Core, сайт, кабинеты, Android, интеграции и дизайн могут развиваться параллельно.
- QA, Security, Ops и Integrator разгружают feature-потоки от повторяющейся работы.
- Документация следует за фактической интеграцией, а не за планируемым кодом.
- Тестовый сервер и rollback являются частью Definition of Done.
- iOS не потребляет ресурсы и не задерживает релизы.
- Автономность ускоряет delivery, но не отменяет security boundaries и recovery requirements.
