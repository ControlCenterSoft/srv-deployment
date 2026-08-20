# Control Center

Baseline: **1.0.0**

This repository is the clean implementation line for the new Control Center product. Previous implementation, release history and architecture are not inherited unless explicitly re-adopted.

## Current implementation

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

Commands from a complete checkout:

```bash
bash install/install.sh --preflight
bash install/install.sh --install
bash install/install.sh --repair
bash install/install.sh --rollback
```

The installer must run as root for install/repair/rollback because it manages the system user, `/opt/control-center`, systemd and atomic release links.

## Release metadata
`deployment.json` is the canonical machine-readable product state consumed by the public website and local Platform API. A feature or client must not be presented as released unless its release metadata and acceptance evidence say so.

## Parallel clients
Current independent development trains:

- Website — release-aware public portal
- Android Client — `0.1.0`
- Android Admin — `0.1.0`
- Android SDK — `0.1.0`, shared API v1 models/contracts

All privileged authorization remains server-side; client UI visibility is never treated as an authorization boundary.

## Quality gate
GitHub Actions validates:

- Python syntax
- shell syntax
- deployment manifest schema
- API unit/contract tests
- live API smoke test
- negative write-method behavior

The CI result is recorded in `ops/ci-status.json` for machine-readable release gating.
