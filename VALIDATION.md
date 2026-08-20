# Validation — Control Center 1.0.0-beta.1 implementation candidate

Validation date: 2026-08-20

## Passed locally
- `gofmt` validation passed for all Go sources.
- `go test ./...` passed, including strict release-manifest/SemVer tests and the Web `[hidden]` regression contract.
- `go vet ./...` passed.
- Shell syntax passed for installer, uninstaller, updater, build and all acceptance scripts.
- `node --check internal/httpserver/web/app.js` passed.
- GitHub Actions YAML parsed successfully.
- Static linux/amd64 build passed.
- Static linux/arm64 build passed.
- `sha256sum -c dist/SHA256SUMS` passed for both binaries.

## Signed release validation
An ephemeral Ed25519 development keypair was generated outside the repository and used only for the local smoke test.

Passed:
- release-tool created a gzip tar containing exactly `manifest.json`, `manifest.sig`, `control-center` in the required order;
- the built trusted runtime verified the exact manifest signature;
- signed release version/commit matched embedded candidate build metadata;
- artifact byte size and SHA-256 verified;
- release ID was derived deterministically from version/commit/artifact digest;
- modified manifest bytes were rejected;
- malformed JSON trailing data is covered by unit tests and rejected;
- invalid RFC3339 `built_at` is rejected;
- SemVer empty identifiers and numeric prerelease leading zeros are rejected;
- platform/state-schema compatibility checks remain fail-closed.

No private signing key is committed, packaged as a product artifact or installed by the beta.1 runtime.

## Process-level acceptance
Using temporary state/log directories and an alternate loopback port, the built beta.1 runtime passed:
- initial admin bootstrap;
- health/readiness/version;
- Auth/RBAC acceptance;
- initial password rotation and bootstrap-secret deletion;
- session revocation;
- admin/viewer authorization boundaries;
- Operations/Audit/Diagnostics acceptance;
- diagnostic whitelist and secret-leak checks.

Verified file modes:
- `state.json`: 0600;
- `secrets.json`: 0600;
- `operations.json`: 0600;
- `audit.jsonl`: 0640.

## Real-host alpha.3 evidence carried forward
The real test host previously exposed two alpha.3 defects during acceptance: systemd-created directory modes and CSS `[hidden]` visibility. Both fixes are carried forward into beta.1:
- explicit `StateDirectoryMode=0750`, `LogsDirectoryMode=0750`, `ConfigurationDirectoryMode=0750`;
- explicit `[hidden] { display: none !important; }` with a regression test.

The temporary HTTP/IP browser mode used on the test host is not part of the secure beta.1 product default.

## Intentionally not used as a local gate
`go test -race ./...` is not a promotion gate in this constrained sandbox because production PBKDF2-HMAC-SHA256 uses 600,000 iterations and race instrumentation exceeds the available execution window. The production KDF was not weakened.

## Pending external/system evidence
beta.1 remains an **implementation candidate**, not an accepted release, until a real root/systemd host passes:
1. migration/install from the accepted alpha.3 host state;
2. restart and directory-mode acceptance;
3. installed-runtime Auth/RBAC and Operations/Diagnostics acceptance;
4. update-trust preservation across repair/reinstall/non-purge uninstall;
5. signed newer-version update;
6. same-version rejection;
7. tampered signed metadata rejection;
8. correctly signed broken candidate followed by automatic rollback and recovery;
9. final diagnostics/evidence export.

GitHub push-triggered CI must also be treated as external evidence; a branch publication alone is not proof that Actions passed.
