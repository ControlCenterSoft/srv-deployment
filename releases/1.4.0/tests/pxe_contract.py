#!/usr/bin/env python3
from __future__ import annotations

from pathlib import Path
import re
import tempfile

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


def exercise_agent_runtime(agent: str) -> None:
    ns: dict = {'__name__': 'srvcc_pxe_contract_agent'}
    exec(compile(agent, '<release14-agent-contract>', 'exec'), ns)

    original_run = ns['run']
    try:
        ns['run'] = lambda *args, **kwargs: (
            '2: lan0    inet 10.10.0.9/24 brd 10.10.0.255 scope global lan0\n'
            '2: lan0    inet 192.168.10.1/24 brd 192.168.10.255 scope global secondary lan0\n'
        )
        selected = ns['_interface_ipv4']('lan0', '192.168.10.0', '255.255.255.0')
        if selected != '192.168.10.1':
            fail(f'PXE next-server selected wrong subnet address: {selected}')
        try:
            ns['_interface_ipv4']('lan0')
        except RuntimeError as exc:
            if 'ambiguous' not in str(exc):
                raise
        else:
            fail('ambiguous PXE interface addresses were accepted')
    finally:
        ns['run'] = original_run

    storage, early = ns['_ubuntu_storage']({'storage_layout': 'direct'})
    if storage != {'layout': {'name': 'direct'}} or not early or 'exit 42' not in early[0]:
        fail('Ubuntu automatic storage no longer blocks ambiguous multi-disk installs')
    storage, early = ns['_ubuntu_storage']({'storage_layout': 'lvm', 'disk_match': {'serial': 'SAFE-*'}})
    if storage.get('layout', {}).get('match', {}).get('serial') != 'SAFE-*' or early:
        fail('Ubuntu explicit disk_match was not preserved deterministically')
    try:
        ns['_ubuntu_storage']({'disk_match': {'unsupported': 'x'}})
    except RuntimeError:
        pass
    else:
        fail('Ubuntu unsupported disk_match key was accepted')

    target = Path(tempfile.mkdtemp(prefix='srvcc-pxe-win-contract.'))
    base_called = {'count': 0}

    def fake_windows(profile, config, output, server, cred):
        base_called['count'] += 1
        output.mkdir(parents=True, exist_ok=True)
        output.joinpath('startnet.cmd').write_text(
            '@echo off\r\n'
            'diskpart /s %DiskScript%\r\n'
            'if errorlevel 1 goto failed\r\n'
            'dism /Apply-Image /ImageFile:Z:\\images\\7\\install.wim /Index:2 /ApplyDir:W:\\\r\n'
            'if errorlevel 1 goto failed\r\n',
            encoding='utf-8',
        )

    ns['_publish_windows_v14'] = fake_windows
    win_profile = {
        'id': 42,
        'image_id': 7,
        'windows_edition': 'Windows 11 Pro',
        'metadata': {
            'install_image': 'install.wim',
            'editions': [
                {'index': 3, 'name': 'Windows 11 Pro N'},
                {'index': 2, 'name': 'Windows 11 Pro'},
            ],
        },
    }
    ns['publish_windows'](win_profile, {}, target, '192.168.10.1', {'username': 'u', 'password': 'p'})
    generated = target.joinpath('startnet.cmd').read_text(encoding='utf-8')
    if base_called['count'] != 1:
        fail('Windows generator wrapper did not invoke the validated base generator exactly once')
    info = generated.find('dism /Get-WimInfo /WimFile:Z:\\images\\7\\install.wim /Index:2')
    erase = generated.find('diskpart /s %DiskScript%')
    apply = generated.find('/CheckIntegrity /Verify')
    if min(info, erase, apply) < 0 or info > erase:
        fail('Windows WIM/index validation is not performed before disk erase')

    bad = dict(win_profile)
    bad['windows_edition'] = 'Windows 11 Does Not Exist'
    base_called['count'] = 0
    try:
        ns['publish_windows'](bad, {}, target, '192.168.10.1', {'username': 'u', 'password': 'p'})
    except RuntimeError as exc:
        if 'not found exactly' not in str(exc):
            raise
    else:
        fail('unknown Windows edition silently fell back to another image index')
    if base_called['count']:
        fail('base Windows generator ran after edition validation failure')

    linux_target = Path(tempfile.mkdtemp(prefix='srvcc-pxe-linux-contract.'))

    def fake_linux(profile, config, output, server):
        output.mkdir(parents=True, exist_ok=True)
        output.joinpath('preseed.cfg').write_text('d-i netcfg/get_hostname string test\n', encoding='utf-8')
        output.joinpath('boot.ipxe').write_text(
            '#!ipxe\n'
            'kernel http://${next-server}/pxe/files/images/9/vmlinuz\n'
            'initrd http://${next-server}/pxe/files/images/9/initrd\n'
            'imgfetch --name srv-consume http://${next-server}/pxe/consume/9/token?mac=${net0/mac} || goto denied\n'
            'boot || goto denied\n',
            encoding='utf-8',
        )

    ns['_publish_linux_v14'] = fake_linux
    linux_profile = {'id': 9, 'image_id': 9, 'config': {'boot_token': 'token'}}
    ns['publish_linux'](linux_profile, {}, linux_target, '192.168.10.1')
    linux_boot = linux_target.joinpath('boot.ipxe').read_text(encoding='utf-8')
    guard = linux_boot.find('shim http://${next-server}/pxe/profile/9/token/secure-boot-shim-not-available.efi')
    consume = linux_boot.find('imgfetch --name srv-consume')
    if guard < 0 or consume < 0 or guard > consume:
        fail('Linux Secure Boot guard does not fail before one-time authorization consume')
    preseed = linux_target.joinpath('preseed.cfg').read_text(encoding='utf-8')
    if 'd-i passwd/root-login boolean false' not in preseed:
        fail('Debian preseed can still pause for root-account configuration')


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
    require(core, "PXE_ENTRY = Path('/srv/pxe/media/boot/entry.ipxe')", "'needs_upgrade': bool(pxe_installed and not pxe_managed)")
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

    require(core, 'MANAGED_DHCP_OPTION_CODES = {3, 6, 60, 66, 67, 93, 175}', 'def _validate_extra_dhcp_option(')
    add_option = effective_function(core, 'def add_dhcp_option(')
    update_option = effective_function(core, 'def update_dhcp_option(')
    require(add_option, '_validate_extra_dhcp_option')
    require(update_option, '_validate_extra_dhcp_option')

    dhcp = effective_function(agent, 'def apply_dhcp() -> str:')
    require(
        dhcp,
        '_pxe_runtime_active()',
        '_http_boot_assets_ready()',
        "_interface_ipv4(str(c['interface']), str(c['network']), str(c['netmask']))",
        'dhcp-match=set:ipxe,175',
        'dhcp-userclass=set:ipxe,iPXE',
        'dhcp-vendorclass=set:httpclient,HTTPClient',
        'option:client-arch,0',
        'option:client-arch,6',
        'option:client-arch,7',
        'option:client-arch,9',
        'option:client-arch,10',
        'option:client-arch,11',
        'option:client-arch,15',
        'option:client-arch,16',
        'option:client-arch,17',
        'option:client-arch,18',
        'option:client-arch,19',
        'option:client-arch,20',
        'tag:pxe-bios,undionly.kpxe',
        'tag:pxe-efi32,i386/snponly.efi',
        'tag:pxe-efi64,x86_64-sb/snponly-shim.efi',
        'tag:pxe-arm32,arm32/snponly.efi',
        'tag:pxe-arm64,arm64-sb/snponly-shim.efi',
        'tag:pxe-noarch,undionly.kpxe',
        'tag:ipxe,http://',
        "('pxe-http-efi32', 'http-efi32', 'httpboot/i386/snponly.efi')",
        "('pxe-http-efi64', 'http-efi64', 'httpboot/x86_64-sb/snponly-shim.efi')",
        "('pxe-http-arm32', 'http-arm32', 'httpboot/arm32/snponly.efi')",
        "('pxe-http-arm64', 'http-arm64', 'httpboot/arm64-sb/snponly-shim.efi')",
        "('pxe-http-bios', 'http-bios', 'httpboot/bios/undionly.kpxe')",
        'dhcp-option=tag:{selected},60,HTTPClient',
    )
    if "('pxe-http-ebc'" in dhcp:
        fail('HTTP EBC is advertised even though no architecture-safe EBC iPXE NBP is shipped')
    if "{c['gateway']}" in '\n'.join(line for line in dhcp.splitlines() if 'dhcp-boot=' in line):
        fail('effective PXE next-server is still derived from gateway instead of interface address')

    install = effective_function(agent, 'def install_pxe() -> str:')
    require(install, '_install_pxe_v14()', '_publish_http_boot_assets()', 'native UEFI HTTP Boot assets published')
    http_publish = effective_function(agent, 'def _publish_http_boot_assets(')
    require(
        http_publish,
        "'bios/undionly.kpxe'",
        "'i386/snponly.efi'",
        "'x86_64-sb/snponly-shim.efi'",
        "'arm32/snponly.efi'",
        "'arm64-sb/snponly-shim.efi'",
        "PXE_MEDIA / 'boot/entry.ipxe'",
        '_pxe_autoexec()',
    )

    remove = effective_function(agent, 'def remove_pxe() -> str:')
    require(remove, "disable', '--now', 'tftpd-hpa.service", 'apply_dhcp()', 'DHCP boot advertisement disabled')

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

    software = effective_function(agent, 'def _software_commands(')
    require(
        software,
        'PXE software package is missing',
        'outside managed media root',
        'unsupported PXE software package type',
        'if "%SRV_RC%"=="3010" set "SRV_REBOOT=1"',
        'goto setup_failed',
    )
    require(
        agent,
        'install_disk_number',
        'install_disk_serial',
        "Get-Disk ^| Where-Object",
        'if not defined InstallDisk goto disk_failed',
        'diskpart-selected.txt',
        'Cannot select exactly one Windows installation disk',
        ':setup_failed',
        'if errorlevel 1 goto setup_failed',
        'Add-Computer -DomainName',
    )

    windows = effective_function(agent, 'def publish_windows(')
    require(
        windows,
        '_publish_windows_v14',
        "casefold() == requested.casefold()",
        'not found exactly',
        'dism /Get-WimInfo',
        'diskpart /s %DiskScript%',
        '/CheckIntegrity /Verify',
    )

    require(
        agent,
        'def _ubuntu_storage(',
        "storage_layout must be direct or lvm",
        'Ubuntu PXE disk_match must be a non-empty object',
        'SRV-PXE-multiple-install-disks',
        "'error-commands'",
        'd-i partman/early_command string',
        'list-devices disk',
        'd-i mirror/http/hostname string',
        'd-i grub-installer/bootdev string',
        'priority=critical interface=auto hostname=',
    )

    linux = effective_function(agent, 'def publish_linux(')
    require(
        linux,
        '_publish_linux_v14',
        'd-i passwd/root-login boolean false',
        'secure-boot-shim-not-available.efi',
        'imgfetch --name srv-consume',
    )

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

    exercise_agent_runtime(agent)

    print(
        'PXE CONTRACT PASS: classic PXE/TFTP + UEFI HTTP Boot; BIOS + UEFI IA32/x64/ARM32/ARM64; '
        'x64/ARM64 Secure Boot; firmware/image gate; subnet-bound next-server; mutually-exclusive option93; '
        'Windows exact-edition+WIM+disk+postinstall safety; Linux disk/mirror/pre-consume safety; '
        'deny-by-default; pinned-assets'
    )
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
