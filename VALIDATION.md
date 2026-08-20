# Validation — Control Center 1.0.0-beta.1 implementation candidate

Validation date: 2026-08-20

## Passed locally
- `gofmt` validation passed for all Go sources.
- `go test ./...` passed, including strict release-manifest/SemVer tests, overflow-safe arbitrarily large numeric SemVer ordering, artifact/platform/schema negative verification, and the Web `[hidden]` regression contract.
- `go vet ./...` passed.
- Shell syntax passed for installer, uninstaller, updater, build and all acceptance scripts.
- `node --check internal/httpserver/web/app.js` passed.
- GitHub Actions YAML parsed successfully.
- Static linux/amd64 build passed.
- Static linux/arm64 build passed.
- `sha256sum -c dist/SHA256SUMS` passed for both binaries.

## Signed release validation
An ephemeral Ed25519 development keypair was generated outside the repository and used only for local and real-host acceptance.

Passed:
- release-tool created a gzip tar containing exactly `manifest.json`, `manifest.sig`, `control-center` in the required order;
- the built trusted runtime verified the exact manifest signature;
- signed release version/commit matched embedded candidate build metadata;
- artifact byte size and SHA-256 verified;
- release ID was derived deterministically from version/commit/artifact digest;
- modified manifest bytes were rejected;
- malformed JSON trailing data is rejected;
- invalid RFC3339 `built_at` is rejected;
- SemVer empty identifiers and numeric prerelease leading zeros are rejected;
- arbitrarily large numeric SemVer identifiers compare without machine-integer overflow;
- platform/state-schema compatibility checks fail closed.

No private signing key is committed, packaged as a product artifact or retained on the managed host by the acceptance tooling.

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

## Real-host evidence completed
On the real systemd test host the beta.1 line has already demonstrated:
- migration/reinstall from accepted alpha.3 state without deleting users or state;
- restricted configuration/state/log directory modes;
- browser authentication through the temporary ops-only HTTP proxy;
- valid signed update from beta.1 to synthetic beta.2;
- same-version rejection;
- candidate-byte tamper rejection before candidate execution;
- strict package-whitelist rejection;
- signed wrong-architecture rejection;
- signed downgrade rejection;
- tampered manifest/signature rejection;
- correctly signed but intentionally non-starting beta.3 followed by automatic rollback;
- restoration of the exact beta.1 runtime after the synthetic update tests.

The first full real-host run then exposed a real recovery defect: the intentionally broken beta.3 exhausted systemd's start-rate limiter. A subsequent controlled `repair` was blocked with `start-limit-hit` even though `current` already pointed to the known-good beta.1 runtime.

A diagnostic recovery run confirmed `RECOVERY_REASON=start-limit-hit`, then `systemctl reset-failed` restored the exact beta.1 runtime and readiness. This evidence localizes the failure to stale systemd failure/rate state rather than state corruption, release-link corruption or a bad beta.1 binary.

Product fix commit `75ac950eefbc1b70b77bc93373444011791c4415` adds a scoped `systemctl reset-failed control-center.service` before controlled installer restart and before updater activation/rollback restart. It does not weaken package verification or alter user/state data.

## Real-host alpha.3 evidence carried forward
The real test host previously exposed two alpha.3 defects during acceptance: systemd-created directory modes and CSS `[hidden]` visibility. Both fixes remain carried forward into beta.1:
- explicit `StateDirectoryMode=0750`, `LogsDirectoryMode=0750`, `ConfigurationDirectoryMode=0750`;
- explicit `[hidden] { display: none !important; }` with a regression test.

The temporary HTTP/IP browser mode used on the test host is not part of the secure beta.1 product default.

## Intentionally not used as a local gate
`go test -race ./...` is not a promotion gate in this constrained sandbox because production PBKDF2-HMAC-SHA256 uses 600,000 iterations and race instrumentation exceeds the available execution window. The production KDF was not weakened.

## Remaining promotion gate
beta.1 remains an **implementation candidate**, not an accepted release, until resume acceptance for commit `75ac950eefbc1b70b77bc93373444011791c4415` proves the repaired path end-to-end:
1. install/reinstall fixed beta.1 over preserved state;
2. signed update to synthetic beta.2;
3. signed broken beta.3;
4. automatic rollback;
5. immediate restart of the restored known-good runtime without `start-limit-hit`;
6. return to the exact beta.1 commit;
7. repair and reinstall;
8. non-purge uninstall/reinstall with state and update-trust preservation;
9. browser-authenticated API access;
10. final diagnostics/evidence export.

GitHub push-triggered CI is separate external evidence; branch publication alone is not proof that Actions passed.
