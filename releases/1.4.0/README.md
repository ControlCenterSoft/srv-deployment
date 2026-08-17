# SRV Control Center 1.4.0

Release 1.4.0 activates the DHCP and PXE foundations that already existed in the Control Center schema and adds managed network and folder-redirection workflows.

## Included

- Services: install/remove DHCP Server (`dnsmasq`) and PXE Server (TFTP/iPXE/wimboot).
- DHCP: interface/network/netmask/pool/gateway/DNS/lease configuration, arbitrary DHCP option code/value pairs, reservations and live lease view.
- PXE Server Windows: ISO upload and preparation, Windows edition discovery, per-MAC computer profiles, multiple software/configuration profiles, optional domain target, one-time authorization and deny-by-default boot.
- PXE Server Linux: Ubuntu/Debian ISO preparation, autoinstall/preseed generation and the same per-MAC one-time authorization model.
- PXE safety: a MAC without an existing and authorized profile never receives an installer. Authorization is consumed on the first accepted boot and must be explicitly re-enabled for another installation attempt.
- Backup retention: optional maximum number of retained Control Center backups; `0` keeps unlimited copies.
- Network: separate WAN/LAN/Wi-Fi UI, DHCP/static/PPPoE/L2TP WAN modes, Wi-Fi client/AP/repeater modes, dual-radio 2.4/5 GHz AP support, and a 120-second fail-safe network rollback until the new configuration is confirmed.
- Shared/network access: folder redirect profiles for standard Windows folders and arbitrary application folders, with user/group/computer/PXE-profile assignments.

## Upgrade contract

- Supported source: installed Control Center `1.3.x` with Alembic head `13f0a1300001`.
- Pre-release backup is mandatory and created with the existing Control Center backup worker.
- Database head after upgrade: `14f0a1400001`.
- Application deployment is incremental: existing 1.3 modules are retained; 1.4 adds a dedicated router/core module and shadows only the upgraded UI routes.
- Rollback downgrades the schema to `13f0a1300001` and restores every changed path from the deployment backup.

## Acceptance highlights

Acceptance verifies the application health endpoint, release metadata, Python imports, Alembic head, new database tables, path agents and the public PXE authorization endpoint. An unknown synthetic MAC must return an explicit installation denial and must not receive `kernel`, `boot.wim`, or `autoinstall` payloads.
