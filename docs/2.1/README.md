# Control Center 2.1.x

Control Center 2.1.x is the Minecraft Bedrock stabilization release train.

## Versioning policy

- `2.1.0` is the base stabilization release.
- Any defect found while stabilizing this line is fixed only in a new patch release: `2.1.1`, `2.1.2`, `2.1.3`, and so on.
- Published/frozen releases are never edited in place.
- `2.1.0` passed real-server production acceptance and is frozen as the accepted production baseline. Any subsequent repair belongs to a new `2.1.x` patch release.

## Upgrade compatibility

2.1.0 supports a direct upgrade from the real production state `1.3.8` as well as from published `2.0.0`. A server is not required to install 2.0.0 manually first when it is still on 1.3.8; the 2.1.0 transaction carries forward and accepts the published 2.0.0 baseline before Minecraft normalization.

## Primary objective

Bring the existing Minecraft Bedrock Server into one canonical, supportable state without unnecessary world replacement:

1. Detect the actual running `bedrock_server`, its runtime directory, service ownership, port and active world.
2. Preserve the existing world, properties, allow list and permissions before any service normalization.
3. Convert an unmanaged or ambiguously managed process to one canonical systemd service: `srv-control-minecraft-bedrock.service`.
4. Keep the proven single-server Control Center API as the authoritative UI contract for 2.1.x.
5. Disable conflicting multi-instance automatic update scheduling while the single-server contract is authoritative.
6. Make start/stop/restart, status, logs, backup/restore and update operations work against the same canonical service.
7. Reinstall only the Bedrock runtime when health checks prove it is necessary. Preserve server data during runtime reinstall.
8. Replace the world only when the existing world is missing/corrupt and recovery cannot make the server healthy; a successful safety backup is mandatory before replacement.
9. Validate UDP listening on the configured Bedrock port (default 19132), active world existence, process/service ownership and Control Center API health.
10. Run real-server acceptance before declaring a release stable.

## Verified production result

Control Center 2.1.0 was merged to `main` as commit `7cc7b0512233fa023a5ab36951d57363272d024f` and was applied by the real server automatically.

The production state collected at `2026-08-18T16:20:54+03:00` reports:

- installed `release_version=2.1.0` and `release_id=2.1.0`;
- installed Git SHA `7cc7b0512233fa023a5ab36951d57363272d024f`;
- deployment result `success` at stage `acceptance`, finished `2026-08-18T16:15:13+03:00`;
- updater result `updated`, stage `accepted`, with no update pending;
- `srv-control-minecraft-bedrock.service` enabled;
- one live `bedrock_server` process listening on UDP `19132`;
- automatic Control Center update timer `srvcc-github-agent.timer` enabled and active after the release transaction.

The original mismatch — a live Bedrock server that was not owned by the expected Control Center management path — is therefore resolved for the accepted production server.

## Current release gate

`main/deployment.json` points to `2.1.0`. The release has passed dedicated 2.1 CI and real-server production acceptance. `2.1.0` is frozen. Any newly discovered Minecraft defect must be implemented as `2.1.1` or a later patch release, with its own preflight/apply/acceptance/rollback and real-server acceptance.