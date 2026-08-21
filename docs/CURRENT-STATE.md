# Control Center — текущее подтверждённое состояние

Дата сверки: 2026-08-21.

Этот документ описывает **фактическое подтверждённое состояние** по коду, release metadata, GitHub CI и real-staging. При расхождении с планами/старыми документами приоритет имеют exact release metadata и CI/runtime evidence.

## Production

- Канонический production release: **1.0.0**.
- `deployment.json`: `channel=stable`, `status=production-ready`, `acceptance=passed`.
- Accepted source commit: `1b364ae88789696bf98537d21544de8a259d086d`.
- Production promotion на 1.1.x не выполнялся.

## Development 1.1.x

- Интеграционная ветка: `1.1.x`.
- Exact HEAD после интеграции DNS resolver preview: `d988b2dc1400f23473c8984bc50a8840ee987600`.
- Merge `#147` добавил безопасный admin-only `POST /api/v1/dns/resolver/preview` с Desired/Actual/Rollback моделью, no-op detection, validation/audit и `apply_supported=false`; никаких resolver/service mutations этот slice не выполняет.
- Предыдущий merge `#140` уже добавил read-only resolver actual-state inventory; preview строится поверх этого принятого состояния.

## Последний подтверждённый staging candidate

Последний exact candidate, полностью прошедший real test-server Full Acceptance для продуктового slice: **1.1.0-rc.6** / `302eb6da97324d719849e7ae752fc10bdc557d9a`.

Для этого exact SHA подтверждены:

1. Control Center 1.1.x Fast CI — PASS.
2. Contract & Regression QA — PASS.
3. Independent Security Review — PASS.
4. Full Acceptance / real test-server staging — PASS.
5. Test server после acceptance сообщал `1.1.0-rc.6` на commit `302eb6da97324d719849e7ae752fc10bdc557d9a`.

После merge `#147` интеграционный HEAD изменился на `d988b2dc1400f23473c8984bc50a8840ee987600`, поэтому **новый release candidate ещё не зафиксирован** и прежнее staging evidence не повышает новый HEAD до production-ready автоматически.

## Текущие gated кандидаты

### Admin Web Audit

PR `#141`, exact head `2303ab818388b5356f0c57eea6a08529540756ac`:

- Fast CI — PASS;
- Contract & Regression QA — PASS;
- Frontend Quality — PASS после исправления focus/live-region regression;
- Independent Security Review — PASS;
- Ops/Test Server staging evidence на этом exact SHA пока не подтверждено.

До staging на неизменившемся SHA PR не интегрируется.

### Core A Fleet disconnect

PR `#139`, exact head `e457678c3e3f14460cd4bb16516242ee21ac2fb4` остаётся QA-conditional: recovery claim требует полного `disconnect → fresh enrollment → fresh heartbeat` regression coverage из test-only PR `#143`. После интеграции тестов head изменится и потребует свежих CI/QA/Security evidence.

### AI Gateway

PR `#150` и default-branch dispatcher `#151` не могут быть активированы/merged, пока routine queue не переведён на hardened provider transport. Независимый Security Review подтвердил redirect/credential attack path в старом transport. Security-fix chain `#145` содержит fail-closed redirect handling и credential-header hardening, но должна быть корректно интегрирована в parent AI transport и пройти свежие exact-SHA gates.

## Test server / Ops Agent

- На последнем подтверждённом typed preflight test server сообщал Control Center **1.1.0-rc.6** / `302eb6da97324d719849e7ae752fc10bdc557d9a`.
- Установленный Ops Agent/Broker на preflight: **1.1.8**.
- Diagnostics PR `ControlCenterSoft/control-center-server-diagnostics#14` поднимает agent identity до **1.1.10** и устраняет повторную публикацию одного и того же rejected command ID.
- Exact head diagnostics `d4337bdd5f3111431ee06858fcd0d3338655751c`: CI PASS, Contract & Regression QA PASS, Independent Security Review PASS.
- Технический staging PR `srv-deployment#158` не прошёл deploy: SSH transport доступен, но текущий staging account не имеет non-interactive `sudo`; workflow остановился до установки agent fix. Product runtime/release identity не менялась.

До успешного безопасного staging PR `#14` не должен считаться подтверждённо установленным на test server.

## Website

- Website UX/CRO PR `control-center-website#55` exact head `29a3b44eb612048b96ddbe33d74ab522e84aff4b`: repository CI PASS, Contract & Regression QA PASS, Frontend Quality PASS после 44px/focus fix.
- Cloudflare deployment status для этого exact head сообщает deployment failure, поэтому merge/deploy остаётся gated до устранения site deployment blocker и повторной проверки.
- Client Portal `#61` и Website Admin `#59` являются contract/evidence foundation; они намеренно не создают privileged/public account routes до появления server-authoritative backend contracts.
- Website Visual/Layout `#54` остаётся отдельным визуальным потоком и не должен конфликтовать с functional UX/CRO files.

## Android

- Android SDK Fleet contract уже интегрирован в `control-center-android-sdk/main`.
- `control-center-android-admin#2` остаётся draft: typed Fleet inventory parsing есть, но user-facing Compose screen, focused UI/parser tests и финальные exact-head quality/security gates ещё не завершены.
- iOS полностью вне scope и не участвует в release gate.

## Update / rollback policy

- Same-version и downgrade apply не должны молча перезаписывать runtime.
- Controlled rollback не обходит signature/digest/platform/state-schema checks.
- Для idempotent staging допускается только безопасный no-op при совпадении version, exact commit/build identity и требуемых runtime bytes.
- Любое изменение candidate SHA инвалидирует прежние QA/Security/Quality/Staging evidence.

## Release governance

- Каждый обычный новый релиз Control Center должен включать минимум одну завершённую **User-facing improvement**.
- Release notes должны фиксировать пользовательскую ценность и связанное acceptance evidence.
- Refactor, CI/CD, dependencies, docs, tests, infrastructure и internal agent/transport изменения не должны самостоятельно инициировать обычный продуктовый релиз.
- Emergency maintenance/security/hotfix release без новой пользовательской функции допускается только при объективном риске и должен быть явно маркирован.
- Финальный merge/release/promotion выполняется только после зелёных применимых CI, QA, Quality, Security и staging gates на неизменившихся exact SHA.

## Документационная дисциплина

- Исторические release records `docs/releases/1.0.0*.md` не переписываются задним числом.
- `deployment.json` остаётся authoritative source production release status.
- Google Drive roadmap/requirements не повышают release status без code/CI/runtime evidence.
- Runtime/CI discrepancy оформляется технической задачей и не маскируется документацией.
