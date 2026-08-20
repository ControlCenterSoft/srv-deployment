# Control Center

Baseline: **1.0.0**  
Current development milestone: **1.0.0-alpha.1 — Platform Skeleton**

Control Center is being rebuilt from a clean baseline. Previous implementation, release history and architecture are not part of the active product unless explicitly re-adopted through the new governance process.

## alpha.1

The first milestone provides an unprivileged Go runtime, embedded Web UI, versioned health/readiness/version APIs, systemd packaging, installer/repair/uninstall foundations and CI validation.

### Local development

```bash
go test ./...
go run ./cmd/control-center
```

Open `http://127.0.0.1:8876`.

### Build

```bash
./scripts/build.sh
```

Release binaries are written to `dist/` for linux/amd64 and linux/arm64.

### Install on a systemd test host

```bash
sudo ./install/install.sh
```

Repair/reinstall:

```bash
sudo ./install/install.sh --repair
sudo ./install/install.sh --reinstall
```

Uninstall while preserving state:

```bash
sudo ./install/uninstall.sh
```

Use `--purge` only for explicit destructive removal of configuration and state.

## Architecture decisions

See `docs/adr/ADR-0001` through `ADR-0006`. Accepted alpha.1 decisions are ADR-0001 and ADR-0002; later security/state/update ADRs remain proposed until their implementation milestone.
