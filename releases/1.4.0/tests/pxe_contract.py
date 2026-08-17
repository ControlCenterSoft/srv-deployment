#!/usr/bin/env python3
from __future__ import annotations

from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[1]

EXPECTED = {
    ROOT / 'payload/app/core/release14.parts': [f'{n:02d}.part' for n in range(8)],
    ROOT / 'payload/app/routers/release14.parts': [f'{n:02d}.part' for n in range(4)],
    ROOT / 'system/srv-control-release14-agent.parts': [f'{n:02d}.part' for n in range(13)],
}


def fail(message: str) -> None:
    raise AssertionError(message)


def source(directory: Path) -> str:
    expected = EXPECTED[directory]
    actual = sorted(path.name for path in directory.glob('*.part'))
    if actual != expected:
        fail(f'unexpected source parts in {directory.relative_to(ROOT)}: expected={expected} actual={actual}')
    text = ''.join((directory / name).read_text(encoding='utf-8') for name in expected)
    compile(text, str(directory), 'exec')
    return text


def require(text: str, *needles: str) -> None:
    missing = [needle for needle in needles if needle not in text]
    if missing:
        fail('missing PXE contract anchors: ' + ', '.join(repr(item) for item in missing))


def main() -> int:
    core = source(ROOT / 'payload/app/core/release14.parts')
    router = source(ROOT / 'payload/app/routers/release14.parts')
    agent = source(ROOT / 'system/srv-control-release14-agent.parts')
    main_py = (ROOT / 'payload/app/main.py').read_text(encoding='utf-8')

    # Public/private separation: per-device profiles must never be a static tree.
    require(main_py, "StaticFiles(directory='/srv/pxe/media'", "PUBLIC_PREFIXES = ('/static/', '/pxe/')")
    if "StaticFiles(directory='/srv/pxe'," in main_py:
        fail('private /srv/pxe/profiles would be exposed through StaticFiles')
    require(router, '/pxe/profile/{profile_id}/{token}/{artifact:path}', 'profile_boot_token_valid', '/pxe/consume/{profile_id}/{token}')

    # Authorization must be peek -> stage payload -> consume, not consume on first boot.ipxe GET.
    require(core, 'def peek_boot_profile(', 'def consume_boot_profile(', 'install_authorized=false', "status='installing'")
    boot_route = router[router.index("@router.get('/pxe/boot.ipxe'"):router.index("@router.post('/pxe/report/")]
    require(boot_route, 'peek_boot_profile(mac)', 'boot_file.is_file()', 'Authorization retained')
    if re.search(r'(?<!peek_)boot_profile\(mac\)', boot_route):
        fail('boot.ipxe still consumes authorization before payload validation')

    # DHCP option 93 matrix and iPXE loop breaking.
    require(
        agent,
        'dhcp-match=set:ipxe,175',
        'dhcp-userclass=set:ipxe,iPXE',
        'option:client-arch,0',
        'option:client-arch,6',
        'option:client-arch,7',
        'option:client-arch,9',
        'option:client-arch,10',
        'option:client-arch,11',
        'undionly.kpxe',
        'i386-efi/snponly.efi',
        'x86_64-sb/snponly-shim.efi',
        'arm32-efi/snponly.efi',
        'arm64-sb/snponly-shim.efi',
    )
    require(agent, "IPXE_VERSION = 'v2.0.0'", 'ipxeboot.tar.gz', "WIMBOOT_X64_URL", "WIMBOOT_I386_URL", "WIMBOOT_ARM64_URL")
    require(agent, 'platform=${platform}', 'buildarch=${buildarch}', 'isset ${net0/ip} || dhcp', 'route\\n', 'shell\\n')

    # next-server must be the actual PXE/DHCP interface address, not the LAN gateway field.
    require(agent, 'def _interface_ipv4(', "server = _interface_ipv4(str(c['interface']))")
    if "{c['gateway']}" in '\n'.join(line for line in agent.splitlines() if 'dhcp-boot=' in line):
        fail('PXE next-server is still derived from gateway instead of interface address')

    # Windows: one x64 profile must be able to install in both real firmware modes.
    require(
        agent,
        'PEFirmwareType',
        'diskpart-bios.txt',
        'diskpart-uefi.txt',
        'convert mbr',
        'convert gpt',
        'set BootMode=BIOS',
        'set BootMode=UEFI',
        'bcdboot W:\\\\Windows /s S: /f %BootMode%',
        'wimboot.i386',
        'wimboot.arm64',
    )
    windows_start = agent.index('def publish_windows(')
    linux_start = agent.index('def publish_linux(')
    windows = agent[windows_start:linux_start]
    require(windows, '/pxe/profile/', 'imgfetch --name srv-consume', '/pxe/consume/', 'boot || goto denied')
    if windows.index('imgfetch --name srv-consume') > windows.index('boot || goto denied'):
        fail('Windows authorization consume happens after boot')

    # Linux: unattended Ubuntu/Debian plus signed distro shim when present.
    linux = agent[linux_start:]
    require(linux, 'ds=nocloud-net;s=', 'preseed/url=', 'secure_boot_shims', 'shim {base}/images/', 'imgfetch --name srv-consume')

    # Samba AD DC is a supported production role; never expose the private profiles share.
    require(agent, 'active directory domain controller', "['samba-tool', 'user', 'create'", 'PXE_MEDIA', 'valid users = srv-pxe')
    if "path = {PXE_ROOT}" in agent:
        fail('PXE Samba share still includes the private profiles directory')

    # Exactly one executable entry point after all compatibility overrides.
    if agent.count("if __name__ == '__main__'") != 1 and agent.count("if __name__=='__main__'") != 1:
        fail('release14 agent must contain exactly one __main__ entry point')

    print('PXE CONTRACT PASS: BIOS + UEFI IA32/x64/ARM32/ARM64, x64/ARM64 Secure Boot, Windows BIOS/UEFI, Linux unattended, deny-by-default')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
