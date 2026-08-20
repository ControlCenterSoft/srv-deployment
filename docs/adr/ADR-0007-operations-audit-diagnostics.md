# ADR-0007 — Operations, audit and bounded diagnostics

Status: accepted

## Context
Control Center must make state-changing actions traceable and failures diagnosable without exposing secrets or requiring operators to infer application state from arbitrary shell output. The 1.0.0 baseline also requires health/readiness, operation correlation, audit evidence and a safe diagnostics export path.

## Decision
- Every traced application mutation receives the request operation/correlation ID and records a persistent operation with a stable kind, actor, role, target, status and timestamps.
- Operation states are explicit: `running`, `succeeded`, `failed`, `interrupted`.
- A `running` operation found after process restart is converted to `interrupted` with error code `process_restarted`; it is never silently reported as successful.
- Operation records use a versioned schema and are persisted atomically with mode 0600. The store retains a bounded history.
- Security- and administration-relevant events are written to a dedicated append-only JSONL audit log. Audit records contain operation ID, actor/role, action, target, result, remote IP and a safe machine-readable error code where applicable. Request bodies and credentials are never written to audit.
- Viewer access is limited to safe system and diagnostics summaries. Reading operation history, audit history and exporting a diagnostics archive require administrative permissions.
- Diagnostics export is generated from a strict in-memory whitelist. It never archives arbitrary filesystem paths. The alpha.3 bundle contains only `manifest.json`, `version.json`, `runtime.json`, `users.json`, `audit.json` and `operations.json`.
- Diagnostics deliberately exclude passwords, password hashes, bootstrap credentials, session tokens, CSRF tokens and request bodies.
- Diagnostic artifacts declare their format version, generation timestamp, operation ID and `contains_secrets=false` contract.

## Security implications
Operational evidence is itself sensitive. It is therefore bounded, access-controlled and excluded from the public unauthenticated API. Diagnostics contains usernames and operational metadata but no authentication secret material. Future modules must explicitly register safe diagnostics rather than granting the platform a generic filesystem collector.

## Operational implications
Operations survive restart and provide deterministic interrupted-state recovery evidence. Audit is independently readable as JSONL. The product can produce a supportable diagnostics bundle without root shell access or unrestricted log collection.

## Acceptance criteria
- Mutation operations persist terminal state and restart converts unfinished operations to `interrupted`.
- Audit writes and bounded recent reads are covered by tests.
- Admin can read operations/audit and export diagnostics.
- Viewer can read the safe diagnostics summary but receives permission denial for operations/audit/export.
- Diagnostic tar.gz contains exactly the approved files and automated tests reject password hash, bootstrap-secret and session-token leakage.
- Process-level acceptance runs Auth/RBAC first, then verifies traced RBAC operations, audit evidence and diagnostics export.

## Rollback/exit strategy
The operation and diagnostic schemas are additive foundation contracts. A later replacement must migrate or explicitly archive operation evidence. Audit/diagnostic collection can be disabled or replaced without granting additional privilege to the Web runtime.
