# Control Center 1.0.11 — Documentation Compliance Matrix

Release: **1.0.11**  
Build: **20260819.5**  
Source of truth: `README.md` + `docs/*.md` + `releases/1.0.11/manifest.json`.

`deployment.json.audit` MUST remain `pending` until every runtime-required row below is proven by the final commit's CI run.

| Requirement | Source document | Implementation evidence | Acceptance evidence | Gate |
|---|---|---|---|---|
| Version/build are 1.0.11 / 20260819.5 | README, INSTALL | `app/release.json`, VERSION/BUILD install flow | static release CI + runtime version check | required |
| PostgreSQL schema migration 005 | README, POSTGRESQL | `app/migrations/005_rbac_services_dhcp.sql` | schema/table/dependency checks | required |
| Portal requires authentication | AUTHENTICATION, SECURITY | `app/release_111_auth.py` | unauthenticated `/api/market` = 401 | required |
| Local authentication uses PAM via isolated root daemon | AUTHENTICATION, SECURITY | `system/control-center-authd`, `/etc/pam.d/control-center-web` | real local admin/viewer login | required |
| Web process cannot read shadow / privileged auth state | AUTHENTICATION, SECURITY | systemd sandbox + auth Unix socket | socket ownership + secret-boundary checks | required |
| Clean server gets `controladmin` nologin account | AUTHENTICATION, INSTALL | `install/install.sh` | `bootstrap-auth` runtime job | required |
| Clean-install password is random, shown once, not persisted plaintext | AUTHENTICATION, INSTALL, SECURITY | `install/install.sh` | masked runtime login + filesystem secret scan | required |
| Domain authentication is enabled after AD activation | AUTHENTICATION, README | `control-center-authd`, `release_111_auth.py` | real domain admin/viewer login | required |
| Bootstrap portal roles are admin/viewer | AUTHENTICATION | migration 005 + auth layer | local/domain authorization checks | required |
| Domain group `Control Center Admins` is mandatory | AUTHENTICATION, SAMBA-AD-DC | `system/control-center-domain-post` | membership `Administrator` and domain test admin | required |
| Market exposes Domain | README | `app/release_111_services.py` | Market/API test | required |
| Market exposes standalone DNS | README | `market/control-center-dns-apply` | real Unbound install/config | required |
| Market exposes standalone Network Storage | README | `market/control-center-storage-apply` | real Samba standalone install | required |
| Domain requires DNS and Storage | README, SAMBA-AD-DC | service dependency schema/orchestrator | readiness dependency plan | required |
| Existing standalone DNS/Storage transition into Domain mode | README, SAMBA-AD-DC | domain pre/post context | runtime standalone → Domain transition | required |
| Existing standalone DNS/Storage return after Domain removal | README, SAMBA-AD-DC | `control-center-domain-restore-prestate` | runtime Domain removal restore | required |
| Domain wizard uses Static active network role | NETWORK, SAMBA-AD-DC | readiness + root revalidation | disposable Static LAN provisioning | required |
| Arbitrary AD interface/IP cannot be injected by Web API | NETWORK, SAMBA-AD-DC | readiness/network role resolution | static/API contract check | required |
| Active DC hostname cannot be changed | README, NETWORK | hostname guard | HTTP 409 runtime check | required |
| Active DC interface/IP/prefix/method cannot be changed | README, NETWORK | network guard | HTTP 409 runtime check | required |
| Active Domain DNS/Storage cannot be removed | README, DNS/Storage lifecycle | Market guards | HTTP 409 runtime checks | required |
| Domain clients receive AD-DC as DHCP DNS | NETWORK, DHCP | DHCP/Domain integration | runtime DHCP config = DC IP only | required |
| DHCP client inventory exposes leases + reservations | DHCP | `release_111_dhcp.py` | real API check | required |
| DHCP reservations support reserve/edit/release and validation | DHCP | API + privileged reservations worker | real reservation config + DB check | required |
| DHCP client UI is paginated by exactly 10 rows | DHCP | `release-111-compliance.js` | static asset contract + runtime served asset check | required |
| DC IP cannot be reserved to a DHCP client | DHCP, NETWORK | reservation validation | API/root validation contract | required |
| Domain Administrator secret is not persisted | SAMBA-AD-DC, SECURITY | `/run` request boundary, no `--adminpass` | runtime filesystem/DB secret scan | required |
| Provisioning uses purpose-bound one-time approval | SAMBA-AD-DC, SECURITY | `control-center-samba-approve` | real approval code provisioning | required |
| Domain removal uses separate purpose-bound approval and confirmation | SAMBA-AD-DC, SECURITY | removal approval + API | real guarded removal | required |
| Domain removal requires proof of single DC | SAMBA-AD-DC, SECURITY | `control-center-domain-destroy` | runtime topology/removal check | required |
| AD acceptance includes LDAP, DRS, DNS, Kerberos, SYSVOL | SAMBA-AD-DC | Domain orchestrator | real runtime acceptance | required |
| Built-in Administrator RID 500 must map to UID 0 | SAMBA-AD-DC, SECURITY | orchestrator SID acceptance | `wbinfo --name-to-sid` + `--sid-to-uid` | required |
| Authenticated SMB must pass before Domain becomes active | SAMBA-AD-DC | orchestrator smbclient acceptance | real runtime acceptance | required |
| Domain package changes have exact reversible pre-state | SAMBA-AD-DC, INSTALL, SECURITY | `control-center-samba-package-guard` | package presence/version/manual-auto comparison | required |
| Exact rollback bytes are prepared before Domain mutation | SAMBA-AD-DC, SECURITY | `apt-get -s` + `apt-get download` | static contract + runtime persistent pre-state | required |
| Failed Domain provisioning restores pre-state | SAMBA-AD-DC | service ExecStopPost + restore worker | runtime failure path when encountered / static invariant | required |
| Successful Domain removal restores package/config/service pre-state | SAMBA-AD-DC | persistent package pre-state + restore worker | runtime post-removal exact comparison | required |
| Domain cleanup compares deterministic fingerprints | README, SAMBA-AD-DC | domain destroy cleanup audit | runtime `prestate_fingerprints_match` | required |
| Generated `sam.ldb` and SYSVOL are removed if absent before | README, SAMBA-AD-DC | cleanup audit | runtime generated artifact checks | required |
| DNS removal performs cleanup audit | README, NOTIFICATIONS | DNS worker | runtime cleanup audit | required |
| Storage removal performs cleanup audit and preserves user files | README, NOTIFICATIONS | Storage worker | runtime preserved file + audit | required |
| Notification center exposes DNS/Storage/DHCP/cleanup lifecycle | NOTIFICATIONS | notification aggregation | runtime source set + cleanup history | required |
| Full uninstall cannot bypass managed service lifecycle | README, INSTALL, SECURITY | `install/uninstall.sh` guards | static release contract / acceptance | required |
| `--keep-data` preserves managed service state/data | INSTALL, SECURITY | uninstall mode | static contract | required |
| `dpkg --audit` is clean after lifecycle | README / release acceptance | package lifecycle workers | final runtime `dpkg --audit` | required |

## Release completion rule

Release 1.0.11 can be marked fully compliant only when the **same final branch head** has:

```text
Validate Control Center release  = success
Validate Control Center runtime  = success
  bootstrap-auth                  = success
  runtime                         = success
```

Only after that may:

```json
"audit": "passed"
```

be written to `deployment.json` and the release be considered ready for merge/publication.
