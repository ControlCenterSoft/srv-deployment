# ADR-0001 — Platform architecture

Status: accepted

## Context
Control Center 1.0.0 starts from a clean baseline and requires an offline-safe, diagnosable runtime with a strict privilege boundary.

## Decision
The platform core is a Go service compiled as a self-contained Linux binary. Static Web UI assets are embedded in that binary. The application layer exposes versioned HTTP APIs. The main Web/API process runs as an unprivileged system account and never receives an arbitrary root shell. Future privileged system changes are delegated to narrow workers over explicit contracts.

The initial service binds to loopback only. External exposure and authenticated sessions are introduced with the security/RBAC milestone rather than publishing an unauthenticated alpha runtime to the LAN.

## Alternatives considered
- Python/FastAPI: strong application ergonomics but adds interpreter/package runtime dependencies to the target server.
- Node.js backend: adds a larger server runtime and dependency surface.
- Shell/CGI: rejected because it conflicts with typed API, lifecycle, audit and privilege-separation goals.

## Security implications
A single unprivileged core reduces target-host dependencies. No privileged operation is implemented in alpha.1. Security headers are emitted from the first HTTP skeleton.

## Data/migration implications
No persistent application data schema is introduced by alpha.1. Schema 1.0 is defined in ADR-0004 before persistent state is added.

## Operational implications
The core runs under systemd with hardening and exposes `/api/v1/health`, `/api/v1/readiness` and `/api/v1/version`.

## Compatibility implications
Linux with systemd is the alpha.1 platform baseline. Release binaries target amd64 and arm64.

## Acceptance criteria
Build from clean checkout; unit/API tests pass; Web UI is embedded; service can run without root; health/readiness/version endpoints respond deterministically.

## Rollback/exit strategy
The architecture can replace the HTTP/UI implementation behind stable v1 contracts. If Go is abandoned before 1.0.0, this ADR must be superseded explicitly.
