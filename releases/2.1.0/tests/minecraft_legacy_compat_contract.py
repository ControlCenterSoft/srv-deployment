#!/usr/bin/env python3
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
APPLY = (ROOT / 'apply-2.0.0.sh').read_text(encoding='utf-8')
ROLLBACK = (ROOT / 'rollback-2.0.0.sh').read_text(encoding='utf-8')
REPAIR = (ROOT / 'system/srv-control-minecraft-repair').read_text(encoding='utf-8')
LEGACY = (ROOT / 'system/srv-control-minecraft-legacy').read_text(encoding='utf-8')
ROUTER = (ROOT / 'payload/app/routers/minecraft_legacy.py').read_text(encoding='utf-8')

# The regression observed on the real 1.3.8 server: bedrock_server was already
# listening on UDP/19132, but historical /usr/local/sbin helpers did not exist.
# 2.0 must install its compatibility backend before health-first repair.
assert 'srv-control-minecraft-legacy srv-control-pxe-probe' in APPLY
assert 'python3 -m py_compile "$SYSTEM/srv-control-minecraft-legacy"' in APPLY
for helper in (
    'srv-control-minecraft',
    'srv-control-minecraft-worlds',
    'srv-control-minecraft-players',
    'srv-control-minecraft-restore',
    'srv-control-minecraft-live',
):
    assert f'/usr/local/sbin/{helper}' in APPLY, helper
    assert f'/usr/local/sbin/{helper}' in ROLLBACK, helper
    assert f'"{helper.removeprefix("srv-control-minecraft-")}"' in ROUTER or helper == 'srv-control-minecraft'

assert '/etc/sudoers.d/srv-control-minecraft-legacy' in APPLY
assert '/etc/sudoers.d/srv-control-minecraft-legacy' in ROLLBACK
assert 'visudo -cf "$sudoers_tmp"' in APPLY
assert 'srv-control ALL=(root) NOPASSWD:' in APPLY

# Compatibility health discovers the live process and runtime rather than
# declaring the server down because a historical helper was never installed.
for anchor in (
    "'bedrock_server'",
    "Path(os.readlink(f'/proc/{pid}/cwd')).resolve()",
    "unit_for_pid(pid)",
    "'port_listening': udp_listening(port)",
    "'world_exists': world_exists",
    "'healthy': bool(active and udp_listening(port) and level and world_exists)",
):
    assert anchor in LEGACY, anchor

# Destructive actions remain gated by safety backup and a discoverable service.
assert "safety = backup('pre-update')" in LEGACY
assert "safe Bedrock update requires a discoverable systemd service" in LEGACY
assert "backup('pre-world-switch')" in LEGACY
assert "backup('pre-world-delete')" in LEGACY
assert "safety=backup('pre-restore')" in LEGACY
assert 'cannot replace world because safety backup failed' in REPAIR
assert 'ControlCenter-Recovery-' in REPAIR

# Apply no longer requires pre-existing helpers; it installs them first and then
# invokes the normal repair command.
assert 'proven Minecraft legacy helpers are missing' not in APPLY
assert 'srv-control-minecraft-repair repair --replace-world-on-failure' in APPLY

print('MINECRAFT LEGACY COMPAT CONTRACT PASS')
