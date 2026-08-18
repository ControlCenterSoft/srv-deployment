# Control Center 2.0.0

## Status

2.0.0 is staged in `release/2.0.0` and must remain non-production until all release gates pass. The accepted production deployment remains 1.3.8 during staging.

## Major changes

### Interface

The web interface is rebuilt around the approved Control Center design: left navigation, top status bar, redesigned dashboard, consistent dark workspace surfaces, responsive mobile navigation, shared modal/toast interactions, keyboard navigation, accessibility states, responsive tables, loading skeletons and consistent object editors.

The redesign covers login, dashboard, network, services, system/update center, domain and access, network shares, RBAC, AdGuard VPN, downloads and Minecraft Bedrock management.

### Product updater

The legacy updater is replaced by `srvcc-update-controller`, while the established unit/API names remain compatible. The new status schema separately tracks:

- last update check;
- last update attempt;
- last successful accepted update;
- transaction id and stage;
- failed/blocked release fingerprint.

A release fingerprint that failed automatic application is not repeatedly applied on every timer invocation. Checks continue and the timer remains active. A changed release fingerprint can be considered again.

### Backups

The System page gains multi-select and bulk deletion of backups. Bulk deletion reuses the existing privileged system action queue and does not bypass CSRF or administrator checks.

The pre-update backup policy is made authoritative. In the 1.x path, release apply could create a pre-release backup even when the outer updater had correctly read `backup_before_update=false`. 2.0 removes that unconditional user-visible backup from apply. A private rollback snapshot is still created because it is part of the deployment transaction, not the configured backup schedule.

### Minecraft Bedrock

2.0 introduces a health-first repair flow. It verifies service activity, the Bedrock UDP listener and active-world information. A healthy server is left unchanged. If unhealthy, 2.0 attempts a safety backup, update/reinstall through the proven server management path and restart. Only if the server remains unhealthy and a safety backup exists may a replacement recovery world be selected.

## Update-center text

The System workspace displays:

- `Автоматическое обновление` — current configured mode/timer state;
- `Последняя проверка обновления` — discovery/check timestamp;
- `Последнее успешное обновление` — last transaction that reached accepted success.

The historical successful timestamp is preserved during migration rather than overwritten by a check or failed attempt.

## Required release gates

Before production activation:

1. `main` must be an ancestor of the 2.0 release head so all published 1.x work is carried forward.
2. Manifest hashes must match the exact release scripts.
3. Shell, Python and JavaScript validation must pass.
4. UI, updater, backup and Minecraft regression contracts must pass.
5. Upgrade from the actual 1.3.8 production state must pass preflight/apply/acceptance/rollback simulation.
6. Production server must complete the 1.3.8 → 2.0.0 transaction and publish fresh `server-state` proving the new version and service health.
7. Only after successful real-server acceptance may obsolete unpublished 1.x branches be removed.
