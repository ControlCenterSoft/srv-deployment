# Control Center — текущее подтверждённое состояние

Дата сверки: 2026-08-21.

Этот документ описывает **фактическое подтверждённое состояние** по коду, release metadata, GitHub CI и runtime/staging evidence. При расхождении с планами или старыми документами приоритет имеют exact release metadata и проверяемое CI/runtime evidence.

## Production

- Канонический production release серверного Control Center: **1.0.0**.
- `deployment.json`: `channel=stable`, `status=production-ready`, `acceptance=passed`.
- Accepted source commit: `1b364ae88789696bf98537d21544de8a259d086d`.
- Production promotion серверного продукта на 1.1.x не выполнялся.

## Development 1.1.x

- Интеграционная ветка: `1.1.x`.
- Exact HEAD: `6e279af1f45db4b501ee40035985aee289d9b82d`.
- Приняты DNS resolver actual-state inventory и безопасный admin-only resolver preview с Desired/Actual/Rollback моделью, no-op detection, validation/audit и `apply_supported=false`.
- Resolver/service mutations пока не включены.

## Последний подтверждённый staging candidate

Последний exact candidate, полностью прошедший real test-server Full Acceptance для серверного продукта: **1.1.0-rc.6** / `302eb6da97324d719849e7ae752fc10bdc557d9a`.

Для этого exact SHA подтверждены Fast CI, Contract & Regression QA, Independent Security Review и Full Acceptance / real test-server staging. После последующих merge интеграционный HEAD изменился, поэтому это staging evidence не повышает текущий `1.1.x` до production-ready автоматически.

## Текущие gated кандидаты

### Core B DNS preflight

PR `#161`, exact head `ca0d610aca75d3838c5d10eb841182529a95fc4d`:

- Fast CI — PASS;
- Contract & Regression QA — PASS на exact SHA;
- apply остаётся отключённым;
- свежий Independent Security Review на этом exact SHA ещё требуется до Integrator merge.

### Admin Web Audit

PR `#141`, exact head `2303ab818388b5356f0c57eea6a08529540756ac`:

- Fast CI — PASS;
- Contract & Regression QA — PASS;
- Frontend Quality — PASS;
- Independent Security Review — PASS;
- Ops/Test Server staging evidence на этом exact SHA пока не подтверждено.

До staging на неизменившемся SHA PR не интегрируется.

### Core A Fleet disconnect

PR `#139`, exact head `e457678c3e3f14460cd4bb16516242ee21ac2fb4`, сейчас не mergeable относительно текущей `1.1.x`. Recovery claim требует полного `disconnect → fresh enrollment → fresh heartbeat` regression coverage из test-only PR `#143`. После синхронизации/интеграции тестов head изменится и потребует свежих CI/QA/Security evidence.

### AI Gateway

Security-fix PR `#145` с fail-closed redirect handling, non-redirectable provider credentials и default-path regression coverage интегрирован в parent transport PR `#142`.

Новый exact head `#142`: `5653b0c1c33494e24ced7b4ffc882bd45ebe813d`. После изменения SHA прежние parent evidence недействительны; новый Fast CI/ops bootstrap запущены и должны завершиться, затем требуются свежие exact-SHA QA/Security gates.

PR `#150` и default-branch dispatcher `#151` остаются заблокированы. `#150` всё ещё закреплён на старом vulnerable transport path; `#151` дополнительно нарушает действующий frozen-main post-release allowlist. Оба требуют перепривязки к принятому hardened transport и свежих QA/Security gates; текущие heads не merge.

## Test server / Ops Agent

- На последнем подтверждённом typed preflight test server сообщал Control Center **1.1.0-rc.6** / `302eb6da97324d719849e7ae752fc10bdc557d9a`.
- Установленный Ops Agent/Broker: **1.1.8**.
- Diagnostics PR `ControlCenterSoft/control-center-server-diagnostics#14`, exact head `d4337bdd5f3111431ee06858fcd0d3338655751c`: CI PASS, Contract & Regression QA PASS, Independent Security Review PASS.
- Технический staging PR `srv-deployment#158` остановился до mutation: SSH transport был доступен, но staging account не имеет general non-interactive sudo. Сервер не изменялся.

До успешного безопасного staging diagnostics PR `#14` не считается подтверждённо установленным на test server.

## Website / RUVDS

- **Единственный канонический production runtime публичного сайта, Client Portal и Website Admin — `control-center.pro` на сервере RUVDS.**
- Cloudflare больше не является частью действующей website hosting/deployment architecture и не является release gate. Старые Cloudflare workflow/check failures — legacy/non-blocking evidence и не должны блокировать website PR/release.
- Все будущие website deployment/promotion/runtime acceptance выполняются только через безопасный RUVDS path с preflight, recovery/rollback и последующей проверкой HTTPS/TLS, nginx/reverse proxy, `/api/health`, релевантных public/client/admin endpoints и exact deployed revision, когда она доступна.
- Website UX/CRO PR `control-center-website#55`, exact head `29a3b44eb612048b96ddbe33d74ab522e84aff4b`: repository CI PASS, Contract & Regression QA PASS, Frontend Quality PASS. До merge/promotion требуется актуальное применимое RUVDS runtime/deployment evidence; Cloudflare status не учитывается.
- Website Admin contract foundation `control-center-website#59` интегрирован в website `main`; это docs/test-only contract boundary без privileged runtime route.
- Client Portal `#61` — contract/evidence foundation; после движения `main` требует синхронизации перед дальнейшей интеграцией.
- Website Visual/Layout `#54` имеет зелёные repository CI/QA/Frontend Quality на текущем head, но финальный runtime smoke относится к RUVDS gate.

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
