# ADR-0005 — Privileged Worker boundary

Status: proposed

## Context
System management requires privileged operations, while the Web/API runtime must not have arbitrary root execution.

## Decision
Privileged changes are implemented by narrow workers with explicit typed operations, validated inputs, bounded execution time, least-privilege systemd/sudo/polkit capabilities as applicable, fail-closed behavior and operation IDs. Arbitrary shell fragments from the Web/API process are prohibited.

## Реализованный прогресс линии 1.1.x

На текущем development-срезе реализованы следующие слои. Они существенно продвигают boundary, но сами по себе не переводят ADR в `accepted` до завершения installer/update wiring и real-host acceptance:

1. fail-closed engine для typed operation `service.restart` с фиксированным `/usr/bin/systemctl`, allowlist сервисов, bounded timeout/output и security-negative tests;
2. Linux Unix-domain-socket boundary с versioned JSON protocol, `SO_PEERCRED` peer UID verification, explicit UID allowlist, bounded request size, unknown-field rejection и запретом world-access к socket;
3. audit correlation contract по `operation_id` и `actor_id` с типом операции, итоговым status/exit code/error code и bounded timing metadata; arguments и command output в audit event не копируются;
4. standalone `control-center-privileged-worker` daemon без arbitrary shell;
5. fail-closed durable JSONL audit: privileged execution не начинается, если durable audit preflight недоступен; sink использует `O_NOFOLLOW|O_SYNC`, mode `0600`, защищённый parent directory и отдельный `audit_unavailable` protocol result;
6. hardened systemd unit с root worker, пустым capability bounding set, `AF_UNIX`-only networking, строгими filesystem/proc/kernel protections и dedicated root-only audit directory;
7. regression coverage для durable-audit preflight/post-write failures, symlink/permissions, malformed/unauthorized socket paths и typed command boundary.

Этот прогресс интегрирован в development-ветку `1.1.x` через PR #82. Frozen/accepted runtime 1.0.0 и canonical `main` этим не меняются.

Следующие обязательные gate: API-side integration с production operation lifecycle, installer/repair/update/rollback wiring worker daemon и его filesystem ownership, proof отсутствия arbitrary root shell на собранном/installable candidate, затем real-host acceptance.

## Acceptance criteria
Permission-negative tests, malformed-input tests, timeout handling, durable audit correlation, installer/update/repair/rollback coverage и proof that the Web process cannot obtain an arbitrary root shell.

## Rollback/exit strategy
Each privileged operation defines its own repair or rollback semantics before release inclusion. Worker packaging must be removable/repairable independently and must not weaken the accepted 1.0.0 rollback/update trust boundary.
