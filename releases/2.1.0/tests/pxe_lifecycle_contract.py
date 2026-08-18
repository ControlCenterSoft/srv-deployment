#!/usr/bin/env python3
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CORE = ''.join((ROOT / 'payload/app/core/release14.parts' / f'{n:02d}.part').read_text(encoding='utf-8') for n in range(8))
ROUTER = ''.join((ROOT / 'payload/app/routers/release14.parts' / f'{n:02d}.part').read_text(encoding='utf-8') for n in range(4))
UI = (ROOT / 'payload/static/js/pxe-1.4.js').read_text(encoding='utf-8')


def function(source: str, name: str) -> str:
    signature = f'def {name}('
    start = source.rfind(signature)
    if start < 0:
        raise AssertionError(f'missing effective {name}')
    end = source.find('\ndef ', start + len(signature))
    return source[start:] if end < 0 else source[start:end]


prepare = function(CORE, '_prepare_pxe_attempt')
for anchor in (
    "status == 'installing' and not emergency_retry",
    "emergency_retry and status != 'installing'",
    "'boot_token': secrets.token_urlsafe(32)",
    "'report_token': secrets.token_urlsafe(32)",
    "consumed_at=NULL",
    "status='publishing'",
):
    assert anchor in prepare, anchor

authorize = function(CORE, 'authorize_pxe_profile')
force = function(CORE, 'force_retry_pxe_profile')
assert '_prepare_pxe_attempt(profile_id, emergency_retry=False)' in authorize
assert '_prepare_pxe_attempt(profile_id, emergency_retry=True)' in force

report = function(CORE, 'report_pxe')
for anchor in (
    "str(row.get('status') or '') != 'installing'",
    "compare_digest(expected, str(token or ''))",
    "WHERE id=:id AND status='installing'",
):
    assert anchor in report, anchor

assert "@router.post('/api/v1/release14/pxe/profiles/{profile_id}/emergency-retry')" in ROUTER
assert 'confirm_previous_install_stopped' in ROUTER
assert 'force_retry_pxe_profile(profile_id)' in ROUTER
assert 'emergency-retry-after-interrupted-install' in ROUTER

for anchor in (
    'Аварийно разрешить повторно',
    'предыдущая установка на этом ПК уже остановлена или ПК выключен',
    'confirm_previous_install_stopped:true',
    'Старые токены аннулированы',
):
    assert anchor in UI, anchor

print('PXE LIFECYCLE CONTRACT PASS: per-attempt token rotation + stale-report rejection + explicit interrupted-install recovery')
