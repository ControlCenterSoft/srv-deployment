#!/usr/bin/env python3
from __future__ import annotations

from pathlib import Path
import re

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


def effective_function(text: str, signature: str) -> str:
    start = text.rfind(signature)
    if start < 0:
        fail(f'missing effective function: {signature}')
    end = text.find('\ndef ', start + len(signature))
    return text[start:] if end < 0 else text[start:end]


def main() -> int:
    core = source(ROOT / 'payload/app/core/release14.parts')
    router = source(ROOT / 'payload/app/routers/release14.parts')
    agent = source(ROOT / 'system/srv-control-release14-agent.parts')
    main_py = (ROOT / 'payload/app/main.py').read_text(encoding='utf-8')

    require(main_py, "StaticFiles(directory='/srv/pxe/media'", "PUBLIC_PREFIXES = ('/static/', '/pxe/')")
    if "StaticFiles(directory='/srv/pxe'," in main_py:
        fail('private /srv/pxe/profiles would be exposed through StaticFiles')
    require(router, '/pxe/profile/{profile_id}/{token}/{artifact:path}', 'profile_boot_token_valid', '/pxe/consume/{profile_id}/{token}')

    require(core, 'def peek_boot_profile(', 'def consume_boot_profile(', 'install_authorized=false', "status='installing'")
    boot_route = router[router.index("@router.get('/pxe/boot.ipxe'"):router.index("@router.post('/pxe/report/")]
    require(boot_route, 'peek_boot_profile(mac)', 'boot_file.is_file()', 'Authorization retained', '_pxe_firmware_compatible(firmware, arch, image_arch)')
    if re.search(r'(?<!peek_)boot_profile\(mac\)', boot_route):
        fail('boot.ipxe still consumes authorization before payload validation')
    firmware_gate = effective_function(router, 'def _pxe_firmware_compatible(')
    require(
        firmware_gate,
        "fw in {'pcbios', 'bios'}",
        "return image in {'i386', 'x86_64'}",
        "if fw == 'efi':",
        "image not in {'i386', 'x86_64', 'arm32', 'arm64'}",
        'image == boot_arch',
    )

    # Structured network/PXE fields own these DHCP options.  A raw duplicate
    # must be rejected so option 67 cannot silently override managed PXE.
    require(core, 'MANAGED_DHCP_OPTION_CODES = {3, 6, 66, 67, 93, 175}', 'def _validate_extra_dhcp_option(')
    add_option = effective_function(core, 'def add_dhcp_option(')
    update_option = effective_function(core, 'def update_dhcp_option(')
    require(add_option, '_validate_extra_dhcp_option')
    require(update_option, '_validate_extra_dhcp_option')

    dhcp = effective_function(agent, 'def apply_dhcp() -> str:')
    require(
        dhcp,
        'dhcp-match=set:ipxe,175',
        'dhcp-userclass=set:ipxe,iPXE',
        'option:client-arch,0',
        'option:client-arch,6',
        'option:client-arch,7',
        'option:client-arch,9',
        'option:client-arch,10',
        'option:client-arch,11',
        'tag-if=set:pxe-noarch',
        'undionly.kpxe',
        'i386/snponly.efi',
        'x86_64-sb/snponly-shim.efi',
        'arm32/snponly.efi',
        'arm64-sb/snponly-shim.efi',
        "server = _interface_ipv4(str(c['interface']))",
    )
    if "{c['gateway']}" in '\n'.join(line for line in dhcp.splitlines() if 'dhcp-boot=' in line):
        fail('effective PXE next-server is still derived from gateway instead of interface address')

    require(
        agent,
        "IPXE_VERSION = 'v2.0.0'",
        'ipxeboot.tar.gz',
        "TFTP_ROOT / 'i386/snponly.efi'",
        "TFTP_ROOT / 'x86_64/snponly.efi'",
        "TFTP_ROOT / 'arm32/snponly.efi'",
        "TFTP_ROOT / 'arm64/snponly.efi'",
        "WIMBOOT_X64_URL",
        "WIMBOOT_I386_URL",
        "WIMBOOT_ARM64_URL",
        'platform=${platform}',
        'buildarch=${buildarch}',
        'isset ${net0/ip} || dhcp',
        'route\\n',
        'shell\\n',
        "IPXE_ARCHIVE_URL: '01a526d4cc791fc30362259c609d6c506cc64a7bdff51b9a5eb788354e17eee1'",
        "WIMBOOT_X64_URL: '5f067ccdc4d084d5bf77b6c853bd0f8402dfc2b4cd1b103d358993ae97fae8e3'",
        "WIMBOOT_I386_URL: 'b770ad4fa6111d688c062478de3849806b9c3e94a6b770453ef56c94fec254d9'",
        "WIMBOOT_ARM64_URL: 'b1440c6386981fb447b2f341294ec7a59546d496dff0f075b0f698c853f1c949'",
        "run(['sha256sum', str(target)]",
    )

    windows = effective_function(agent, 'def publish_windows(')
    require(
        windows,
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
        '/pxe/profile/',
        'imgfetch --name srv-consume',
        '/pxe/consume/',
        'boot || goto denied',
    )
    if windows.index('imgfetch --name srv-consume') > windows.index('boot || goto denied'):
        fail('Windows authorization consume happens after boot')

    linux = effective_function(agent, 'def publish_linux(')
    require(linux, 'ds=nocloud-net;s=', 'preseed/url=', 'secure_boot_shims', 'shim {base}/images/', 'imgfetch --name srv-consume')
    shim_copy = effective_function(agent, 'def _copy_linux_shims(')
    require(shim_copy, 'shimx64.efi', 'shimaa64.efi', 'BOOTX64.EFI', 'BOOTAA64.EFI')
    if 'BOOTIA32.EFI' in shim_copy:
        fail('Linux IA32 must not be advertised as managed Secure Boot capable')
    require(agent, "'secure_boot_capable': architecture in {'amd64', 'arm64'} and architecture in shims")

    samba = effective_function(agent, 'def ensure_pxe_samba_share(')
    require(samba, 'active directory domain controller', "['samba-tool', 'user', 'create'", 'PXE_MEDIA', 'valid users = srv-pxe')
    if "path = {PXE_ROOT}" in samba:
        fail('effective PXE Samba share still includes the private profiles directory')

    entries = agent.count("if __name__ == '__main__'") + agent.count("if __name__=='__main__'")
    if entries != 1:
        fail(f'release14 agent must contain exactly one __main__ entry point, found {entries}')

    print('PXE CONTRACT PASS: BIOS + UEFI IA32/x64/ARM32/ARM64, x64/ARM64 Secure Boot, firmware/image gate, Windows BIOS/UEFI, Linux unattended, deny-by-default, pinned-assets')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
