# Control Center

Baseline: **1.0.0**  
Current development milestone: **1.0.0-alpha.3 — Operations, Audit & Diagnostics Foundation**

Control Center is being rebuilt from a clean baseline. Previous implementation, release history and architecture are not part of the active product unless explicitly re-adopted through the new governance process.

## alpha.3

This milestone extends alpha.2 with persistent operation tracking, correlated audit events, extended runtime status and a bounded diagnostics export. Diagnostics are generated from an explicit whitelist and never collect arbitrary filesystem paths or authentication secrets.

### First administrator

The installer bootstraps a local `admin` account only when the state store contains no users. The generated credential is **not printed to logs**. It is stored at:

```text
/var/lib/control-center/bootstrap-admin.secret
```

Read it with root privileges, sign in, and change the initial password. The bootstrap secret is deleted automatically after a successful password change.

### Local development

```bash
go test ./...
CONTROL_CENTER_STATE_DIR=$(mktemp -d) go run ./cmd/control-center bootstrap-admin
CONTROL_CENTER_STATE_DIR=<same-dir> CONTROL_CENTER_LOG_DIR=$(mktemp -d) go run ./cmd/control-center
```

The runtime binds to `127.0.0.1:8876` by default. Browser session cookies are `Secure`, so browser deployment is expected to use HTTPS termination while the application itself remains loopback-only.

### Build and validation

```bash
./scripts/build.sh
./scripts/auth-acceptance.sh        # on an installed test host
./scripts/operations-acceptance.sh  # after Auth/RBAC acceptance
```

Release binaries are written to `dist/` for linux/amd64 and linux/arm64.

### Install / repair / uninstall

```bash
sudo ./install/install.sh
sudo ./install/install.sh --repair
sudo ./install/install.sh --reinstall
sudo ./install/uninstall.sh
```

Use `sudo ./install/uninstall.sh --purge` only for explicit destructive removal of configuration and state.

## Architecture decisions

See `docs/adr/ADR-0001` through `ADR-0007`. ADR-0001 through ADR-0004 and ADR-0007 are accepted for the implemented foundation; privileged-worker and update-integrity decisions remain proposed until their implementation milestones.
