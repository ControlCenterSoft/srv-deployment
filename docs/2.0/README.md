# Control Center 2.x

This directory is the normative documentation set for the Control Center 2.x release line.

## Release baseline

Control Center 2.0.0 is a major release built from the complete published 1.3.8 production state plus the approved redesigned web interface. Published 1.x release directories remain immutable and are not rewritten by 2.x development.

Production must remain on the accepted 1.3.8 deployment until the 2.0.0 release contract, CI, upgrade simulation and real-server acceptance all pass.

## Documents

- [RELEASE-2.0.0.md](RELEASE-2.0.0.md) — release scope, user-visible changes and acceptance gates.
- [UPDATE-ARCHITECTURE.md](UPDATE-ARCHITECTURE.md) — transactional GitHub update architecture and failure recovery.
- [BACKUP-POLICY.md](BACKUP-POLICY.md) — scheduled backups, backups before updates and bulk deletion.
- [MINECRAFT-RECOVERY.md](MINECRAFT-RECOVERY.md) — Minecraft Bedrock health, repair and recovery-world policy.
- [MIGRATION-AND-ROLLBACK.md](MIGRATION-AND-ROLLBACK.md) — supported upgrade path, rollback snapshot and production transition.
- [BRANCH-CLEANUP.md](BRANCH-CLEANUP.md) — branch-retention and post-2.0 cleanup rules.

## Release invariants

1. Published 1.x releases are frozen.
2. A failed update may block re-application of the same release fingerprint, but it must not disable future update checks.
3. `backup_before_update=false` must be honored for both Control Center and OS update flows.
4. Internal deployment rollback snapshots are not user-visible scheduled/pre-update backups and are always retained for transaction safety.
5. Minecraft recovery is health-first. A healthy server is not reinstalled or given a replacement world.
6. Production `deployment.json` is switched to 2.0.0 only after release CI and real-server readiness are proven.
