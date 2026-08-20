# Validation — Control Center 1.0.0-alpha.2 local candidate

Validation date: 2026-08-20

## Passed locally
- `gofmt` applied to all Go sources.
- `go test ./...` passed, including Auth/RBAC, login rate-limit, session revocation and state fail-closed tests.
- `go vet ./...` passed.
- `bash -n install/install.sh install/uninstall.sh scripts/build.sh scripts/auth-acceptance.sh` passed.
- linux/amd64 static binary built successfully.
- linux/arm64 static binary built successfully.
- Process-level bootstrap created the initial administrator without printing the password.
- Process-level readiness returned ready with an active administrator.
- Login returned a server-side session cookie with HttpOnly, Secure and SameSite=Strict.
- Authenticated session lookup passed.
- Password rotation passed, revoked the previous session and removed `bootstrap-admin.secret`.
- Anonymous privileged API is rejected.
- Missing CSRF on mutation is rejected.
- Viewer has positive read access to system status and negative access to privileged RBAC writes.
- Blocking a user revokes its active session.
- The final active administrator cannot be blocked.
- Login rate limiting returns HTTP 429 after the configured failed-attempt threshold.
- Password metadata and password hashes are separated into `state.json` and `secrets.json`.
- Persistent state revision mismatch fails closed and requests repair.
- Unsupported state schema fails closed.
- Response security headers and operation IDs remain enabled.

## Additional note
`go test -race ./...` exceeds the available execution window in this sandbox because PBKDF2-HMAC-SHA256 uses the production work factor of 600,000 iterations and race instrumentation significantly amplifies its cost. The production KDF was not weakened to accommodate the sandbox. Normal unit/API tests, vet, static builds and real process-level authentication smoke tests pass.

## Pending external/system evidence
The GitHub connector available in this session does not expose push-triggered Actions runs for the feature commit. Full root/systemd acceptance remains a release gate: clean install -> restart -> installed-runtime Auth/RBAC acceptance -> repair -> reinstall -> preserve-state uninstall/reinstall -> explicit purge.

This document records local candidate evidence only; it does not promote alpha.2 or retroactively close alpha.1 acceptance.
