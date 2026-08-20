# ADR-0006 — Signed update integrity, atomic activation and rollback

Status: accepted

## Context
Control Center 1.0.0 requires an update foundation that can install a new runtime without trusting unverified candidate code, preserve the last known-good release and fail closed when package integrity, compatibility or post-update health checks fail.

The update path must support offline/local package delivery, deterministic acceptance and recovery without embedding a production signing secret in the repository, release artifact or managed server.

## Decision

### Trust and signed metadata
- Update package metadata uses release manifest schema `1`.
- The exact `manifest.json` bytes are signed with Ed25519.
- The managed server stores only an externally provisioned Ed25519 public key at `/etc/control-center/update-public-key.pem`.
- Production private signing keys are never stored in this repository, packaged into releases or installed on managed servers.
- The currently installed trusted Control Center runtime verifies the manifest signature before parsing or trusting manifest fields.

### Manifest contract
The signed manifest binds:
- product identity;
- semantic version and release channel;
- source commit;
- RFC3339 build timestamp;
- Linux architecture (`amd64` or `arm64`);
- supported state-schema range;
- artifact file name, byte size and SHA-256 digest.

Unknown manifest fields, invalid semantic versions, malformed/trailing JSON data, unsupported platforms, incompatible state-schema ranges and artifact digest/size mismatches fail closed.

### Package contract
A release update archive contains exactly three top-level regular files, in this order:
1. `manifest.json`
2. `manifest.sig`
3. `control-center`

Extra entries, symlinks or unexpected package shapes are rejected before activation.

### Verification boundary
Candidate code is not executed until the current trusted runtime has verified:
1. Ed25519 signature;
2. manifest schema and metadata;
3. platform and state-schema compatibility;
4. candidate size and SHA-256.

Only after those checks may the candidate execute `build-info`; its embedded version and commit must match signed metadata.

### Immutable release layout
Installed releases live under:

```text
/usr/local/lib/control-center/releases/<release-id>/
/usr/local/lib/control-center/current -> releases/<release-id>
/usr/local/lib/control-center/previous -> releases/<release-id>
/usr/local/lib/control-center/staging/
```

Release directories are root-owned and non-writable during normal operation. Activation changes only the `current` symlink via an atomic replacement. The prior release remains addressable for rollback.

### Version policy
- Normal update requires target SemVer precedence to be strictly newer than the current runtime.
- Same-version replacement and downgrade are rejected by default.
- `--allow-downgrade` is an explicit operator-controlled rollback escape hatch; it does not weaken signature, digest, platform or schema verification.

### Post-update acceptance and rollback
After switching `current`, systemd restarts Control Center. Success requires:
- service active;
- health endpoint successful;
- readiness reports `ready=true`;
- version endpoint reports the signed target version.

The acceptance endpoint defaults to `http://127.0.0.1:8876` and may be explicitly overridden for a deployment through `CONTROL_CENTER_UPDATE_HEALTH_URL`.

If post-update acceptance fails, `current` is atomically restored to the prior target, the previous runtime is restarted, and the update exits failed. A failed candidate may remain stored as immutable evidence/cache; automatic retention and garbage collection are deferred.

### Installer migration
The beta.1 installer migrates the previous single-binary layout into the release-directory/current-symlink layout while preserving configuration, state and update public trust. Installer failure restores the prior runtime layout.

## Acceptance criteria
- Valid signed package verifies and activates.
- Manifest signature tampering is rejected.
- Artifact byte/size mismatch is rejected.
- Package entries outside the strict whitelist are rejected.
- Platform and state-schema incompatibility are rejected.
- Same-version/downgrade is rejected unless explicitly overridden.
- Embedded candidate version/commit must equal signed metadata.
- Successful update advances `current` and records the former release in `previous`.
- Correctly signed but runtime-broken candidate triggers automatic post-update rollback.
- Previous known-good runtime becomes healthy after rollback.
- Installer migration, repair and reinstall preserve state and trust material.

## Consequences and deferred work
This ADR establishes package verification and local safe activation, not a remote update service. Channel discovery, automatic download, production key-management/HSM integration, release retention/GC, privileged-worker orchestration, Web-triggered self-update and schema migrations beyond state schema `1` remain future work.

A future manifest schema change requires an explicitly compatible transition and cannot silently reinterpret schema `1`.
