#!/usr/bin/env python3
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PARTS = ROOT / 'system/srv-control-release14-agent.parts'
AGENT = ''.join((PARTS / f'{n:02d}.part').read_text(encoding='utf-8') for n in range(13))


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

# RFC/IANA architecture 9 is EFI Byte Code, not x64 UEFI. This test is
# intentionally fail-closed until the DHCP generator maps 9 to an unsupported
# EBC tag instead of serving the x86_64 NBP.
dhcp = function('apply_dhcp')
assert 'dhcp-match=set:efi64,option:client-arch,7' in dhcp
assert 'dhcp-match=set:efibc,option:client-arch,9' in dhcp
assert 'dhcp-match=set:efi64,option:client-arch,9' not in dhcp
assert 'tag:!efibc' in dhcp
assert 'dhcp-boot=tag:pxe-efibc' not in dhcp

print('PXE TRANSPORT CONTRACT PASS: active netX interface + RFC-correct EFI BC fail-safe')
