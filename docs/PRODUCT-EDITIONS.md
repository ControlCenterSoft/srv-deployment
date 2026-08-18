# Control Center — Product Editions & Licensing Architecture

> **Status:** canonical architecture decision for future edition-aware releases.

## Naming principle

The public product name is **Control Center**. The `SRV` prefix is no longer part of product branding.

Public edition names are:

- **Control Center Home**
- **Control Center Professional**

Existing low-level identifiers such as `srv-control.service`, `/opt/srv-control`, `srvcc-*`, repository paths and historical compatibility identifiers are technical implementation names. They are not product branding and must not be renamed in-place where doing so would break installed systems, frozen releases, update compatibility or rollback. New user-facing text must use Control Center naming.

## Principle

Control Center uses **one shared Control Center Core** and produces two editions. Home and Professional must not become independently diverging codebases.

## Home Edition

**Control Center Home** is intended for personal, home, non-commercial use.

- Home/non-commercial EULA.
- Single-server/single-domain baseline product model.
- Enterprise/fleet/HA capabilities may be restricted by entitlements.
- No artificial CPU/RAM/network-throughput throttling.
- Minecraft is included as a Home edition module.
- Core home Samba, DHCP, PXE, monitoring, backup and infrastructure capabilities remain available according to Home entitlements.

The Home EULA defines permitted use. The software must not attempt to infer whether a machine is physically located in a home or business.

## Professional Edition

**Control Center Professional** is intended for commercial use.

- Commercial EULA.
- Activation and signed commercial license.
- Full commercial entitlements according to the purchased license.
- Full Endpoint Management and future multi-server/HA capabilities according to entitlements.
- **Minecraft is excluded from the Professional build**, not merely hidden in the UI. Minecraft backend/API/helpers/systemd/templates/assets must not be shipped in the commercial artifact.

## Professional release lifecycle and update rights

Update entitlement is calculated from the **official release date of the applicable release line**, not from the customer's purchase or activation date.

For every commercially supported release line, Control Center publishes concrete lifecycle dates. The authoritative timestamps are stored in signed release/lifecycle metadata and are displayed in **System → About / О системе**.

Lifecycle policy:

1. **Full updates — 24 months from the official release date.** During this period the supported line receives applicable feature/minor updates, maintenance/bug-fix updates and security updates according to the release compatibility policy.
2. **Security-only period — the following 12 months.** After the first 24 months, the line receives security updates only. Functional/minor feature development is no longer included for that line.
3. **End of updates — 36 months from the official release date.** After this date free update entitlement for that release line ends. The already activated licensed installation is not disabled merely because its update period ended.
4. **Major upgrade is paid.** A new major product generation is a separately licensed upgrade unless the commercial agreement explicitly grants it.

Example: if a commercial major release `1.0.0` is officially released on `YYYY-MM-DD`, its default lifecycle is:

- Release date: `YYYY-MM-DD`;
- Full updates until: `YYYY-MM-DD + 24 months`;
- Security updates only until: `YYYY-MM-DD + 36 months`;
- End of updates: the latter date.

**Concrete dates must never be guessed in documentation or UI.** They are populated only when a release is actually published and its official release timestamp is known. For existing pre-commercial/development releases, no Professional commercial lifecycle date is claimed retroactively unless explicitly designated.

### About/System UI contract

For Control Center Professional, **О системе / About** must show at least:

- Product: Control Center Professional;
- installed version;
- official release date for the licensed/supported release line;
- full-updates-until date;
- security-updates-until date;
- lifecycle state: `Full updates`, `Security updates only`, or `Updates ended`;
- licensed major generation;
- license/activation status;
- update channel;
- link/reference to applicable release notes and license terms.

The Update Center must use the same signed lifecycle metadata, so UI display and update authorization cannot disagree.

## Edition enforcement

Edition is selected at build/release time and is not a user-editable UI switch. Entitlements are enforced at UI, API authorization, privileged helper and build-time module levels. The UI is never the sole security boundary.

## Installation identity — VM-safe licensing

Commercial licensing is bound to a **logical product installation**, not physical hardware.

At first installation Control Center creates a random `installation_id` UUID. This identity survives normal updates, reboots, VM virtual-hardware changes and recovery of the same installation.

MAC address, CPU/disk serial, motherboard UUID, SMBIOS UUID or hypervisor VM UUID must not be the primary licensing identity. They may only be optional risk signals. This model must support physical servers, KVM/Proxmox, Hyper-V, VMware and cloud VMs.

### License models

Architecture must support `per-installation`, future `per-host/cluster`, and future `floating/subscription` licensing. Clone detection uses activation records such as `license_id + installation_id + last_seen/activation state`, not brittle hardware locking. Legitimate migration uses deactivate/transfer/re-host. Disaster Recovery of the same logical server preserves installation identity.

## Signed licenses

Target design uses asymmetric signatures, with Ed25519 as the preferred design target. The licensing private key exists only in the licensing authority/service and never in the product repository or installed Control Center. Installed products contain only verification public material.

## Online and offline activation

Professional supports online activation over HTTPS and offline request/response activation for isolated enterprise networks. Temporary loss of Internet must not stop critical infrastructure services. License validation problems may restrict administrative commercial features after an appropriate grace policy, but must not shut down already-running Samba AD, DHCP, DNS or other critical services.

## Release signing

Edition architecture requires cryptographically signed release manifests in addition to SHA-256 integrity checks. Updater verifies edition/channel compatibility, hashes and signature before privileged preflight/apply.

## Update channels and CI

Home and Professional use edition-aware production channels/artifacts so cross-edition update cannot occur accidentally. A shared Core remains the development source. Every edition-sensitive Core change validates Core tests, Home build/entitlements/Minecraft, Professional build/activation, and explicit absence of Minecraft from Professional artifacts.

## EULA

Two agreements are required: Home EULA for personal/non-commercial use and Professional EULA for commercial rights, installation count, activation, transfer/re-host, release-based maintenance/update terms, support and termination. EULA and technical entitlement enforcement are separate layers. Final agreements require professional legal review before external commercial launch.

## Roadmap integration

- 1.4.x: prepare module boundaries, edition manifest and user-facing branding transition without destabilizing production.
- 1.5.x: License/Entitlement Engine foundations in DB/API/UI, including signed release lifecycle metadata and About/System lifecycle fields.
- 1.6.x: Professional activation/offline activation and signed releases; Ansible foundation is entitlement-aware.
- 1.7.x: Endpoint Management uses the same Desired State Core with Home vs Professional entitlements.
- 1.8.x: multi-server/HA is a Professional entitlement; Home remains single-server.

Detailed release scope remains in `docs/ROADMAP.md`. This document is the canonical architecture reference for editions, licensing, release lifecycle and public product naming.