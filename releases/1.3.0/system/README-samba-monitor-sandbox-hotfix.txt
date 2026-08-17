SRV Control Center 1.3.0 Samba monitor sandbox hotfix

Problem observed on the real HM.DM domain:
- Root shell ldbsearch saw 11 users and 41 groups.
- The systemd collector returned `Samba default naming context not found` and an empty directory snapshot.
- The service uses ProtectSystem=strict, while local Samba/LDB reads require Samba lock/runtime state to remain writable.

The service keeps ProtectSystem=strict and grants write access only to:
- /var/lib/srv-control
- /var/lib/samba
- optional /var/cache/samba
- optional /run/samba

No Samba domain data, users, groups, policies or shares are mutated by this hotfix.
