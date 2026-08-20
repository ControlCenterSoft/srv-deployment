# ADR-0002 — Installer, repair and uninstall model

Status: accepted

## Context
The baseline requires clean installation, repair/reinstall and safe behavior after partial failure.

## Decision
Installation is performed by an auditable root installer, but the installed runtime executes as the `control-center` system user. The installer performs preflight before mutation, backs up replaced runtime files, installs the binary and systemd unit, restarts the service, and requires a local health check. A failed transaction restores prior runtime files. Repair/reinstall re-apply runtime artifacts while preserving configuration. Uninstall preserves state by default; `--purge` is explicit.

## Alternatives considered
- Container-only deployment: deferred because target host integration and later privileged workers require native lifecycle contracts.
- Package-manager-specific first release: deferred until packaging policy is stabilized; the alpha installer remains deterministic and small.

## Security implications
Configuration is root-owned and group-readable only where required. Runtime service has no Linux capabilities and uses systemd hardening.

## Data/migration implications
Repair does not delete configuration or state. Purging is a separate explicit destructive action.

## Operational implications
Health failure makes installation fail closed and invokes rollback of runtime files.

## Compatibility implications
Requires systemd and standard Linux account/install utilities.

## Acceptance criteria
Installer syntax validation, clean install on supported host, successful health check, restart, repair, reinstall, uninstall and failed-install rollback tests.

## Rollback/exit strategy
Runtime file backup/restore is the alpha.1 rollback. Version-aware update rollback is defined separately in ADR-0006.
