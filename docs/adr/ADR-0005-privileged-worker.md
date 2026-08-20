# ADR-0005 — Privileged Worker boundary

Status: proposed

## Context
System management requires privileged operations, while the Web/API runtime must not have arbitrary root execution.

## Decision
Privileged changes are implemented by narrow workers with explicit typed operations, validated inputs, bounded execution time, least-privilege systemd/sudo/polkit capabilities as applicable, fail-closed behavior and operation IDs. Arbitrary shell fragments from the Web/API process are prohibited.

## Acceptance criteria
Permission-negative tests, malformed-input tests, timeout handling, audit correlation and proof that the Web process cannot obtain an arbitrary root shell.

## Rollback/exit strategy
Each privileged operation defines its own repair or rollback semantics before release inclusion.
