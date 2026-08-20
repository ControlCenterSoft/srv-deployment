# ADR-0004 — Configuration and state model

Status: proposed

## Context
Control Center needs versioned configuration, desired/observed state and recoverable migrations.

## Decision
Persistent state is introduced with an explicit schema version. Desired state is stored separately from observed runtime state. Configuration is schema-validated before apply. Secrets are stored separately from ordinary configuration. Forward migrations must be repeatable or have a documented repair path.

## Acceptance criteria
Schema validation, migration, interrupted-migration repair and desired/observed reconciliation tests are mandatory before 1.0.0.

## Rollback/exit strategy
Configuration export plus repair/migration tooling must allow recovery without assuming full reinstall.
