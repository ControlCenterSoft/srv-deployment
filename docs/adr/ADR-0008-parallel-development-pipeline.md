# ADR-0008 — Параллельный автономный конвейер разработки

Status: accepted

## Context

Stable 1.0.0 принят как exact immutable baseline. Новая линия 1.1.x должна развиваться быстрее, не разрушая принятые runtime/API/data contracts и не превращая Web/API в универсальный root execution surface.

## Decision

Линия 1.1.x развивается в отдельной интеграционной ветке `1.1.x`.

Каждая функция проходит параллельные обязательные дорожки:

1. implementation — backend/frontend/platform code;
2. tests — unit/contract/negative tests;
3. security — static checks, secret scan, permission-negative review;
4. independent review — Gemini как advisory evidence;
5. integration — сборка linux/amd64 и linux/arm64;
6. acceptance — exact candidate SHA, staging, runtime/security/recovery evidence.

Короткие feature-ветки создаются от актуальной `1.1.x` и возвращаются в неё только после mandatory development gate.

Stable `main` остаётся источником принятого production baseline 1.0.0 до отдельного release-governance решения.

## AI roles

- ChatGPT — orchestration, architecture, implementation integration and release decision support.
- Gemini — independent code review only; output is untrusted advisory evidence.
- Perplexity — external research/fact-checking; findings are untrusted research input and require source validation.
- Deterministic CI/tests — authoritative automated evidence for syntax, contracts, builds and reproducible checks.

AI output never executes directly as shell, deployment metadata, privileged operation or configuration.

## Security boundary

Privileged system changes follow ADR-0005: typed allowlisted operations, validated inputs, bounded execution and auditable operation IDs. Arbitrary shell fragments from Web/API/AI output are prohibited.

Remote staging remains fail-closed until the repository contains a versioned typed `scripts/staging-deploy.sh` contract. Missing staging implementation is a blocker, not a reason to fall back to arbitrary SSH commands.

## Release behavior

A development build is not a release. Production promotion requires:

- exact candidate commit;
- mandatory CI green;
- runtime/security/negative acceptance;
- repair/rollback evidence;
- immutable artifacts and checksums/signatures where applicable;
- explicit update of canonical release metadata.

## Consequences

Development work can run in parallel and receive feedback earlier while the accepted 1.0.0 production identity remains reproducible and recoverable.
