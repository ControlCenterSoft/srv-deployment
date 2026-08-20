# ADR-0006 — Update, integrity and rollback

Status: proposed

## Context
1.0.0 requires a safe update foundation tied to immutable release artifacts.

## Decision
Updates use deterministic release metadata, artifact integrity verification, staging before activation and an atomic switch or equivalent safe activation mechanism. Post-update acceptance determines success. Failed activation returns to the previous known-good runtime or enters an explicit repair state. Production runtime must report the release version and commit/tree represented by the published artifact.

## Acceptance criteria
Valid update, corrupted artifact, interrupted staging, failed post-update health, rollback/repair and version/commit consistency tests.

## Rollback/exit strategy
The previous known-good release remains addressable until post-update acceptance closes successfully.
