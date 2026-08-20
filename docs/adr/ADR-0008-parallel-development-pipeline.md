# ADR-0008 — Параллельный автономный конвейер разработки

Status: accepted

## Context

Stable 1.0.0 принят как exact immutable baseline. Линия 1.1.x должна давать короткую обратную
связь на feature-ветках, но сохранять полный release-grade acceptance на интеграционной ветке.
Тяжёлые multi-arch/reproducibility/runtime проверки на каждом commit создают лишний цикл ожидания
и не повышают качество docs-only или узких изменений.

## Decision

`1.1.x` является интеграционной веткой разработки. `main` остаётся frozen production baseline
1.0.0 до отдельного promotion решения.

Работа разбивается на короткие ветки `feature/1.1-*`. Одна ветка должна представлять один
проверяемый вертикальный срез. Большие функциональные области делятся на backend/API, UI,
tests/negative tests и integration work, когда эти части можно проверять независимо.

### Tier 1 — Fast CI

На feature-ветках и pull request в `1.1.x` выполняется path-based fast gate:

- всегда: stable-ancestor policy, frozen production pointer, `git diff --check`, secret scan;
- Go paths: `gofmt`, `go vet`, `go test`;
- shell/install paths: `bash -n`;
- AI integration paths: Python compile + regression tests;
- runtime paths: один быстрый `linux/amd64` build;
- docs-only changes не запускают runtime build.

Неиспользуемые jobs должны быть `skipped`, а не имитироваться пустыми тяжёлыми проверками.

### Tier 2 — Full candidate acceptance

Каждый успешно интегрированный push в `1.1.x` автоматически становится ephemeral release
candidate `1.1.0-rc.<run-number>` и проходит:

- exact candidate SHA validation;
- полный deterministic test set;
- reproducible `linux/amd64` и `linux/arm64` build;
- повторную воспроизводимость принятого stable 1.0.0;
- disposable root/systemd install, health/readiness, signed update, rollback, auth,
  operations и repair acceptance;
- signed staging package;
- real test-server staging, когда staging transport secrets настроены.

Отсутствие remote staging credentials не блокирует повседневную разработку, но обязано быть
явно отражено как `REMOTE_STAGING=NOT_CONFIGURED`. Production promotion без реального staging
evidence запрещён.

## AI roles

- ChatGPT — orchestration, architecture, implementation integration, branch/PR/release coordination.
- Gemini — independent code review; external, untrusted, advisory evidence.
- Perplexity — web-grounded external research: current upstream docs, compatibility,
  deprecations, migrations and relevant security advisories.
- Deterministic CI/tests — authoritative correctness evidence.

Perplexity integration uses the current official Sonar API contract. AI output never becomes shell,
deployment metadata, privileged operation or configuration without deterministic validation.

## Merge policy

Feature PRs target only `1.1.x`. The orchestrator may enable GitHub auto-merge only after the PR
has the mandatory fast gate attached. Gemini and Perplexity remain independent evidence streams;
provider unavailability must not silently weaken deterministic gates.

No feature branch writes directly to `main`. Production metadata changes occur only in an explicit
release-promotion change after full acceptance and real-server evidence.

## Staging security boundary

Remote staging uses the versioned `scripts/staging-deploy.sh` entrypoint. The entrypoint accepts only:

- exact signed candidate package;
- exact candidate version;
- exact 40-hex candidate SHA;
- pinned SSH host key and fixed staging identity.

It does not accept an arbitrary command. The remote operation is limited to the installed
`control-center-update` updater plus fixed health/readiness/version checks. Candidate packages use a
dedicated staging signing key, separate from production update trust.

## Consequences

Feature feedback is substantially shorter because unrelated multi-arch/reproducibility/runtime work
is removed from each commit. Integration pushes still receive release-grade evidence. Accepted 1.0.0
remains reproducible and untouched until a separately validated production promotion.
