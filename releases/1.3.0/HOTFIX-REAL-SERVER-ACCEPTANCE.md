# 1.3.0 real-server acceptance hotfix

Production acceptance now prepares the isolated restored Samba runtime cache directory before `testparm`, matching the already validated CI restore flow. Live Samba health, backup checksum, restore, realm and SID verification remain enforced.
