# ADR-0005 — Privileged Worker boundary

Status: proposed

## Context
System management requires privileged operations, while the Web/API runtime must not have arbitrary root execution.

## Decision
Privileged changes are implemented by narrow workers with explicit typed operations, validated inputs, bounded execution time, least-privilege systemd/sudo/polkit capabilities as applicable, fail-closed behavior and operation IDs. Arbitrary shell fragments from the Web/API process are prohibited.

## Реализованный прогресс линии 1.1.x

На текущем development-срезе реализованы три независимых слоя, которые сами по себе не переводят ADR в `accepted`:

1. fail-closed engine для typed operation `service.restart` с фиксированным `/usr/bin/systemctl`, allowlist сервисов, bounded timeout/output и security-negative tests;
2. Linux Unix-domain-socket boundary с versioned JSON protocol, `SO_PEERCRED` peer UID verification, explicit UID allowlist, bounded request size, unknown-field rejection и запретом world-access к socket;
3. audit correlation contract: каждое дошедшее до typed engine выполнение связывается с `operation_id` и `actor_id`, фиксирует тип операции, итоговый status/exit code/error code и bounded timing metadata; arguments и command output в audit event не копируются. Покрыты success и permission-negative paths.

Следующие обязательные gate: отдельный worker process/systemd unit, service user/group и filesystem ownership, **persistent fail-safe audit sink** для уже введённого correlation contract, API-side client integration, proof отсутствия arbitrary root shell, install/repair/rollback packaging и real-host acceptance.

## Acceptance criteria
Permission-negative tests, malformed-input tests, timeout handling, audit correlation and proof that the Web process cannot obtain an arbitrary root shell.

## Rollback/exit strategy
Each privileged operation defines its own repair or rollback semantics before release inclusion.
