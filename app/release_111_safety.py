from __future__ import annotations

from flask import jsonify, request

import database


def register(app, main):
    previous = app.view_functions.get('samba_provision_111')
    if not previous:
        return

    def samba_provision_guarded_111():
        rc, out, _ = main._run(
            ['systemctl', 'is-active', 'control-center-samba-apply.service'],
            3,
        )
        worker_state = (out or '').strip().lower()
        if worker_state in {'activating', 'active', 'reloading'}:
            return jsonify(
                ok=False,
                error='Создание Samba AD-DC уже выполняется root-worker. Дождитесь итогового статуса в колокольчике.',
                worker_state=worker_state,
            ), 409

        response = previous()
        try:
            status_code = response[1] if isinstance(response, tuple) and len(response) > 1 else getattr(response, 'status_code', 200)
            if request.method == 'POST' and int(status_code) == 202:
                body = request.get_json(silent=True) or {}
                public = {
                    'realm': str(body.get('realm') or '')[:253],
                    'netbios_domain': str(body.get('netbios_domain') or '')[:15],
                    'network_role': str(body.get('network_role') or '')[:8],
                    'dns_forwarder': str(body.get('dns_forwarder') or '')[:64],
                }
                database.audit(
                    'samba-ad-dc.provision.requested',
                    public.get('realm') or 'new-domain',
                    'queued',
                    request.remote_addr,
                    public,
                )
        except Exception:
            pass
        return response

    app.view_functions['samba_provision_111'] = samba_provision_guarded_111
