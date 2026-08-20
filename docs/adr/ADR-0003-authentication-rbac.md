# ADR-0003 — Authentication, sessions and RBAC

Status: accepted

## Context
Control Center 1.0.0 requires local authentication, admin/viewer roles, secure browser sessions, server-side authorization and a path that does not grant the Web process root privileges.

## Decision
- Local users are authoritative application identities for the 1.0 foundation.
- Passwords are stored as salted PBKDF2-HMAC-SHA256 hashes with 600,000 iterations and algorithm/work-factor metadata in the encoded value. The format permits future KDF upgrades without treating the algorithm as implicit state.
- Initial administrator credentials are generated once, stored in a mode-0600 bootstrap secret in the state directory and removed after the first successful password change. They are never printed by the installer.
- Browser sessions use random opaque tokens. Only a SHA-256 digest of the token is retained in server-side memory. Restart therefore revokes all sessions by design.
- Session cookies are HttpOnly, Secure and SameSite=Strict. Long-lived bearer credentials are not stored in localStorage.
- State-changing authenticated requests require the session CSRF token and origin validation.
- Authentication failures are rate-limited before expensive password verification.
- Roles are `admin` and `viewer`. Every privileged API is checked server-side; UI visibility is never an authorization control.
- Password change and account blocking revoke applicable sessions.

## Security implications
The application remains loopback-only by default and expects HTTPS termination for browser use because Secure cookies are mandatory. Login errors do not distinguish unknown, blocked or wrong-password accounts. The final active administrator cannot be blocked.

## Acceptance criteria
Login/logout, session lookup, secure-cookie attributes, password rotation/session revocation, CSRF rejection, admin positive authorization, viewer positive read authorization, viewer negative privileged authorization and bootstrap-secret deletion are automated tests.

## Rollback/exit strategy
Session state is disposable and can be revoked by restart. Password records carry KDF metadata for future re-hash migration. Persistent user metadata is governed by the state schema and repair rules in ADR-0004.
