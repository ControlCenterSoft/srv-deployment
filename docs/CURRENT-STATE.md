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
- Ops/Test Server staging/runtime evidence для этого exact SHA не подтверждено;
- после движения `1.1.x` PR сейчас не mergeable относительно актуальной интеграционной ветки.

До интеграции требуется синхронизация с текущим `1.1.x`; новый SHA инвалидирует прежние QA/Security evidence и требует полного свежего gate набора плюс staging/runtime evidence.

### Admin Web Audit

PR `#141`, exact head `2303ab818388b5356f0c57eea6a08529540756ac`:

- ранее подтверждены Fast CI, Contract & Regression QA, Frontend Quality и Independent Security Review на этом exact SHA;
- Ops/Test Server staging evidence на этом exact SHA не подтверждено;
- после движения `1.1.x` PR сейчас не mergeable относительно актуальной интеграционной ветки.

До интеграции требуется синхронизация, полный свежий exact-SHA gate набор и staging на неизменившемся новом SHA.

### Core A Fleet disconnect

PR `#139`, exact head `e457678c3e3f14460cd4bb16516242ee21ac2fb4`, не mergeable относительно текущей `1.1.x`. Recovery claim требует полного `disconnect → fresh enrollment → fresh heartbeat` regression coverage из test-only PR `#143`. После синхронизации/интеграции тестов head изменится и потребует свежих CI/QA/Security evidence.

### Control Center Visual UI

PR `#138`, exact head `a38e2668c80a8f307722638d3ccd495a601f08f8`, после движения `1.1.x` сейчас не mergeable. Перед Integrator merge требуется синхронизация и свежие применимые exact-SHA CI/QA/Frontend Quality/Security evidence.

### AI Gateway

PR `#142`, exact reviewed head `5653b0c1c33494e24ced7b4ffc882bd45ebe813d`, прошёл Fast CI, Contract & Regression QA, Independent Security Review и был интегрирован P0 Integrator в `1.1.x` merge commit `bbbd4b586b61a1ad7a4c673bef5515edd54e767e`.

Это внутренний advisory AI transport/security slice без product/Core/Admin Web/runtime/release authority; отдельный обычный product release из-за него не создаётся, потому что он не является завершённой User-facing improvement.

Security-fix PR `#164` для Perplexity routine queue имеет Contract & Regression QA PASS и Security Review PASS на exact head `883b69d532e1bf6640011a07455e1c04c00def2e`, но собственного PR-triggered deterministic CI run на этом exact head нет. Поэтому Integrator не объединяет `#164` в parent `#150` до появления применимого exact-SHA CI evidence.

PR `#150` и default-branch dispatcher `#151` остаются заблокированы. После будущей интеграции hardened transport в `#150` его head изменится и потребует свежих exact-SHA CI/QA/Security evidence; `#151` должен быть перепривязан к новому immutable parent SHA и повторно пройти требуемые gates. Frozen-main allowlist остаётся обязательным ограничением.

## Test server / Ops Agent

- На последнем подтверждённом typed preflight test server сообщал Control Center **1.1.0-rc.6** / `302eb6da97324d719849e7ae752fc10bdc557d9a`.
- Установленный Ops Agent/Broker: **1.1.8**.
- Diagnostics PR `ControlCenterSoft/control-center-server-diagnostics#14`, exact head `d4337bdd5f3111431ee06858fcd0d3338655751c`: CI PASS, Contract & Regression QA PASS, Independent Security Review PASS.
- Технический staging PR `srv-deployment#158` остановился до mutation: SSH transport был доступен, но staging account не имеет general non-interactive sudo. Сервер не изменялся.

До успешного безопасного staging diagnostics PR `#14` не считается подтверждённо установленным на test server.

## Website / RUVDS

- **Единственный канонический production runtime публичного сайта, Client Portal и Website Admin — `control-center.pro` на сервере RUVDS.**
- Website `main` после gated удаления legacy Cloudflare control plane PR `#63`: exact HEAD `a6ea0029b0a4c4d4ef1692c2f0945f705cac11dc`.
- PR `#63` прошёл exact-head repository CI, RuVDS runtime tests, Contract & Regression QA и Independent Security Review; merge commit `a6ea0029b0a4c4d4ef1692c2f0945f705cac11dc` удалил retired Cloudflare workflows/helper/control-plane metadata без production runtime mutation.
- Cloudflare больше не является частью действующей website hosting/deployment architecture и не является release gate. Старые Cloudflare workflow/check failures — legacy/non-blocking evidence и не должны блокировать website PR/release.
- Все будущие website deployment/promotion/runtime acceptance выполняются только через безопасный RUVDS path с preflight, recovery/rollback и последующей проверкой HTTPS/TLS, nginx/reverse proxy, `/api/health`, релевантных public/client/admin endpoints и exact deployed revision, когда она доступна.
- Website UX/CRO PR `control-center-website#55`, exact head `29a3b44eb612048b96ddbe33d74ab522e84aff4b`: repository CI, Contract & Regression QA и Frontend Quality были PASS на этом SHA до последнего движения `main`; Independent Security Review и применимое RUVDS promotion/runtime evidence не подтверждены. Перед merge требуется повторная сверка с текущим `main` и свежий полный применимый gate набор на неизменившемся candidate SHA.
- Website Admin contract foundation `control-center-website#59` интегрирован в website `main`; это docs/test-only contract boundary без privileged runtime route.
- Client Portal `#61` — contract/evidence foundation и сейчас не mergeable относительно актуального `main`; требуется синхронизация, а фактическая user-facing реализация ждёт server-authoritative auth/session/profile/license contract.
- Website Visual/Layout `#54` имеет ранее собранные repository CI/QA/Frontend Quality evidence, но после движения `main` требует повторной exact-SHA сверки и применимых Security/RUVDS gates перед merge/promotion.

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
