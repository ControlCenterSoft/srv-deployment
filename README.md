# Control Center

Baseline: **1.0.0**

This repository is the clean implementation line for the new Control Center product. Previous implementation, release history and architecture are not inherited unless explicitly re-adopted.

## Current implementation

### Web UI shell
The local server console is now available as a server-rendered, read-only shell:

- `/overview` — **Обзор**
- `/market` — **Маркет**
- `/rbac` — **RBAC**
- `/system` — **Система**
- `/` maps to the overview shell

The current UI intentionally contains no JavaScript, forms or privileged actions. It reads the same validated `deployment.json` as Platform API v1, escapes manifest data before HTML output, uses CSP/frame protections and fails closed with HTTP 503 if release metadata is invalid.

Privileged controls will be introduced only after the reachable login/session flow, CSRF/origin policy and persistent audit path are implemented and tested.

### RBAC / session security foundation
Security primitives are implemented and tested before any login endpoint becomes reachable:

- server-side roles `viewer` and `admin`
- stable permission policy and fail-closed `require_permission`
- scrypt password hashing with bounded parameters
- cryptographically random session tokens; only SHA-256 token digests are intended for storage
- `__Host-cc_session` cookie contract with `Secure`, `HttpOnly`, `SameSite=Strict` and no Domain attribute
- bounded audit envelope with recursive redaction of password/token/cookie/API-key fields

This is a **foundation**, not a completed authentication system. Persistent accounts/sessions, login/logout endpoints, CSRF/origin checks, rate limits and privileged authorization are not enabled yet.

### Platform API v1
The first server contour is intentionally read-only and dependency-free:

- `GET /api/v1/health`
- `GET /api/v1/readiness`
- `GET /api/v1/version`
- `GET /api/v1/release`
- `HEAD` is supported for the same endpoints
- all write methods are rejected in this baseline
- every response carries `X-Correlation-ID`
- deployment metadata fails closed when invalid
- the service binds to `127.0.0.1:8876` by default

The API process contains no root execution path and does not expose arbitrary commands.

### Installer foundation
`install/install.sh` provides:

- host preflight
- atomic release staging under `/opt/control-center/releases/`
- `current` / `previous` release links
- hardened `control-center-api.service`
- dedicated unprivileged `control-center` system user
- post-switch readiness verification
- automatic restoration after a failed switch
- explicit rollback to the previous healthy release
- Web UI, API and security foundation installed as one versioned release payload

Commands from a complete checkout:

```bash
bash install/install.sh --preflight
bash install/install.sh --install
bash install/install.sh --repair
bash install/install.sh --rollback
```

The installer must run as root for install/repair/rollback because it manages the system user, `/opt/control-center`, systemd and atomic release links.

## Release metadata
`deployment.json` is the canonical machine-readable product state consumed by the public website, local Web UI and Platform API. A feature or client must not be presented as released unless its release metadata and acceptance evidence say so.

## Parallel clients
Current independent development trains:

- Website — release-aware public portal
- Android Client — `0.1.0`
- Android Admin — `0.1.0`
- Android SDK — `0.1.0`, shared API v1 models/contracts and bounded GET transport

All privileged authorization remains server-side; client UI visibility is never treated as an authorization boundary.

## Quality gate
GitHub Actions validates:

- Python syntax
- shell syntax
- deployment manifest schema
- API unit/contract tests
- Web UI navigation/security/fail-closed tests
- RBAC permission boundaries
- password/session security primitives
- audit secret redaction
- live API smoke test
- negative write-method behavior

The CI result is recorded in `ops/ci-status.json` for machine-readable release gating.
