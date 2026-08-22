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
- Exact HEAD после gated merge Ops/Test Server staging chain PR `#176`: `e9f5420a8148c68d3b7ddeb96083acfa727993bc`.
- PR `#176` был интегрирован только после повторной проверки `mergeable=true`, неизменившегося exact head `a2ac42ad55d1fa5e82b5e2f31b734cb11d30b958`, зелёных `Control Center 1.1.x Fast CI` и `Test ops agent bootstrap`, exact-SHA Contract & Regression QA PASS и exact-SHA Security Review PASS.
- Merge `#176` добавляет только ограниченный signed diagnostics-agent staging path: command-scoped root wrapper, строгую signed package admission, anti-replay/serialization, immutable same-version mapping, fail-closed source provenance и rollback. Он не меняет product release identity, public API, production promotion или SO_PEERCRED broker boundary.
- Ранее приняты DNS resolver actual-state inventory/preview и shared hardened Gemini/Perplexity transport остаются в `1.1.x`.

## Последний подтверждённый server staging candidate

Последний exact candidate серверного продукта, полностью прошедший real test-server Full Acceptance: **1.1.0-rc.6** / `302eb6da97324d719849e7ae752fc10bdc557d9a`.

Этот staging evidence не повышает текущий `1.1.x` до production-ready: интеграционный HEAD изменился после последующих gated merge.

## Текущие gated кандидаты

### Core A Fleet disconnect

PR `#139`, exact head `e457678c3e3f14460cd4bb16516242ee21ac2fb4`.

- После изменения `1.1.x` GitHub сообщает `mergeable=false`.
- Recovery claim требует test-only PR `#143` с полным `disconnect → fresh enrollment → fresh heartbeat` lifecycle coverage.
- После интеграции тестов и синхронизации с новым base head изменится; все прежние exact-SHA QA/Security/staging evidence должны быть получены заново.

### Core B DNS preflight

PR `#161`, exact head `ca0d610aca75d3838c5d10eb841182529a95fc4d`.

- Реализует admin-only resolver preflight и fingerprint handoff, при этом `apply_supported=false` и privileged mutation не добавлена.
- После изменения `1.1.x` GitHub сообщает `mergeable=false`.
- Перед интеграцией требуется синхронизация без контрактных конфликтов, новый exact head и свежие применимые CI/QA/Security/staging gates.

### Admin Web Audit

PR `#141`, exact head `2303ab818388b5356f0c57eea6a08529540756ac`.

- Добавляет user-facing read-only Audit workflow поверх существующего `GET /api/v1/audit`.
- После изменения `1.1.x` GitHub сообщает `mergeable=false`.
- После синхронизации head изменится; прежние QA/Frontend Quality/Security evidence станут устаревшими. Требуются свежие exact-SHA gates и test-server runtime acceptance.

### Control Center Visual UI

PR `#138`, exact head `a38e2668c80a8f307722638d3ccd495a601f08f8`.

- После изменения `1.1.x` GitHub сообщает `mergeable=false`.
- Перед Integrator merge требуется синхронизация и полный свежий exact-SHA CI/QA/Frontend Quality/Security набор плюс требуемое runtime/staging evidence.

### AI Gateway

- Hardened shared provider transport PR `#142` уже интегрирован в `1.1.x`.
- Security-fix PR `#164`, exact head `883b69d532e1bf6640011a07455e1c04c00def2e`, имеет exact-head QA/Security PASS, но собственного применимого deterministic PR CI на этом exact head нет.
- Parent `#150` остаётся non-mergeable; dispatcher `#151` по-прежнему закреплён на старый immutable parent SHA и не может продвигаться до repin + fresh gates.

## Test server / Ops Agent

- Последний подтверждённый typed preflight: Control Center **1.1.0-rc.6** / `302eb6da97324d719849e7ae752fc10bdc557d9a`.
- Установленный Ops Agent/Broker: **1.1.8**.
- Diagnostics PR `ControlCenterSoft/control-center-server-diagnostics#14`, exact head `d4337bdd5f3111431ee06858fcd0d3338655751c`, agent candidate **1.1.10**: deterministic CI PASS, Contract & Regression QA PASS, Independent Security Review PASS.
- Интегрированный `srv-deployment#176` pin-ит именно этот diagnostics source tuple: repo/path + commit `d4337bdd5f3111431ee06858fcd0d3338655751c` + Git blob `412ec9e08432e34d82c64813af079a4177a6ac1e`.
- Перед merge `#176` fresh read-only typed evidence подтвердил `health.get` PASS, `readiness.get` ready=true и `version.get` PASS; product остался `1.1.0-rc.6` / `302eb6da...`, agent/broker `1.1.8`.
- Сам diagnostics agent `1.1.10` ещё **не установлен**: для actual staging нужен один root bootstrap нового narrow wrapper и затем signed agent package apply через существующий pinned SSH path. В текущем automation runtime нет отдельного server/SSH connector или workflow-dispatch action, поэтому server mutation здесь не выполнялась.
- Старые PR `#170`, `#171`, `#175` являются составными предшественниками интегрированного replacement candidate `#176`; regression evidence `#174` сохраняется как доказательство ранее закрытого provenance gap.

До успешного exact-source staging diagnostics PR `#14` и post-update runtime verification агент `1.1.10` не считается подтверждённо установленным.

## Website / RUVDS

- **Единственный канонический production runtime публичного сайта, Client Portal и Website Admin — `control-center.pro` на RUVDS.**
- Website `main`: `450bfbac5ac83121b9d559393f86608bf535803f` после gated RuVDS production-target PR `#66`.
- Production manifest по-прежнему одобряет exact website SHA `455e77cd6bd06af6d2259ce32e0c1d8a12d76b54`; merge `#66` сам по себе не был production promotion.
- Cloudflare полностью исключён из действующей architecture/gates; legacy Cloudflare checks не являются текущими blockers.
- Website UX/CRO `#55`, exact head `29a3b44eb612048b96ddbe33d74ab522e84aff4b`, `mergeable=true`, но полного актуального Security + RUVDS promotion/runtime evidence нет.
- Client Portal `#61`, exact head `495de3ea6089611c4b6ff788f63f5706d013c728`, `mergeable=true`, остаётся contract-only foundation и ждёт server-authoritative auth/session/profile/license contract.
- Website Admin secure contract foundation `#59` уже интегрирован; privileged runtime/UI ждёт серверный контракт.
- Website Visual/Layout `#54`, exact head `dd5ddb09a3ae015c3d704d5b80fa1856e8d28d63`, `mergeable=true`, но требует полного актуального QA/Frontend Quality/Security/RUVDS gate набора.

## Android

- Android SDK Fleet contract интегрирован в `control-center-android-sdk/main`.
- `control-center-android-admin#2`, exact head `dca3e33f482b3aa8a409318b600dd16875032e45`, остаётся draft: typed Fleet parsing есть, но Compose UI, focused UI/parser tests, build/lint acceptance и independent Security Review не завершены.
- iOS полностью вне scope и не участвует в release gate.

## Update / rollback policy

- Same-version и downgrade apply не должны молча перезаписывать runtime.
- Controlled rollback не обходит signature/digest/platform/state-schema checks.
- Для diagnostics-agent staging same-version допускается только exact-artifact idempotence; same-version/different-artifact replacement и downgrade блокируются.
- Полный privileged agent update path сериализуется root-owned lock; package provenance и product identity проверяются fail-closed; rollback восстанавливает предыдущий agent/registration/timer state при post-install failure.
- Любое изменение candidate head SHA инвалидирует прежние QA/Security/Quality/Staging evidence.

## Release governance

- Каждый обычный новый релиз Control Center должен включать минимум одну завершённую **User-facing improvement**.
- Refactor, CI/CD, dependencies, docs, tests, infrastructure и internal agent/transport изменения могут интегрироваться в development line, но сами не инициируют обычный продуктовый релиз.
- Emergency maintenance/security/hotfix release без новой пользовательской функции допускается только при объективном риске и должен быть явно маркирован.
- Финальный merge/release/promotion выполняется только после зелёных применимых CI, Contract & Regression QA, Frontend/Android Quality где применимо, Security Review и требуемых staging/runtime gates на неизменившихся exact SHA.

## Документационная дисциплина

- Исторические release records `docs/releases/1.0.0*.md` не переписываются задним числом.
- `deployment.json` остаётся authoritative source production release status серверного продукта.
- Google Drive roadmap/requirements не повышают release status без code/CI/runtime evidence.
- Runtime/CI discrepancy оформляется технической задачей и не маскируется документацией.
