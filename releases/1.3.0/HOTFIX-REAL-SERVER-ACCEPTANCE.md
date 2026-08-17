# 1.3.0 real-server acceptance hotfix

Production acceptance prepares the isolated restored Samba runtime cache directory before `testparm`, matching the validated CI restore flow.

The real-server SID validation now resolves the restored domain `defaultNamingContext` from `sam.ldb` and reads `objectSid` from that domain root instead of incorrectly requesting `objectSid` from RootDSE (`-b ''`). Empty naming-context and SID results fail with dedicated diagnostics before the final live/restored SID comparison.

Live Samba health, backup checksum, isolated restore, realm verification and SID verification remain enforced.
