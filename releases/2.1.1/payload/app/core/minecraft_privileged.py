from __future__ import annotations

import json
import os
from pathlib import Path
import time
import uuid

ACTION_DIR = Path('/var/lib/srv-control/minecraft-actions')
RESULT_DIR = Path('/var/lib/srv-control/system-results')


def _atomic_request(path: Path, payload: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.parent / f'.{path.name}.{uuid.uuid4().hex}.tmp'
    temporary.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    os.chmod(temporary, 0o640)
    os.replace(temporary, path)


def run_helper(kind: str, args: list[str], *, payload: dict | None = None, timeout: int = 90) -> dict:
    if kind not in {'control', 'players', 'worlds', 'restore', 'live'}:
        raise RuntimeError('unsupported Minecraft helper kind')
    clean_args: list[str] = []
    for value in args:
        value = str(value)
        if len(value) > 512 or any(ch in value for ch in ('\x00', '\r', '\n')):
            raise RuntimeError('invalid Minecraft helper argument')
        clean_args.append(value)
    stdin_text = json.dumps(payload, ensure_ascii=False) if payload is not None else ''
    if len(stdin_text.encode('utf-8')) > 1024 * 1024:
        raise RuntimeError('Minecraft helper request is too large')

    request_id = uuid.uuid4().hex
    request = {
        'schema_version': 4,
        'request_id': request_id,
        'action': 'minecraft-legacy-helper',
        'actor': 'control-center-web',
        'client_ip': None,
        'payload': {
            'kind': kind,
            'args': clean_args,
            'stdin': stdin_text,
            'timeout': max(5, min(int(timeout), 1800)),
        },
    }
    result_path = RESULT_DIR / f'{request_id}.json'
    _atomic_request(ACTION_DIR / f'{request_id}.json', request)

    deadline = time.monotonic() + max(5, min(int(timeout) + 10, 1810))
    while time.monotonic() < deadline:
        try:
            result = json.loads(result_path.read_text(encoding='utf-8'))
        except FileNotFoundError:
            time.sleep(0.05)
            continue
        except Exception as exc:
            raise RuntimeError(f'invalid Minecraft privileged-agent result: {exc}') from exc
        if not isinstance(result, dict) or result.get('request_id') != request_id:
            raise RuntimeError('Minecraft privileged-agent result does not match request')
        detail = str(result.get('detail') or '')
        try:
            decoded = json.loads(detail) if detail else {}
        except Exception:
            decoded = {}
        if result.get('result') != 'success':
            message = decoded.get('error') if isinstance(decoded, dict) else None
            raise RuntimeError(str(message or detail or 'Minecraft privileged operation failed'))
        if not isinstance(decoded, dict) or decoded.get('ok') is not True:
            raise RuntimeError(detail or 'invalid Minecraft privileged helper response')
        return decoded
    raise TimeoutError(f'Minecraft privileged operation timed out after {timeout}s')
