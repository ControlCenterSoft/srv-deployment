#!/usr/bin/env python3
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
BACKUP = (ROOT / 'system/srv-control-backup').read_text(encoding='utf-8')
APPLY = (ROOT / 'apply.sh').read_text(encoding='utf-8')
ROLLBACK = (ROOT / 'rollback.sh').read_text(encoding='utf-8')

for anchor in (
    '/var/lib/srv-control/network-config.json',
    '/var/lib/srv-control/pxe/smb-credential.json',
    '/etc/dnsmasq.d/srv-control.conf',
    '/etc/default/tftpd-hpa',
    '/etc/samba/smb.conf',
    '"pxe_media_included": False',
    '"pxe_restore_policy": "revoke-active-authorizations"',
    'def invalidate_restored_pxe_authorizations()',
    "install_authorized = false",
    "status = CASE WHEN status = 'installed' THEN 'installed' ELSE 'disabled' END",
    "config = COALESCE(config, '{}'::jsonb) - 'boot_token' - 'report_token'",
    'restore-requires-reauthorization',
    'def _validate_and_reload_restored_services(',
    "run([\"dnsmasq\", \"--test\"]",
    "run([\"testparm\", \"-s\", str(samba_conf)]",
):
    assert anchor in BACKUP, anchor

# Large media is deliberately excluded from routine config backups; restore
# must revoke all boot permissions instead of reviving stale attempt artifacts.
assert 'Path("/srv/pxe/media")' not in BACKUP
assert 'Path("/srv/pxe/profiles")' not in BACKUP

pre = APPLY.index('/usr/local/libexec/srv-control-backup create --actor system --reason pre-release-1.4.0')
install = APPLY.index('"$RELEASE_DIR/system/srv-control-backup" /usr/local/libexec/srv-control-backup')
assert pre < install, '1.4 worker replaced before mandatory 1.3 pre-release backup'
assert '/usr/local/libexec/srv-control-backup' in APPLY
assert '/usr/local/libexec/srv-control-backup' in ROLLBACK

print('PXE BACKUP CONTRACT PASS: config/secrets preserved, media not duplicated, restored authorizations/tokens revoked')
