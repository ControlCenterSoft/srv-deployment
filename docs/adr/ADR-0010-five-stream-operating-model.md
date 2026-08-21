# ADR-0010: Пятиконтурная операционная модель разработки Control Center

- Статус: принято
- Дата: 2026-08-21
- Область: engineering operating model / delivery governance

## Контекст

Скорость разработки Control Center ограничивается уже не только написанием кода, но и конкуренцией за общий backlog, конфликтами между параллельными изменениями, staging/acceptance и несинхронным покрытием Web/Mobile. Для ускорения выхода на рынок продуктовая разработка должна быть разделена на независимые потоки с одним интеграционным центром.

## Решение

Основной постоянный operating model проекта состоит из пяти контуров.

### 1. Core A — Platform / Identity / Operations

Высший продуктовый приоритет. Владеет Native Authentication, Identity, RBAC, users/roles/scopes, Audit, Health, Notifications, Change/Jobs, Desired/Actual State, Automation foundation, Licensing/Entitlements, Search, Operations/Incidents и общими platform contracts.

Коммерческий приоритет нулевого уровня после secure foundation — ранний Fleet/multi-server foundation: enrollment, inventory, health, version/update, diagnostics, groups и безопасные low-risk actions для нескольких серверов без ожидания полного Enterprise scope.

### 2. Core B — Infrastructure

Второй основной продуктовый поток. Владеет Network shared model, DNS, DHCP↔DNS, IPAM, File Services, Storage, Backup, VPN, Reverse Proxy/App Gateway и Firewall. Использует общие Identity/RBAC/Jobs/Audit/Secrets contracts Core A и не создаёт параллельные platform services.

### 3. Ops / Test Server

Enabler-контур. Владеет безопасным remote agent/control plane, real staging, test-server preparation, update/rollback, health/readiness и bounded diagnostics. Его KPI — сокращать время от готового product slice до подтверждённого real-server evidence. Если Ops/staging блокирует product delivery, такой blocker временно получает P0.

### 4. Experience — Admin Web / Mobile / Website

Владеет пользовательским представлением новых Core capabilities. Приоритет: Admin Web coverage → Mobile Client/Admin coverage для применимых сценариев → UX/accessibility/performance → публичный сайт/CRO. Для каждой новой функции поддерживается связь Core feature → Web coverage → Mobile coverage → acceptance evidence. Сложная конфигурация не обязана полностью дублироваться на мобильном устройстве; допускается эквивалентный безопасный mobile workflow.

### 5. Integrator + Docs

Единый integration/release gate. Не конкурирует за feature backlog. Собирает только готовые зелёные изменения, контролирует shared contracts, exact-head merges, required CI, Full Acceptance, real staging, release promotion, состояние test server и синхронизацию документации после фактической интеграции.

## Приоритеты ресурсов

1. Core A — основной приоритет пользовательского и коммерческого functional throughput.
2. Core B — параллельный основной производитель Professional infrastructure functionality.
3. Experience — функциональное Web/Mobile покрытие уже реализованных Core slices; публичный marketing site ниже продуктового покрытия.
4. Ops/Test Server — постоянный enabler; любой delivery-blocker автоматически повышает его до P0 до устранения.
5. Integrator+Docs — обязательный gate и orchestration layer, но не отдельный производитель feature scope.

При конфликте между чисто технической оптимизацией и завершением безопасного user-facing vertical slice приоритет получает vertical slice, если техническая работа не является его прямой зависимостью или security/reliability blocker.

## WIP и границы владения

- Core A и Core B поддерживают WIP=1: по одному активному vertical slice до Definition of Done.
- Потоки не начинают параллельно широкие незавершённые инициативы.
- Shared contracts меняются минимально, backward-compatible и с явной dependency для Integrator.
- Не допускаются отдельные RBAC, Scheduler, Secret Store, Notification System или State Model внутри модулей.

## Definition of Done для product slice

Законченный slice включает применимые API/Object Model, UI, permissions/RBAC, Desired/Actual state, validation/apply/verify/recovery, health, audit, diagnostics, tests, upgrade compatibility и acceptance evidence. Наличие кода без пользовательского рабочего сценария не считается завершением feature scope.

## Release governance

Каждый обычный product release обязан содержать минимум одну завершённую User-facing improvement, реально доступную пользователю и подтверждённую acceptance evidence. Технические изменения могут интегрироваться и накапливаться, но не инициируют обычный продуктовый release самостоятельно. Emergency maintenance/security/hotfix остаётся ограниченным исключением по отдельной release policy.

## Часовой цикл

Рабочие потоки выполняются последовательно в пределах одного цикла: Core A → Core B → Ops/Test Server → Experience → Integrator+Docs. Integrator завершает цикл после остальных потоков, чтобы видеть их фактические результаты и не интегрировать устаревший head.

После каждого завершённого общего цикла пользователю отправляется одна минимальная сводка по пяти контурам. Промежуточные штатные уведомления отдельных потоков не отправляются; исключение — критический blocker, требующий пользовательского действия.

## Следствия

- Больше доступного времени тратится на пользовательские vertical slices, а не на docs-only и infrastructure-only activity.
- Core Platform и Infrastructure могут развиваться параллельно с меньшим количеством конфликтов.
- Web и Mobile не становятся отдельными несинхронными продуктами.
- Test server и acceptance остаются частью Definition of Done, а не завершающим ручным этапом.
- Документация следует за фактической интеграцией и не занимает отдельный автономный продуктовый слот.
- Ранний multi-server/Fleet foundation становится приоритетным рыночным differentiator до тяжёлого Enterprise scope.
