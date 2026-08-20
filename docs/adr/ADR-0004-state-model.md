# ADR-0004 — Configuration and state model

Status: accepted

## Context
Control Center needs versioned configuration, desired/observed state, separate secret material and fail-closed behavior when persistent state is inconsistent.

## Decision
- State schema version 1 is explicit.
- `/var/lib/control-center/state.json` stores non-secret metadata including users plus desired/observed state containers.
- `/var/lib/control-center/secrets.json` stores password hashes and other future secret records; ordinary state must not contain password material.
- Both documents carry the same monotonically increasing revision. A revision mismatch is treated as an inconsistent transaction and startup fails closed with `repair required`.
- Each file is written by temp-file + fsync + rename with mode 0600. Secret data is written before metadata so a partial pair update cannot silently authorize metadata that has no corresponding credential.
- Schema mismatch is rejected rather than guessed or auto-downgraded.

## Acceptance criteria
Persistence across reopen, secret separation, revision/schema validation, credential verification after reload and bootstrap-secret lifecycle are automated. Clean install, repair/reinstall and preserve-state reinstall remain systemd acceptance gates.

## Rollback/exit strategy
A mismatched or unsupported schema does not start as ready. Later migration tooling must repair or migrate explicitly; reinstall must not overwrite existing state.
