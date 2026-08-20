# Validation — Control Center 1.0.0-alpha.1 local candidate

Validation date: 2026-08-20

## Passed
- `gofmt` applied to all Go sources.
- `go test ./...` passed.
- `go vet ./...` passed.
- `bash -n install/install.sh install/uninstall.sh scripts/build.sh` passed.
- linux/amd64 static binary built successfully.
- linux/arm64 static binary built successfully.
- amd64 smoke runtime started as an ordinary process and served the embedded UI.
- `/api/v1/health` returned HTTP 200 and `status=ok`.
- `/api/v1/readiness` returned HTTP 200 and `ready=true`.
- `/api/v1/version` returned product/version/build metadata.
- Unknown `/api/*` route returned HTTP 404 with machine-readable `api_not_found` error and operation ID.
- Response headers include CSP, Referrer-Policy, X-Content-Type-Options, X-Frame-Options and operation ID.
- amd64 binary is statically linked (`ldd`: not a dynamic executable).
- `systemd-analyze verify` passed after staging the expected executable path.

## Not yet executable in this sandbox
The full root/systemd acceptance (`install -> restart -> repair -> reinstall -> uninstall`) requires a real systemd test host. It is intentionally retained as the final alpha.1 acceptance gate before publishing the prerelease.
