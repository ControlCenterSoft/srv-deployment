# ADR-0003 — Authentication, sessions and RBAC

Status: proposed

## Context
1.0.0 requires local authentication, admin/viewer roles, secure browser sessions and server-side authorization.

## Decision
Authentication and RBAC are implemented in alpha.2. Browser sessions use server-side session state and Secure/HttpOnly/SameSite cookies. Long-lived bearer credentials are not stored in localStorage. Every privileged API declares required permissions and is checked server-side. UI visibility is presentation only, never an authorization control.

## Acceptance criteria
Login/logout, password change and account blocking revoke applicable sessions; admin/viewer positive and negative permission tests cover every privileged endpoint; auth rate limits and CSRF/origin protections are tested.

## Rollback/exit strategy
RBAC schema and migration must support repair without bypassing authorization.
