# Control Center — текущее подтверждённое состояние

Дата сверки: 2026-08-21.

Этот документ описывает **фактическое подтверждённое состояние** по коду, release metadata, GitHub CI и real-staging. При расхождении с планами/старыми документами приоритет имеют exact release metadata и CI/runtime evidence.

## Production

- Канонический production release: **1.0.0**.
- `deployment.json`: `status=production-ready`, `acceptance=passed`.
- Accepted source commit: `1b364ae88789696bf98537d21544de8a259d086d`.
- Линия `main` не должна продвигаться на 1.1.x без отдельного promotion после полного acceptance.

## Development 1.1.x

- Интеграционная ветка: `1.1.x`.
- Exact HEAD на момент сверки: `b72fed6abd32b0607ff8a9751a6e864eb84d1a0a`.
- Последний exact release candidate, для которого запущен полный acceptance: **1.1.0-rc.3** / `cdcc9d4d6499a26e8ffb8b520525740afc8d2589`.
- HEAD дополнительно содержит bootstrap pin Ops Agent **1.1.8** на diagnostics commit `fdfd4fababfde339c0d381505ff2306af5571e59`; это техническое изменение после candidate source и само по себе не повышает release status.

### Подтверждённые gate results для 1.1.0-rc.3

GitHub Actions run `32453862099` подтвердил:

1. Full deterministic validation — PASS.
2. Reproducible amd64 dual runtime — PASS.
3. Reproducible arm64 dual runtime — PASS.
4. Exact stable 1.0.0 reproducibility — PASS.
5. Disposable runtime install / update / rollback — PASS.
6. Signed staging candidate preparation — PASS.
7. Fast CI — PASS.

Не закрыт:

- **Real test-server staging final gate** — FAIL на шаге `Deploy exact signed candidate`.

### Текущий real-staging blocker

PR #115 изменил новый `update-v2.sh`: exact same-version replay теперь допускается только как безопасный no-op при совпадении version, commit и байтов обоих runtime; same-version identity drift и downgrade остаются fail-closed.

Однако реальный test server уже сообщает установленный `1.1.0-rc.3`, а staging deploy до запуска candidate code выполняет **ранее установленный server-side `control-center-update-v2`**. Этот старый updater ещё не содержит новую idempotent semantics и завершает операцию ошибкой:

`target 1.1.0-rc.3 is not newer than current 1.1.0-rc.3`

Следовательно, source fix #115 сам по себе не закрывает upgrade-bridge для хоста, на котором тот же candidate уже установлен старым updater binary. Актуальное evidence и критерий закрытия зафиксированы в issue **#116**.

До успешного `REMOTE_STAGING=PASSED` с exact identity + health/readiness/version verification `1.1.0` не считается accepted/production-ready.

## Test server

Из real-staging evidence подтверждено:

- pinned SSH transport работает и доходит до test server;
- staging secrets/signing path позволяют построить и передать signed dual-runtime candidate;
- server-side updater отвечает как `control-center-update-v2`;
- текущая server-side version при последнем acceptance: `1.1.0-rc.3`;
- final deploy gate всё ещё не может подтвердить successful exact no-op из-за backward-compatibility gap установленного updater.

Нельзя документировать полный acceptance как PASS, пока workflow не подтвердит exact release identity и post-deploy health/readiness/version.

## Ops Agent

- Последний интегрированный diagnostics bundle: **Ops Agent 1.1.8**.
- Diagnostics source commit: `fdfd4fababfde339c0d381505ff2306af5571e59`.
- `1.1.x` bootstrap pinned на exact blob identities этого bundle.
- Transport сохраняет Unix `SO_PEERCRED` root broker boundary, typed/allowlisted actions и отсутствие arbitrary shell.
- Следующее runtime evidence должно подтвердить фактическую регистрацию `agent_version=1.1.8` на test server; наличие bootstrap pin в Git само по себе не является доказательством установленной версии.

## Update / rollback policy

- Same-version и downgrade apply не должны молча перезаписывать runtime.
- Явный controlled rollback может использовать специальный downgrade path, но не обходит signature/digest/platform/state-schema checks.
- Для idempotent staging допускается только безопасный no-op, когда доверенно совпадают version, exact commit/build identity и требуемые runtime bytes.
- Совпадение только версии при несовпадении identity должно завершаться fail-closed.
- Acceptance обязан учитывать version skew самого установленного updater; новая candidate semantics не считается доступной до фактического переключения/обновления соответствующего trusted updater path.

## Release governance

- Каждый обычный новый релиз Control Center должен включать минимум одну завершённую **User-facing improvement** — новую пользовательскую capability либо заметное расширение существующего пользовательского сценария.
- Release notes должны явно фиксировать эту пользовательскую ценность и связанное acceptance evidence.
- Refactor, CI/CD, dependencies, docs, tests, infrastructure, internal agent/transport и performance-only изменения могут интегрироваться, но не должны самостоятельно инициировать обычный продуктовый релиз.
- Исключение допускается только для явно обозначенного emergency maintenance/security/hotfix release, когда задержка создаёт риск безопасности, потери данных, недоступности продукта или нарушает update/rollback.

## Документационная дисциплина

- Исторические release records `docs/releases/1.0.0*.md` не переписываются задним числом.
- `deployment.json` остаётся authoritative source production release status.
- Плановые Google Drive документы используются как roadmap/requirements, но не повышают фактический release status.
- Runtime/CI discrepancy оформляется технической задачей, а не маскируется документацией.
