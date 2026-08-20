# Validation — Control Center 1.0.0-rc.1 implementation candidate

Validation date: 2026-08-20

## Entry evidence

`1.0.0-beta.1` is accepted on real host `ruvds-pr1re`. Final evidence recorded:
- accepted source commit `b3b7cd7d3a1985bbe02b392bce5e26d5bf0cf39c`;
- final resume status `PASSED`;
- signed newer-candidate update passed;
- signed broken candidate rolled back;
- post-rollback systemd start-limit regression passed;
- exact beta.1 restore passed;
- repair/reinstall passed;
- preserve-state uninstall/reinstall passed;
- browser authentication/protected API path passed;
- final service active/readiness true and config/state/log modes `0750`.

## rc.1 local gates

Initial rc.1 preflight passed locally before publication:
- `gofmt` clean;
- `go test ./...`;
- `go vet ./...`;
- shell syntax for installer/updater/acceptance scripts;
- embedded Web JavaScript syntax;
- static linux/amd64 and linux/arm64 builds;
- SHA-256 verification;
- `1.0.0-rc.1+preflight` build-info identity on amd64;
- arm64 artifact format verification.

The published candidate must be rebuilt with its exact final Git commit SHA before local validation can be called complete.

## rc.1 CI gates

Candidate CI is read-only (`contents: read`) and must not commit evidence back into `main`. It now targets `1.0.0-rc.1+ci`, asserts exact version/commit identity, secure loopback listen default, signed package structure, systemd install/restart, Auth/RBAC, Operations/Diagnostics, rc forward update, broken-candidate rollback, immediate post-rollback restart, lifecycle preservation and purge isolation.

GitHub status/check absence is `unknown`, never `passed`.

## rc.1 external/system gates

Pending:
- clean-install evidence on disposable supported systemd host;
- accepted beta.1 → exact rc.1 upgrade on preserved real test host;
- restart and full OS reboot acceptance;
- Auth/RBAC/security/Operations/Audit/Diagnostics regression;
- signed rc forward-update and broken-candidate rollback regression;
- immediate post-rollback restart without `start-limit-hit`;
- repair/reinstall and preserve-state uninstall/reinstall;
- purge isolation on disposable host;
- final secret-safe evidence bundle and release-readiness review.

The temporary HTTP/IP proxy on the test contour is not part of the secure product default.
