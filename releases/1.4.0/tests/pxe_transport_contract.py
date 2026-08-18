#!/usr/bin/env python3
from pathlib import Path
import tempfile
import shutil

ROOT = Path(__file__).resolve().parents[1]
PARTS = ROOT / 'system/srv-control-release14-agent.parts'
ORDER = [f'{n:02d}.part' for n in range(12)] + ['11a.inc', '12.part']
AGENT = ''.join((PARTS / name).read_text(encoding='utf-8') for name in ORDER)
compile(AGENT, '<release14-agent-transport>', 'exec')


def function(name: str) -> str:
    signature = f'def {name}('
    start = AGENT.rfind(signature)
    if start < 0:
        raise AssertionError(f'missing effective {name}')
    end = AGENT.find('\ndef ', start + len(signature))
    return AGENT[start:] if end < 0 else AGENT[start:end]


autoexec = function('_pxe_autoexec')
assert '${netX/ip}' in autoexec, autoexec
assert '${netX/mac}' in autoexec, autoexec
assert '${net0/ip}' not in autoexec, autoexec
assert '${net0/mac}' not in autoexec, autoexec
assert 'platform=${platform}' in autoexec
assert 'buildarch=${buildarch}' in autoexec
assert 'ifstat' in autoexec and 'route' in autoexec

# RFC/IANA architecture 9 is EFI Byte Code, not x64 UEFI. It is recognized
# but deliberately receives no incompatible x86_64 NBP.
dhcp = function('apply_dhcp')
assert 'dhcp-match=set:efi64,option:client-arch,7' in dhcp
assert 'dhcp-match=set:efibc,option:client-arch,9' in dhcp
assert 'dhcp-match=set:efi64,option:client-arch,9' not in dhcp
assert 'tag:!efibc' in dhcp
assert 'dhcp-boot=tag:pxe-efibc' not in dhcp

# The initial boot authorization and the later one-time consume must identify
# the same active iPXE NIC. Exercise the exact include used by apply.sh on both
# Windows and Linux-shaped generated scripts.
ns = {'__name__': 'srvcc_transport_contract'}
exec(compile(AGENT, '<release14-agent-transport-runtime>', 'exec'), ns)
rewrite = ns['_rewrite_profile_consume_to_active_nic']
for kind in ('windows', 'linux'):
    target = Path(tempfile.mkdtemp(prefix=f'srvcc-{kind}-transport.'))
    try:
        boot = target / 'boot.ipxe'
        boot.write_text(
            '#!ipxe\n'
            'imgfetch --name srv-consume http://${next-server}/pxe/consume/42/token?mac=${net0/mac} || goto denied\n',
            encoding='utf-8',
        )
        rewrite(target)
        value = boot.read_text(encoding='utf-8')
        assert '${netX/mac}' in value, value
        assert '${net0/mac}' not in value, value
    finally:
        shutil.rmtree(target, ignore_errors=True)

include = (PARTS / '11a.inc').read_text(encoding='utf-8')
assert '_publish_windows_active_nic = publish_windows' in include
assert '_publish_linux_active_nic = publish_linux' in include
assert "value.replace('${net0/mac}', '${netX/mac}')" in include

print('PXE TRANSPORT CONTRACT PASS: active netX interface in chainload + Windows/Linux consume; RFC-correct EFI BC fail-safe')
