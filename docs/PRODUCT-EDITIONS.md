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
- Maximum **10 domain user accounts** per Home installation.
- Maximum **10 configured network shares** (SMB/network shared resources) per Home installation.
- Exceeding either Home limit requires **Control Center Professional**, even when the installation remains physically located in a home environment.
- Any commercial/business use requires **Control Center Professional regardless of user/share counts**.
- Enterprise/fleet/HA capabilities may be restricted by entitlements.
- No artificial CPU/RAM/network-throughput throttling.
- Minecraft is included as a Home edition module.
- Core home Samba, DHCP, PXE, monitoring, backup and infrastructure capabilities remain available according to Home entitlements.

The Home EULA defines permitted use. The software must not attempt to infer whether a machine is physically located in a home or business. Home entitlement enforcement must use explicit edition/license state and configured resource counts, not environmental guessing.

## Professional Edition

**Control Center Professional** is intended for commercial use and for deployments that require capabilities or scale beyond Control Center Home limits.

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

For Home, edition-aware entitlement checks must account for the canonical limits of **10 domain users** and **10 network shares**. Attempts to exceed either limit must not silently create an unsupported Home configuration; the product must present a clear Professional-upgrade requirement without disrupting already-running critical infrastructure services.

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

Two agreements are required: Home EULA for personal/non-commercial use and Professional EULA for commercial rights, installation count, activation, transfer/re-host, release-based maintenance/update terms, support and termination. The Home EULA must explicitly state the limits of **10 domain users** and **10 network shares**. EULA and technical entitlement enforcement are separate layers. Final agreements require professional legal review before external commercial launch.

## Default staged licensing rollout

Licensing is a **mandatory sequential release track**. When preparation of each new feature release begins, the next not-yet-accepted stage below is included in that release scope automatically unless the user explicitly changes the plan.

Rules:

1. Stages are implemented strictly in order and are not skipped.
2. A stage is considered complete only after implementation, regression tests, migration/upgrade tests where applicable, security review and release acceptance.
3. If a stage is incomplete at release time, it remains the active licensing stage for the next feature release; the project does not advance to the following stage merely because a version number changed.
4. Emergency repair/hotfix patch releases do **not** consume or advance the licensing stage unless they explicitly contain the remaining work for that stage.
5. Every new feature-release scope must state which licensing stage is active and include its acceptance criteria.
6. Documentation, site messaging and product behavior must not advertise a later stage as available before its acceptance is complete.

### Stage 1 — Edition / Entitlement Engine

**Default target: the next feature release, currently 2.0.0.**

- Control Center understands `Home` and `Professional` as explicit edition state.
- Central entitlement service/API is introduced; UI is not the sole enforcement layer.
- Home limits are enforced at relevant API and privileged-operation boundaries: **10 domain users** and **10 network shares**.
- Attempts to create the 11th domain user or 11th network share are rejected safely with a clear Professional-upgrade message.
- Existing critical services are never stopped merely because a limit is reached.
- Add **System → About / License** (or equivalent) showing edition, entitlement state, Home limits/usage and future activation status placeholder.
- Add DB/state schema foundations needed by later licensing stages without requiring a commercial activation server yet.

### Stage 2 — Signed local Professional licenses

**Default target: the next feature release after Stage 1 acceptance.**

- Generate and persist VM-safe random `installation_id`.
- Define signed license certificate format.
- Verify licenses locally using embedded verification public material; Ed25519 is the preferred target.
- Private signing keys never ship in GitHub, installers or customer systems.
- Professional entitlement state becomes loadable from a valid signed license certificate.
- Invalid/tampered licenses fail closed for commercial administrative entitlements while already-running critical infrastructure services remain available.

### Stage 3 — Online activation service

**Default target: the next feature release after Stage 2 acceptance.**

- Introduce licensing API under the official `control-center.pro` service namespace (for example `api.control-center.pro`).
- License/activation database supports customer/license/installation/activation/entitlement/audit records.
- Activation key is an activation credential, not the runtime license itself.
- Online activation issues a signed license certificate bound to logical `installation_id`.
- Support deactivate / transfer / re-host workflows and activation-count enforcement.
- Product can continue using a previously valid signed local license during temporary network loss.

### Stage 4 — Offline activation

**Default target: the next feature release after Stage 3 acceptance.**

- Product exports a signed/bounded activation request containing installation identity and nonce.
- Connected portal/API accepts the request plus commercial activation credential.
- Portal returns a signed license response/certificate for import into the isolated Control Center installation.
- Replay, substitution and cross-installation misuse are rejected.
- Offline-activated systems do not require continuous Internet access for critical infrastructure operation.

### Stage 5 — Customer licensing portal

**Default target: the next feature release after Stage 4 acceptance.**

- Customer area on `control-center.pro` for licenses and installations.
- View activation status and permitted installation count.
- Deactivate/transfer/re-host a license according to policy.
- Generate/download offline activation responses.
- Show applicable update lifecycle/entitlement and license documents.
- Keep licensing administration separate from the Control Center server's privileged infrastructure control plane.

After Stage 5, new licensing work becomes normal roadmap evolution rather than automatic stage advancement.

## Roadmap integration

The former fixed mapping to 1.4.x/1.5.x/1.6.x/1.7.x/1.8.x is superseded by the sequential staged rule above because the canonical product roadmap has moved to the 2.x line.

- **2.0.0:** must include Stage 1 — Edition / Entitlement Engine.
- **Next feature release after accepted 2.0.0:** Stage 2.
- **Following feature release:** Stage 3.
- **Following feature release:** Stage 4.
- **Following feature release:** Stage 5.

Exact later version numbers are intentionally not guessed in advance; `docs/ROADMAP.md` and each release scope assign the next stage when that release starts preparation.

Detailed release scope remains in `docs/ROADMAP.md`. This document is the canonical architecture reference for editions, licensing, release lifecycle and public product naming.
