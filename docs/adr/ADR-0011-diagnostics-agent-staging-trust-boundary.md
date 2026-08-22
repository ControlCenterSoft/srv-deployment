# ADR-0011 — Diagnostics-agent staging trust boundary

Status: accepted for development line 1.1.x

## Context

The dedicated Control Center test server uses an unprivileged diagnostics agent plus a root SO_PEERCRED broker. The diagnostics agent must occasionally be upgraded independently from the server product, but granting the staging SSH identity general passwordless sudo, arbitrary shell, direct product updater access, or new broker actions would widen the privilege boundary.

The accepted diagnostics candidate is independently gated in `ControlCenterSoft/control-center-server-diagnostics`; integration and runtime promotion remain controlled by the Control Center P0 Integrator gate.

## Decision

For test-server diagnostics-agent staging, Control Center uses a separate, narrow signed-component path:

- one-time root bootstrap installs only `/usr/local/sbin/control-center-ops-agent-staging-update` and one command-scoped sudoers entry;
- the wrapper accepts only `--self-test` or one strict package path and exposes no caller-controlled command/argv execution;
- staging packages are Ed25519-signed and must match the approved source repository, path, commit and Git blob before signing and again during root-side admission;
- the package is bound to the exact expected test-server product version/commit and diagnostics agent version;
- package path, owner, hard-link count, size, tar member count/order, manifest schema, signature, artifact SHA-256, source Git blob and AST-declared agent version are verified fail-closed;
- the complete privileged mutation path is serialized with a root-owned lock;
- lower diagnostics-agent patch versions are rejected;
- a version maps immutably to one artifact: same-version/different-artifact replacement is rejected, while exact-artifact retry is idempotent;
- backups are root-only and collision-safe;
- post-install failure restores the previous agent, registration and timer state;
- bootstrap self-test failure restores the prior wrapper/sudoers state where applicable;
- the existing SO_PEERCRED broker, socket ownership/mode, action allowlists, `NoNewPrivileges`, product updater and product runtime remain unchanged.

The currently approved source tuple is deliberately immutable in reviewed code. Advancing to another diagnostics candidate requires an explicit reviewed change plus fresh exact-SHA CI, Contract & Regression QA and Security Review.

## Security implications

The staging signing key authorizes only an artifact that also satisfies the pinned source provenance and exact product identity. A caller cannot mint a valid package for arbitrary content by supplying self-consistent commit/blob metadata. Retained older signed packages cannot be replayed to downgrade the installed diagnostics agent, and concurrent valid staging requests cannot race backup/rollback state.

No general sudo, arbitrary shell, service-restart wildcard, product release authority or credential disclosure is introduced.

## Operational implications

The first use on a dedicated test server requires one root bootstrap of the narrow wrapper. Subsequent diagnostics-agent staging uses the pinned SSH transport and signed package apply. Read-only preflight must verify broker/timer/socket/`NoNewPrivileges`, health/readiness and exact product identity before upload or sudo mutation; post-update checks repeat the runtime/product identity assertions.

A code merge of this staging path does **not** prove that a diagnostics agent is installed. Installation status requires separate real test-server staging evidence on the exact approved source candidate.

## Acceptance criteria

- deterministic CI covers shell syntax, signed package construction and negative admission cases;
- source provenance mismatch, unapproved commit/blob, downgrade, same-version artifact substitution and concurrent update paths fail closed;
- exact-head Contract & Regression QA PASS and Security Review PASS exist before Integrator merge;
- before actual test-server mutation, read-only preflight is green and recovery/rollback path is available;
- after staging, health/readiness/product identity, broker/timer state and diagnostics-agent identity are re-verified;
- any candidate head SHA change invalidates previous QA/Security/staging evidence.

## Rollback / exit strategy

The root updater restores the immediately previous diagnostics agent and prior registration/timer state on validation failure. The bootstrap restores previous wrapper/sudoers files if its self-test fails. The entire component-staging path can be removed independently without changing the product update trust root or SO_PEERCRED broker protocol.
