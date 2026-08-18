# Control Center — Branding and Naming Policy

## Canonical public name

The product family is named **Control Center**.

Approved public edition names:

- **Control Center Home**
- **Control Center Professional**

The prefix `SRV` must not be used in new product names, UI headings, EULA titles, manuals, roadmap prose, release notes, marketing text, screenshots, activation portal text or new public-facing API/product metadata.

## Migration rule

Existing documentation is migrated from `SRV Control Center` to `Control Center`. Future documentation must use the new naming from the start.

Published/frozen release payloads are immutable and are not rewritten only to change branding. User-visible branding in installed software is changed through a new versioned release and normal deployment/acceptance process.

## Technical compatibility identifiers

The branding change does **not** automatically rename established technical identifiers where that would break compatibility. Examples include:

- `srv-control.service`;
- `srv-control` Unix user;
- `/opt/srv-control` and `/var/lib/srv-control`;
- `srvcc-*` updater/helper names;
- existing database identifiers;
- repository name `srv-deployment`;
- historical release metadata/fingerprints;
- `server-state` compatibility channel.

These identifiers are implementation details, not the public product name. Any future technical namespace migration requires a separate compatibility plan, migrations, rollback support and acceptance tests.

## Terminology

Use **Control Center Core** instead of `SRV Core`.
Use **Recovery Bundle** instead of `SRV Recovery Bundle`.
Use **application manifest** or **Control Center application manifest** instead of `SRV manifest` where the term is user-facing.
Use **multi-server** instead of `Multi-SRV` in public product descriptions.

## Editions

Home: **Control Center Home**.
Professional/commercial: **Control Center Professional**.

Minecraft remains Home-only according to `docs/PRODUCT-EDITIONS.md` and must be physically absent from Professional build artifacts.

## Enforcement

Documentation review and future CI should reject new user-facing occurrences of `SRV Control Center`, `SRV Control Center Home`, `SRV Control Center Professional` and other deprecated public branding outside explicitly marked historical/compatibility contexts.