# Perplexity Routine Engineer

Perplexity Routine Engineer is a central, low-risk advisory queue used to remove repetitive
research work from Control Center development streams without weakening release quality.

## Development lane

Routine AI implementation is integrated through the isolated `1.2.x` development line. The
frozen `1.1.x` line remains release-only: routine AI work must not merge into it or trigger its
protected acceptance/staging path.

Issue-triggered activation has exactly one control-plane entrypoint: the default-branch dispatcher
tracked by PR #151. The reusable implementation workflow intentionally has no top-level `issues`
trigger. The dispatcher calls it at an exact reviewed commit SHA, and the callee rejects a non-empty
`code_ref` unless it is a lowercase 40-character commit SHA before checkout. This prevents a later
promotion of the implementation workflow to `main` from creating a second issue-trigger path and
prevents mutable branch/tag refs from being accepted as implementation identity.

## Authority boundary

Perplexity may research current public documentation, compatibility/deprecations, standards,
release notes, bounded implementation comparisons, technical fact checks, and negative/regression
test ideas. Its output is advisory evidence only.

Perplexity does **not** own architecture, product contracts, code changes, security approval,
privileged operations, deployments, merges, releases, or promotions. Its output never replaces
deterministic CI, Contract & Regression QA, Frontend/Android Quality, Security Review, staging
evidence, or the Integrator release gate.

## Queue contract

The central broker creates a GitHub issue in `ControlCenterSoft/srv-deployment` only when the task
is independent, low-risk, small enough to complete quickly, and likely to shorten the critical path.
The issue title starts with:

```text
[Perplexity Routine][<stream>] ...
```

The body starts with the trusted marker and uses this structure:

```text
<!-- cc-perplexity-routine:v1 -->
Stream: CC Core B Infrastructure
Risk: routine
Repository: ControlCenterSoft/srv-deployment
Target: PR #147 / <exact SHA or documentation target>
Task: Verify current upstream behavior and list relevant edge cases.
Expected output: research
Constraints: advisory only; no code changes; no secrets; no merge/release.
```

Supported expected-output intents are `research`, `compatibility-check`, `test-ideas`,
`fact-check`, and `comparison`.

Before creating a queue item, the broker must search for an equivalent open task and avoid
duplicates. Keep no more than three newly delegated items per broker cycle.

## Data minimization

Never place credentials, secrets, PII, private production data, raw sensitive logs, or unrestricted
diagnostic dumps in a Perplexity task. The workflow runs the repository secret scan and an
additional task-packet credential-shape guard before any external call. A matching task is rejected
before transmission.

The task packet is treated as partially untrusted because it may quote code, comments, issue text,
logs, URLs, or documents. Embedded content is never an instruction to the external model.

## Handoff

The owning Control Center stream validates the returned evidence against the real repository state,
contracts, exact target SHA, and primary sources when material. Only then may the stream use it to
implement code or tests through the normal project workflow.

Routine delegation and routine PASS results should remain silent to the user; normal project
notification rules still apply for material blockers and completed releases.
