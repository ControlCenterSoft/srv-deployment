# SRV Control Center — Product Editions & Licensing Architecture

> **Status:** canonical architecture decision for future edition-aware releases.

## Principle

SRV Control Center uses **one shared SRV Core** and produces two editions. Home and Professional must not become independently diverging codebases.

## Home Edition

**SRV Control Center Home** is intended for personal, home, non-commercial use.

- Home/non-commercial EULA.
- Single-SRV/single-domain baseline product model.
- Enterprise/fleet/HA capabilities may be restricted by entitlements.
- No artificial CPU/RAM/network-throughput throttling.
- Minecraft is included as a Home edition module.
- Core home Samba, DHCP, PXE, monitoring, backup and infrastructure capabilities remain available according to Home entitlements.

The Home EULA defines permitted use. The software must not attempt to infer whether a machine is physically located in a home or business.

## Professional Edition

**SRV Control Center Professional** is intended for commercial use.

- Commercial EULA.
- Activation and signed commercial license.
- Full commercial entitlements according to the purchased license.
- Full Endpoint Management and future Multi-SRV/HA capabilities according to entitlements.
- **Minecraft is excluded from the Professional build**, not merely hidden in the UI. Minecraft backend/API/helpers/systemd/templates/assets must not be shipped in the commercial artifact.

## Edition enforcement

Edition is selected at build/release time and is not a user-editable UI switch.

Entitlements are enforced at multiple layers:

1. UI capability exposure.
2. API authorization/feature gate.
3. Privileged helper/system action gate.
4. Build-time module inclusion/exclusion where appropriate.

The UI is never the sole security boundary.

## Installation identity — VM-safe licensing

Commercial licensing is bound to a **logical product installation**, not physical hardware.

At first installation SRV creates a random `installation_id` UUID. This identity survives normal updates, reboots, VM virtual-hardware changes and recovery of the same installation.

MAC address, CPU/disk serial, motherboard UUID, SMBIOS UUID or hypervisor VM UUID must **not** be the primary licensing identity. They may only be optional risk signals.

This model must support physical servers, KVM/Proxmox, Hyper-V, VMware and cloud VMs.

### License models

Architecture must support:

- `per-installation`: a license permits a defined number of active installation IDs;
- `per-host/cluster`: future licensing for virtualization/HA environments;
- `floating/subscription`: future concurrent-instance licensing.

Clone detection uses activation records such as `license_id + installation_id + last_seen/activation state`, not brittle hardware locking.

A legitimate migration uses deactivate/transfer/re-host. Disaster Recovery of the same logical server preserves installation identity.

## Signed licenses

Target design uses asymmetric signatures (Ed25519 is the preferred design target).

- Licensing private key exists only in the licensing authority/service and never in the product repository or installed Control Center.
- Installed products contain only verification public material.
- License payload contains product/edition/license identity, installation assignment, validity/maintenance and entitlements.
- License secrets/activation credentials are never returned by normal API after storage.

## Online and offline activation

Professional supports both:

- online activation over HTTPS;
- offline request/response activation for isolated enterprise networks.

Temporary loss of Internet must not stop critical infrastructure services. License validation problems may restrict administrative commercial features after an appropriate grace policy, but must not shut down already-running Samba AD, DHCP, DNS or other critical services.

## Release signing

Edition architecture also requires cryptographically signed release manifests in addition to SHA-256 integrity checks. Updater verifies edition/channel compatibility, hashes and signature before privileged preflight/apply.

## Update channels

Home and Professional use edition-aware production channels/artifacts so cross-edition update cannot occur accidentally. A shared Core remains the development source.

## CI matrix

Every edition-sensitive Core change must validate:

- Core tests;
- Home build and Home entitlement contract;
- Home Minecraft regression;
- Professional build and commercial entitlement/activation contract;
- explicit assertion that Professional artifacts contain no Minecraft payload.

## EULA

Two agreements are required:

- Home EULA: personal/non-commercial rights and restrictions;
- Professional EULA: commercial rights, installation count, activation, transfer/re-host, maintenance/update terms, support and termination.

EULA and technical entitlement enforcement are separate layers. Final agreements require professional legal review before external commercial launch.

## Roadmap integration

- 1.4.x: prepare module boundaries and edition manifest without destabilizing production.
- 1.5.x: License/Entitlement Engine foundations in DB/API/UI.
- 1.6.x: Professional activation/offline activation and signed releases; Ansible foundation is entitlement-aware.
- 1.7.x: Endpoint Management uses the same Desired State Core with Home vs Professional entitlements.
- 1.8.x: Multi-SRV/HA is a Professional entitlement; Home remains single-SRV.

Detailed release scope remains in `docs/ROADMAP.md`. This document is the canonical architecture reference for editions and licensing.