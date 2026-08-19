from __future__ import annotations

from flask import jsonify

import database


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

        # release_111 has already removed superseded readiness-only Samba events
        # from the live aggregation. Persist that live set without resetting
        # is_read on existing event IDs, then return server-side read state.
        try:
            database.sync_notifications(current)
            current_samba_ids = {
                str(item.get('id') or '')
                for item in current
                if item.get('source') == 'samba'
            }
            rows = database.list_notifications(300)
            rows = [
                item for item in rows
                if item.get('source') != 'samba'
                or str(item.get('id') or '') in current_samba_ids
            ][:200]
            return jsonify(
                items=rows,
                count=len(rows),
                unread=sum(1 for item in rows if not item.get('read')),
                generated_at=payload.get('generated_at'),
                persistence='postgresql',
            )
        except Exception:
            # A DB outage must not hide Samba lifecycle errors. The underlying
            # release_111 response remains the degraded source of truth.
            return response

    app.view_functions['notifications'] = notifications_111_persisted
