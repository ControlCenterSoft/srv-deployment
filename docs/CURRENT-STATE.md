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
- Exact HEAD на момент сверки: `eabca443287996044a26ff23dfb35104cb55fde8`.
- Проверяемый candidate identity: **1.1.0-rc.2**.
- Последний интегрированный fix исправил runner paths для pinned SSH transport real-staging.

### Подтверждённые gate results для 1.1.0-rc.2

Успешны:

1. Full deterministic validation.
2. Reproducible amd64 dual runtime.
3. Reproducible arm64 dual runtime.
4. Exact stable 1.0.0 reproducibility.
5. Disposable runtime install / update / rollback.
6. Signed staging candidate preparation.
7. Fast CI.

Не закрыт:

- **Real test-server staging final gate**.

Причина текущего failure: тестовый сервер уже сообщает установленную версию `1.1.0-rc.2`; updater корректно запрещает обычный same-version apply и возвращает `target 1.1.0-rc.2 is not newer than current 1.1.0-rc.2`. Acceptance workflow пока трактует этот идемпотентный случай как failure вместо подтверждения exact installed identity + health/readiness/version.

Техническое исправление отслеживается в GitHub issue **#116**. До его закрытия `1.1.0` не считается accepted/production-ready, даже несмотря на наличие candidate на тестовом сервере.

## Test server

Из real-staging evidence подтверждено:

- SSH transport с pinned host identity доходит до test server;
- updater на сервере отвечает как `control-center-update-v2`;
- текущая server-side version при последнем acceptance: `1.1.0-rc.2`.

Не следует документировать полный acceptance как PASS, пока workflow не подтверждает exact release identity и post-deploy health/readiness/version в идемпотентном same-version сценарии.

## Update / rollback policy

- Same-version и downgrade apply не должны молча перезаписывать runtime.
- Явный controlled rollback может использовать специальный downgrade path, но не обходит signature/digest/platform/state-schema checks.
- Для idempotent staging допускается только безопасный no-op, когда совпадают version **и exact commit/build identity**, после чего должны пройти health/readiness/version проверки.
- Совпадение только версии при несовпадении commit/build identity должно завершаться fail-closed.

## Документационная дисциплина

- Исторические release records `docs/releases/1.0.0*.md` не переписываются задним числом.
- `deployment.json` остаётся authoritative source production release status.
- Плановые Google Drive документы используются как roadmap/requirements, но не повышают фактический release status.
- Runtime/CI discrepancy оформляется технической задачей, а не маскируется документацией.
