# Validation — Control Center 1.0.0-alpha.3 local candidate

Validation date: 2026-08-20

## Passed locally
- `gofmt` validation passed for all Go sources.
- `go test ./...` passed, including Auth/RBAC/state plus operations/audit/diagnostics tests.
- `go vet ./...` passed.
- `bash -n install/install.sh install/uninstall.sh scripts/build.sh scripts/auth-acceptance.sh scripts/operations-acceptance.sh` passed.
- linux/amd64 static binary built successfully.
- linux/arm64 static binary built successfully.
- `sha256sum -c dist/SHA256SUMS` passed for both release binaries.
- Process-level bootstrap created the initial administrator without printing the password.
- Process-level readiness reported active admin, operation store and audit log checks as ready.
- Process-level Auth/RBAC acceptance passed: login/session/password rotation/bootstrap-secret deletion/admin-viewer authorization.
- Process-level Operations/Diagnostics acceptance passed.
- Traced RBAC mutation produced a persistent `rbac.user.create` operation.
- Audit contained correlated authentication/RBAC/diagnostics events without request bodies or credentials.
- Admin operation/audit reads and diagnostics export passed.
- Viewer positive system/diagnostics-summary access and negative operations/audit/export authorization are covered by API tests.
- Diagnostic tar.gz contains only `manifest.json`, `version.json`, `runtime.json`, `users.json`, `audit.json`, `operations.json`.
- Diagnostic bundle tests and process acceptance found no PBKDF2/password-hash, bootstrap-secret or session-cookie material.
- Persistent operation store is mode 0600; state/secrets remain mode 0600; audit log is mode 0640 inside the restricted product log directory.
- Operations left `running` across reopen become `interrupted` with `process_restarted` evidence.
- Login rate limiting, blocked-session revocation, state revision mismatch and unsupported schema continue to fail closed.

## Additional note
`go test -race ./...` was not used as a promotion gate in this sandbox because PBKDF2-HMAC-SHA256 uses the production work factor of 600,000 iterations and race instrumentation exceeds the available execution window. The production KDF was not weakened. Normal unit/API tests, vet, static builds and process-level acceptance pass.

## Pending external/system evidence
Full root/systemd acceptance remains a release gate: clean install -> restart -> installed-runtime Auth/RBAC acceptance -> operations/diagnostics acceptance -> repair -> reinstall -> preserve-state uninstall/reinstall -> explicit purge.

The GitHub connector used in this session only exposes pull-request-triggered workflow lookup by commit and therefore cannot by itself prove a push-triggered Actions run. This document records local candidate evidence only and does not promote alpha.3 without external/system evidence.
