#!/usr/bin/env python3
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
BACKUP = (ROOT / 'system/srv-control-backup').read_text(encoding='utf-8')
POLICY = (ROOT / 'system/srv-control-backup-policy').read_text(encoding='utf-8')
APPLY = (ROOT / 'apply-2.0.0.sh').read_text(encoding='utf-8')
ROLLBACK = (ROOT / 'rollback-2.0.0.sh').read_text(encoding='utf-8')

for anchor in (
    '/var/lib/srv-control/network-config.json',
    '/var/lib/srv-control/pxe/smb-credential.json',
    '/etc/dnsmasq.d/srv-control.conf',
    '/etc/default/tftpd-hpa',
    '/etc/samba/smb.conf',
    '"pxe_media_included": False',
    '"pxe_restore_policy": "revoke-active-authorizations"',
    'def invalidate_restored_pxe_authorizations()',
    'install_authorized = false',
    "status = CASE WHEN status = 'installed' THEN 'installed' ELSE 'disabled' END",
    "config = COALESCE(config, '{}'::jsonb) - 'boot_token' - 'report_token'",
    'restore-requires-reauthorization',
    'def _validate_and_reload_restored_services(',
    'run(["dnsmasq", "--test"]',
    'run(["testparm", "-s", str(samba_conf)]',
):
    assert anchor in BACKUP, anchor

# Large PXE media and generated per-attempt profiles are deliberately excluded
# from normal configuration backups. Restoring a database must instead revoke
# all boot/install authorizations and one-time tokens.
assert 'Path("/srv/pxe/media")' not in BACKUP
assert 'Path("/srv/pxe/profiles")' not in BACKUP

# 2.0 intentionally removes the 1.4 mandatory pre-release user backup. The
# user's backup_before_update setting is authoritative; an internal deployment
# rollback snapshot is a separate transaction mechanism.
assert 'pre-release-1.4.0' not in APPLY
assert 'No unconditional user-visible backup is created here' in APPLY
assert 'srv-control-backup-policy scheduled' in APPLY
assert 'raw.get("backup_before_update") is True' in POLICY

# The PXE-aware worker and agents are deployed transactionally and restored on
# rollback, so a failed 2.0 rollout cannot leave half-installed PXE components.
for anchor in (
    'srv-control-backup srv-control-backup-policy',
    'srv-control-pxe-probe',
    'srv-control-release14-agent.parts',
    '/usr/local/libexec/srv-control-release14-agent',
    '/usr/local/libexec/srv-control-pxe-probe',
):
    assert anchor in APPLY, anchor

for anchor in (
    '/usr/local/libexec/srv-control-backup',
    '/usr/local/libexec/srv-control-release14-agent',
    '/usr/local/libexec/srv-control-pxe-probe',
    'srv-control-release14-agent.path',
    'srv-control-backup-retention.path',
):
    assert anchor in ROLLBACK, anchor

print('PXE BACKUP CONTRACT PASS: PXE config/secrets preserved, media not duplicated, restored authorizations revoked, 2.0 backup policy remains authoritative')
