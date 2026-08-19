from __future__ import annotations

from pathlib import Path

from flask import Response, jsonify, request

import database


def register(app, main):
    previous_web = app.view_functions.get('web_settings_107')

    def web_settings_110_reconciled():
        response = previous_web()
        if request.method != 'GET':
            return response
        try:
            payload = response.get_json() or {}
        except Exception:
            return response
        if not isinstance(payload, dict) or 'port' not in payload:
            return response
        try:
            desired = {
                'port': int(payload['port']),
                'ssl_enabled': bool(payload.get('ssl_enabled', False)),
                'standard_port': bool(payload.get('standard_port', False)),
            }
            current = {
                'port': int(database.get_setting('web.port', desired['port'])),
                'ssl_enabled': bool(database.get_setting('web.ssl_enabled', desired['ssl_enabled'])),
                'standard_port': bool(database.get_setting('web.standard_port', desired['standard_port'])),
            }
            if current != desired:
                database.set_setting('web.port', desired['port'])
                database.set_setting('web.ssl_enabled', desired['ssl_enabled'])
                database.set_setting('web.standard_port', desired['standard_port'])
                database.set_setting('web.port.requested', None)
                database.set_setting('web.ssl.requested', None)
                database.set_setting('web.standard.requested', None)
            payload['database_synced'] = True
            payload['database_error'] = None
            payload['persistence'] = 'runtime-file+postgresql'
            return jsonify(payload)
        except Exception as exc:
            payload['database_synced'] = False
            payload['database_error'] = str(exc)
            payload['persistence'] = 'runtime-file'
            return jsonify(payload)

    if previous_web:
        app.view_functions['web_settings_107'] = web_settings_110_reconciled

    static_dir = Path(app.root_path) / 'static'

    def release_assets_110_fix():
        if request.method != 'GET':
            return None
        if request.path == '/static/app.js':
            try:
                payload = (
                    (static_dir / 'app.js').read_text()
                    + '\n\n' + (static_dir / 'release-108.js').read_text()
                    + '\n\n' + (static_dir / 'release-110.js').read_text()
                    + '\n\n' + (static_dir / 'release-110-fix.js').read_text()
                )
                return Response(payload, mimetype='application/javascript')
            except Exception:
                return None
        if request.path == '/static/app.css':
            try:
                payload = (
                    (static_dir / 'app.css').read_text()
                    + '\n\n' + (static_dir / 'release-108.css').read_text()
                    + '\n\n' + (static_dir / 'release-110.css').read_text()
                )
                return Response(payload, mimetype='text/css')
            except Exception:
                return None
        return None

    app.before_request_funcs.setdefault(None, []).insert(0, release_assets_110_fix)
