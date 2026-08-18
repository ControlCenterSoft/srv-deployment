# Control Center 2.1.x

Control Center 2.1.x is the Minecraft Bedrock stabilization release train.

## Versioning policy

- `2.1.0` is the frozen base stabilization release.
- Any defect or hardening discovered after its publication is fixed only in a new patch release: `2.1.1`, `2.1.2`, `2.1.3`, and so on.
- Published/frozen releases are never edited in place.
- Real-server production acceptance is mandatory for every 2.1.x patch before it is considered stable.

## Verified 2.1.0 production result

The real server automatically installed frozen Control Center `2.1.0` at Git SHA `7cc7b0512233fa023a5ab36951d57363272d024f`. Fresh server-state after deployment proved:

- `srv-control-minecraft-bedrock.service` is enabled and active;
- the actual preserved runtime is `/opt/minicraft`;
- exactly one `bedrock_server` owns UDP `19132`;
- the canonical service successfully restarted the existing server and logs reported `Server started.`;
- the old unmanaged Bedrock PID disappeared and the replacement PID belongs to the canonical service;
- the existing world/runtime was preserved rather than replaced.

This closes the original service-ownership/control-plane defect. The remaining hardening issue discovered by production evidence is that the preserved legacy runtime is owned by root, so the canonical Bedrock process in 2.1.0 also runs as `root`.

## 2.1.1 hardening objective

2.1.1 keeps the successful 2.1.0 topology and removes the remaining root execution and scheduler ambiguity without replacing the world:

1. Create/reuse a dedicated non-root `minecraft` system identity, rejecting UID 0.
2. Record the complete pre-change runtime ownership/mode map so rollback can restore metadata without overwriting world contents.
3. Move the preserved runtime to `minecraft:minecraft` ownership.
4. Keep `srv-control-minecraft-bedrock.service` as the single canonical server service, but run it as `User=minecraft` and `Group=minecraft`.
5. Add a root-only pre-start ownership guard that repairs files created by privileged update/restore operations before Bedrock starts.
6. Preserve the frozen 2.1.0 control implementation behind a 2.1.1 dispatcher rather than duplicating its established operations.
7. Replace the historical `minecraft-update.timer` and conflicting multi-instance timer with one managed `srv-control-minecraft-bedrock-update.timer`.
8. Never perform a blind automatic package replacement when the installed Bedrock version cannot be established. The canonical updater records a safe `decision_ready=false` state instead.
9. Derive the installed version from managed version files or canonical Bedrock journal output and expose the new canonical timer through the existing Control Center updater API.
10. Production acceptance must prove the real Bedrock PID is non-root, UDP/world health survives a controlled restart, a deliberately root-created probe is repaired by the pre-start guard, backup inspection still works, and the canonical updater can make a version decision.

## Upgrade compatibility

2.1.1 supports the real production path `2.1.0 -> 2.1.1`. It also retains recovery compatibility for a server that skipped the base release: `1.3.8` or `2.0.0` first executes the exact frozen 2.1.0 transaction inside the 2.1.1 deployment, then applies only the new hardening layer.

## World and runtime policy

The current world is healthy and is not replaced by 2.1.1. Runtime relocation from `/opt/minicraft` is also intentionally deferred: a non-standard but proven path is safer than an unnecessary filesystem move. A later 2.1.x patch may normalize the path only if there is a concrete operational benefit and a proven backup/rollback path.

## Production gate

While 2.1.1 is being prepared, `deployment.json` remains on frozen `2.1.0`. The pointer moves to 2.1.1 only after the dedicated CI validates syntax, frozen-base integrity, upgrade chaining, non-root ownership/rollback contracts, and the canonical update scheduler. After merge, fresh `server-state` must prove the real server accepted 2.1.1 before the patch is frozen as stable.
