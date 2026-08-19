from __future__ import annotations

import json
import time
from pathlib import Path

from flask import jsonify

import database
import release_110

STATUS_SOURCES = [
    ('dns', 'DNS', Path('/var/lib/control-center-system/dns-status.json')),
    ('storage', 'Сетевое хранилище', Path('/var/lib/control-center-system/storage-status.json')),
    ('dhcp-reservations', 'DHCP · IP-бронирования', Path('/var/lib/control-center-system/dhcp-reservations-status.json')),
]
CLEANUP_DIR = Path('/var/lib/control-center-system/cleanup-audits')


def _read(path):
    try:
        value = json.loads(path.read_text())
        return value if isinstance(value, dict) else {}
    except Exception:
        return {}


def _severity(state):
    state = str(state or '').lower()
    if state in {'error', 'failed', 'rollback', 'rejected'}:
        return 'error'
    if state in {'active', 'applied', 'removed', 'running', 'healthy'}:
        return 'ok'
    return 'info'


def _status_event(source, title, path):
    s = _read(path)
    if not s:
        return None
    state = str(s.get('state') or 'unknown')
    ts = int(s.get('timestamp') or 0)
    message = str(s.get('message') or state)
    detail = str(s.get('detail') or '').strip()
    if detail:
        message += '\n' + detail
    event_id = f'{source}-{state}-{ts or int(time.time())}'
    return release_110._notification_item(event_id, source, title, _severity(state), state, message, ts)


def _cleanup_events(limit=10):
    rows = []
    try:
        files = sorted(CLEANUP_DIR.glob('*.json'), key=lambda p: p.stat().st_mtime, reverse=True)[:limit]
    except Exception:
        return rows
    for path in files:
        data = _read(path)
        if not data:
            continue
        service = str(data.get('service') or 'service')
        clean = bool(data.get('clean'))
        ts = int(data.get('timestamp') or path.stat().st_mtime)
        title = {'domain': 'Домен · cleanup-audit', 'dns': 'DNS · cleanup-audit', 'storage': 'Сетевое хранилище · cleanup-audit'}.get(service, f'{service} · cleanup-audit')
        failed = [k for k, v in (data.get('checks') or {}).items() if not v]
        message = 'Удаление проверено: служебных артефактов не обнаружено.' if clean else 'Cleanup-audit обнаружил остаточные артефакты: ' + ', '.join(failed)
        rows.append(release_110._notification_item(f'cleanup-{service}-{ts}', f'cleanup-{service}', title, 'ok' if clean else 'error', 'clean' if clean else 'dirty', message, ts))
    return rows


def register(app, main):
    previous = app.view_functions.get('notifications')
    if not previous:
        return

    def notifications_111_persisted():
        response = previous()
        try:
            payload = response.get_json() or {}
            current = list(payload.get('items') or [])
        except Exception:
            return response

        for source, title, path in STATUS_SOURCES:
            item = _status_event(source, title, path)
            if item:
                current.append(item)
        current.extend(_cleanup_events())

        # Deduplicate the live aggregation before PostgreSQL sync. Distinct
        # lifecycle phases have distinct IDs/timestamps, so start/success/error
        # remain separate historical bell events once observed by the UI poller.
        dedup = {}
        for item in current:
            key = str(item.get('id') or '')
            if key:
                dedup[key] = item
        current = sorted(dedup.values(), key=lambda x: int(x.get('timestamp') or 0), reverse=True)[:250]

        try:
            database.sync_notifications(current)
            current_samba_ids = {
                str(item.get('id') or '')
                for item in current
                if item.get('source') == 'samba'
            }
            rows = database.list_notifications(350)
            rows = [
                item for item in rows
                if item.get('source') != 'samba'
                or str(item.get('id') or '') in current_samba_ids
            ][:250]
            return jsonify(
                items=rows,
                count=len(rows),
                unread=sum(1 for item in rows if not item.get('read')),
                generated_at=int(time.time()),
                persistence='postgresql',
            )
        except Exception:
            # DB outage must not hide operational failures.
            return jsonify(
                items=current,
                count=len(current),
                unread=sum(1 for item in current if not item.get('read')),
                generated_at=int(time.time()),
                persistence='degraded',
            )

    app.view_functions['notifications'] = notifications_111_persisted
