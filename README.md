# Control Center

Baseline: **1.0.0**  
Current development milestone: **1.0.0-rc.1 — Production Candidate**

Control Center is being rebuilt from a clean baseline. Previous implementation, release history and architecture are not part of the active product unless explicitly re-adopted through the new governance process.

## rc.1

`1.0.0-beta.1` is accepted. rc.1 is a scope-frozen production candidate: it does not add new end-user features and concentrates on reproducible release identity, clean-install/upgrade/reboot acceptance, security regression, lifecycle preservation and rollback recovery.

### Release layout

```text
/usr/local/lib/control-center/releases/<release-id>/
/usr/local/lib/control-center/current -> releases/<release-id>
/usr/local/lib/control-center/previous -> releases/<release-id>
/usr/local/lib/control-center/staging/
/usr/local/sbin/control-center-update
/etc/control-center/update-public-key.pem
```

The systemd service executes `/usr/local/lib/control-center/current/control-center`. Release binaries are stored root-owned and non-writable during normal operation.

### Signed update model

Update packages contain exactly:

```text
manifest.json
manifest.sig
control-center
```

`manifest.json` is signed with Ed25519 and binds the release version, commit, platform, state-schema compatibility, artifact byte size and SHA-256. The currently installed trusted runtime verifies the signature and artifact before candidate code is executed.

Only an update **public** key is installed on the managed host. A production private signing key must never be committed, shipped inside release artifacts or installed on the server.

### Create a signed package

For development/CI, generate or supply an Ed25519 PKCS#8 private key and run:

```bash
go run ./cmd/release-tool package \
  --binary ./dist/control-center-linux-amd64 \
  --version 1.0.0-rc.1 \
  --commit <release-commit-sha> \
  --arch amd64 \
  --private-key /secure/path/update-private.pem \
  --output /tmp/control-center-release.tar.gz
```

### Apply an update

After provisioning the matching public key at `/etc/control-center/update-public-key.pem`:

```bash
sudo control-center-update --package /path/to/control-center-release.tar.gz
```

Same-version and downgrade attempts are rejected by default. `--allow-downgrade` is reserved for an explicit controlled rollback and does not bypass signature, digest, platform or state-schema checks.

### First administrator

The installer bootstraps a local `admin` only when state contains no users. The generated credential is stored root-readable at:

```text
/var/lib/control-center/bootstrap-admin.secret
```

It is removed after the first successful password change.

### Local development

```bash
go test ./...
CONTROL_CENTER_STATE_DIR=$(mktemp -d) go run ./cmd/control-center bootstrap-admin
CONTROL_CENTER_STATE_DIR=<same-dir> CONTROL_CENTER_LOG_DIR=$(mktemp -d) go run ./cmd/control-center
```

The secure product default remains `127.0.0.1:8876` with `Secure` browser session cookies. HTTP/IP exposure used on the temporary test host is an ops-only test configuration and is not the rc.1 production default.

### Build and validation

```bash
./scripts/build.sh
./scripts/auth-acceptance.sh        # installed test host
./scripts/operations-acceptance.sh  # after Auth/RBAC acceptance
./scripts/rc1-update-acceptance.sh  # root/systemd host with ephemeral test signing key
```

Release binaries are built statically for linux/amd64 and linux/arm64.

### Install / repair / uninstall

```bash
sudo ./install/install.sh
sudo ./install/install.sh --repair
sudo ./install/install.sh --reinstall
sudo ./install/uninstall.sh
```

Provide an update public key during install with `CONTROL_CENTER_UPDATE_PUBLIC_KEY=/path/public.pem`. Non-purge uninstall preserves configuration/state/trust; `--purge` is explicitly destructive.

## Architecture decisions

See `docs/adr/ADR-0001` through `ADR-0007`. ADR-0006 is inherited from accepted beta.1 and defines signed metadata, trusted verification, immutable releases, atomic activation and rollback.
