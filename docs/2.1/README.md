# Control Center 2.1.x

Control Center 2.1.x is the Minecraft Bedrock stabilization release train.

## Versioning policy

- `2.1.0` is the base stabilization release.
- Any defect found while stabilizing this line is fixed only in a new patch release: `2.1.1`, `2.1.2`, `2.1.3`, and so on.
- Published/frozen releases are never edited in place.
- The 2.1.x line remains active until the real server passes production acceptance with Minecraft Bedrock healthy and fully manageable from Control Center.

## Upgrade compatibility

2.1.0 must support a direct upgrade from the real production state `1.3.8` as well as from published `2.0.0`. A server must not be forced to install 2.0.0 first if it is still on 1.3.8.

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
10. Run real-server acceptance before production activation.

## Current production evidence

The latest server-state snapshot reports Control Center `1.3.8`. The runtime snapshot simultaneously shows a live `bedrock_server` listening on UDP `19132`, while the multi-instance automatic updater previously reported zero automatic instances. This mismatch is treated as a control-plane normalization defect rather than proof that the game runtime itself is absent.

## Release gate

`deployment.json` remains pointed at the currently published production release until 2.1.0 CI is green and the release candidate has passed direct-upgrade and Minecraft recovery/normalization acceptance.