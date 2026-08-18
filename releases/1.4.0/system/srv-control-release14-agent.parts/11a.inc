
# Multi-NIC transport hardening inserted after the Windows/Linux base
# generators and before the final release14 wrappers in 12.part.
# The initial authorization request already uses netX; the one-time consume
# must use the same active iPXE interface instead of assuming net0.


def _rewrite_profile_consume_to_active_nic(target: Path) -> None:
    boot = target / 'boot.ipxe'
    if not boot.is_file():
        raise RuntimeError('generated PXE profile has no boot.ipxe')
    value = boot.read_text(encoding='utf-8')
    if '${net0/mac}' in value:
        value = value.replace('${net0/mac}', '${netX/mac}')
    if '${net0/mac}' in value:
        raise RuntimeError('generated PXE profile still contains fixed net0 MAC')
    if '/pxe/consume/' in value and '${netX/mac}' not in value:
        raise RuntimeError('generated PXE consume URL is not bound to the active iPXE interface')
    boot.write_text(value, encoding='utf-8')


_publish_windows_active_nic = publish_windows


def publish_windows(profile: dict, config: dict, target: Path, server: str, cred: dict) -> None:
    _publish_windows_active_nic(profile, config, target, server, cred)
    _rewrite_profile_consume_to_active_nic(target)


_publish_linux_active_nic = publish_linux


def publish_linux(profile: dict, config: dict, target: Path, server: str) -> None:
    _publish_linux_active_nic(profile, config, target, server)
    _rewrite_profile_consume_to_active_nic(target)
