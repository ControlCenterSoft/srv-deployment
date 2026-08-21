# Control Center — текущее подтверждённое состояние

Дата сверки: 2026-08-22.

Этот документ описывает **фактическое подтверждённое состояние** по коду, release metadata, GitHub CI и runtime/staging evidence. При расхождении с планами или старыми документами приоритет имеют exact release metadata и проверяемое CI/runtime evidence.

## Production

- Канонический production release серверного Control Center: **1.0.0**.
- `deployment.json`: `channel=stable`, `status=production-ready`, `acceptance=passed`.
- Accepted source commit: `1b364ae88789696bf98537d21544de8a259d086d`.
- Production promotion серверного продукта на 1.1.x не выполнялся.

## Development 1.1.x

- Интеграционная ветка: `1.1.x`.
- Exact HEAD после gated merge AI provider transport PR `#142`: `bbbd4b586b61a1ad7a4c673bef5515edd54e767e`.
- Приняты DNS resolver actual-state inventory и безопасный admin-only resolver preview с Desired/Actual/Rollback моделью, no-op detection, validation/audit и `apply_supported=false`.
- Принят shared AI provider transport для Gemini/Perplexity с HTTPS/host allowlist, fail-closed redirects, bounded timeout/retry/response и без отражения provider error bodies/redirect targets в surfaced errors.
- Resolver/service mutations пока не включены.

## Последний подтверждённый staging candidate

Последний exact candidate, полностью прошедший real test-server Full Acceptance для серверного продукта: **1.1.0-rc.6** / `302eb6da97324d719849e7ae752fc10bdc557d9a`.

Для этого exact SHA подтверждены Fast CI, Contract & Regression QA, Independent Security Review и Full Acceptance / real test-server staging. После последующих merge интеграционный HEAD изменился, поэтому это staging evidence не повышает текущий `1.1.x` до production-ready автоматически.

## Текущие gated кандидаты

### Core B DNS preflight

PR `#161`, exact head `ca0d610aca75d3838c5d10eb841182529a95fc4d`:

- ранее подтверждены Fast CI, Contract & Regression QA и Independent Security Review на этом exact SHA;
- `apply_supported=false`, privileged mutation не добавлена;
- GitHub сейчас сообщает `mergeable=true` относительно текущей `1.1.x`;
- Ops/Test Server staging/runtime evidence для этого exact SHA не подтверждено.

До интеграции требуется неизменившийся exact head с полным применимым gate набором и требуемым test-server staging/runtime evidence.

### Admin Web Audit

PR `#141`, exact head `2303ab818388b5356f0c57eea6a08529540756ac`:

- ранее подтверждены Fast CI, Contract & Regression QA, Frontend Quality и Independent Security Review на этом exact SHA;
- GitHub сейчас сообщает `mergeable=true` относительно текущей `1.1.x`;
- Ops/Test Server staging evidence на этом exact SHA не подтверждено.

До интеграции требуется неизменившийся exact head и успешный test-server staging/runtime acceptance.

### Core A Fleet disconnect

PR `#139`, exact head `e457678c3e3f14460cd4bb16516242ee21ac2fb4`, сейчас `mergeable=true`. Recovery claim всё ещё требует полного `disconnect → fresh enrollment → fresh heartbeat` regression coverage из test-only PR `#143`. После интеграции этих тестов head изменится и прежние exact-SHA QA/Security evidence станут устаревшими; потребуется свежий полный gate набор и test-server staging.

### Control Center Visual UI

PR `#138`, exact head `a38e2668c80a8f307722638d3ccd495a601f08f8`, сейчас `mergeable=true`. Перед Integrator merge требуется полный применимый exact-SHA CI/QA/Frontend Quality/Security набор и требуемое test-server runtime/staging evidence на неизменившемся candidate SHA.

### AI Gateway

PR `#142`, exact reviewed head `5653b0c1c33494e24ced7b4ffc882bd45ebe813d`, прошёл Fast CI, Contract & Regression QA, Independent Security Review и был интегрирован P0 Integrator в `1.1.x` merge commit `bbbd4b586b61a1ad7a4c673bef5515edd54e767e`.

Это внутренний advisory AI transport/security slice без product/Core/Admin Web/runtime/release authority; отдельный обычный product release из-за него не создаётся, потому что он не является завершённой User-facing improvement.

Security-fix PR `#164` для Perplexity routine queue имеет Contract & Regression QA PASS и Security Review PASS на exact head `883b69d532e1bf6640011a07455e1c04c00def2e`, но собственного PR-triggered deterministic CI run на этом exact head по-прежнему нет. Поэтому Integrator не объединяет `#164` в parent `#150` до появления применимого exact-SHA CI evidence.

PR `#150` и default-branch dispatcher `#151` остаются заблокированы. После будущей интеграции hardened transport в `#150` его head изменится и потребует свежих exact-SHA CI/QA/Security evidence; `#151` должен быть перепривязан к новому immutable parent SHA и повторно пройти требуемые gates. Frozen-main allowlist остаётся обязательным ограничением.

## Test server / Ops Agent

- На последнем подтверждённом typed preflight test server сообщал Control Center **1.1.0-rc.6** / `302eb6da97324d719849e7ae752fc10bdc557d9a`.
- Установленный Ops Agent/Broker: **1.1.8**.
- Diagnostics PR `ControlCenterSoft/control-center-server-diagnostics#14`, exact head `d4337bdd5f3111431ee06858fcd0d3338655751c`: CI PASS, Contract & Regression QA PASS, Independent Security Review PASS; agent candidate version **1.1.10**.
- P0 staging enabler PR `srv-deployment#170`, exact head `6e15da1863701c497b39bbcf401829dd89024132`, сейчас `mergeable=true`; Fast CI и `Test ops agent bootstrap` успешны.
- На exact head `#170` независимый Security Review дал **BLOCKED**: обнаружены downgrade/replay и race risks в passwordless restricted updater path. Минимальный hardening подготовлен в stacked PR `#171` (`8f2755bcc80806675dd7fd9daee01d6916cf6d60`).
- На том же exact head `#170` Contract & Regression QA дал **FAIL**: builder не доказывает `source_commit + source_path ↔ authoritative Git blob` до подписания. Failing regression evidence зафиксирован в `#174`; fail-closed provenance fix подготовлен в stacked PR `#175` (`a2ac42ad55d1fa5e82b5e2f31b734cb11d30b958`) поверх `#171`.
- `#171` и `#175` нельзя продвигать в parent только на основании их наличия: после их интеграции parent head изменится и потребует свежих exact-SHA CI, Contract & Regression QA и Security Review до любой test-server mutation.
- Ни `#170`, ни diagnostics agent `#14` этим циклом на test server не устанавливались; general passwordless sudo не запрашивается и не разрешается.

До успешного исправления `#170`, свежих exact-SHA QA/Security gates и безопасного staging diagnostics PR `#14` не считается подтверждённо установленным на test server.

## Website / RUVDS

- **Единственный канонический production runtime публичного сайта, Client Portal и Website Admin — `control-center.pro` на сервере RUVDS.**
- Website `main` после gated merge RuVDS production-target gate PR `#66`: exact HEAD `450bfbac5ac83121b9d559393f86608bf535803f`.
- PR `#66`, exact reviewed head `0ff2c78caf984bbba9f63bbb49a0e879fe605b2d`, прошёл repository site CI, RuVDS runtime CI, exact production-target validation и final Security/Release Review без blocking findings. Он закрывает manifest→post-push-CI timing race и не добавляет CI deployment credentials.
- Production manifest после merge `#66` **не изменён** и по-прежнему одобряет exact website SHA `455e77cd6bd06af6d2259ce32e0c1d8a12d76b54`; следовательно сам merge `#66` не является website promotion и не должен перезапускать production runtime.
- Cloudflare больше не является частью действующей website hosting/deployment architecture и не является release gate. Старые Cloudflare workflow/check failures — legacy/non-blocking evidence и не должны блокировать website PR/release.
- Все будущие website deployment/promotion/runtime acceptance выполняются только через безопасный RUVDS path с exact approved target, successful exact-main production-target gate, preflight, recovery/rollback и последующей проверкой HTTPS/TLS, nginx/reverse proxy, `/api/health`, релевантных public/client/admin endpoints и exact deployed revision, когда она доступна.
- Website UX/CRO PR `control-center-website#55`, exact head `29a3b44eb612048b96ddbe33d74ab522e84aff4b`, сейчас `mergeable=true`; завершённой Independent Security Review и применимого RUVDS promotion/runtime evidence на этом exact candidate пока нет, поэтому merge/promotion заблокирован.
- Website Admin contract foundation `control-center-website#59` интегрирован в website `main`; это docs/test-only contract boundary без privileged runtime route.
- Client Portal `#61`, exact head `495de3ea6089611c4b6ff788f63f5706d013c728`, сейчас `mergeable=false` относительно актуального `main`; фактическая user-facing реализация также ждёт server-authoritative auth/session/profile/license contract.
- Website Visual/Layout `#54`, exact head `dd5ddb09a3ae015c3d704d5b80fa1856e8d28d63`, сейчас `mergeable=true`, но требует полного актуального применимого QA/Frontend Quality/Security/RUVDS gate набора перед merge/promotion.

## Android

- Android SDK Fleet contract интегрирован в `control-center-android-sdk/main`.
- `control-center-android-admin#2` остаётся draft: typed Fleet inventory parsing есть, но user-facing Compose screen, focused UI/parser tests и финальные exact-head quality/security gates ещё не завершены.
- iOS полностью вне scope и не участвует в release gate.

## Update / rollback policy

- Same-version и downgrade apply не должны молча перезаписывать runtime.
- Controlled rollback не обходит signature/digest/platform/state-schema checks.
- Для idempotent staging допускается только безопасный no-op при совпадении version, exact commit/build identity и требуемых runtime bytes.
- Любое изменение candidate SHA инвалидирует прежние QA/Security/Quality/Staging evidence.

## Release governance

- Каждый обычный новый релиз Control Center должен включать минимум одну завершённую **User-facing improvement**.
- Refactor, CI/CD, dependencies, docs, tests, infrastructure и internal agent/transport изменения не должны самостоятельно инициировать обычный продуктовый релиз.
- Emergency maintenance/security/hotfix release без новой пользовательской функции допускается только при объективном риске и должен быть явно маркирован.
- Финальный merge/release/promotion выполняется только после зелёных применимых CI, QA, Quality, Security и staging/runtime gates на неизменившихся exact SHA.

## Документационная дисциплина

- Исторические release records `docs/releases/1.0.0*.md` не переписываются задним числом.
- `deployment.json` остаётся authoritative source production release status серверного продукта.
- Google Drive roadmap/requirements не повышают release status без code/CI/runtime evidence.
- Runtime/CI discrepancy оформляется технической задачей и не маскируется документацией.
