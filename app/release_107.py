import os
import socket
import time
from pathlib import Path

from flask import jsonify, request

import database

VERSION = '1.0.7'
BUILD = '20260818.2'
WEB_PENDING = Path('/var/lib/control-center/web-pending.json')
WEB_STATUS = Path('/var/lib/control-center-system/web-status.json')
WEB_CONFIG = Path('/var/lib/control-center-system/web-config.json')


def _runtime_port():
    try:
        port = int(os.getenv('CONTROL_CENTER_PORT', '8080'))
        return port if 1024 <= port <= 65535 else 8080
    except Exception:
        return 8080


def _port_available(port):
    if port == _runtime_port():
        return True, ''
    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    try:
        s.bind(('0.0.0.0', port))
        return True, ''
    except OSError as exc:
        return False, str(exc)
    finally:
        s.close()


def _db_health():
    try:
        return database.health(), None
    except Exception as exc:
        return None, str(exc)


def _sync_runtime(main):
    try:
        lic = main._license_info()
        database.upsert_local_node(
            edition=lic.get('edition', 'Home'),
            version=main.APP_VERSION,
            build=main.APP_BUILD,
            endpoint=f'http://{socket.gethostname()}:{_runtime_port()}',
        )
    except Exception:
        pass
    try:
        cfg, _, source = main._effective_network_config()
        database.sync_service_config('network', cfg, source)
    except Exception:
        pass
    try:
        cfg, source = main._effective_dhcp_config()
        database.sync_service_config('dhcp', cfg, source)
        state = main._read_json(main.DHCP_STATE, {})
        database.upsert_module('dhcp', bool(state.get('installed')), 'installed' if state.get('installed') else 'available', metadata=state)
    except Exception:
        pass


def _extra_notifications(main):
    item = main._status_notification('web', 'Web-панель', WEB_STATUS)
    return [item] if item else []


def register(app, main):
    main.APP_VERSION = VERSION
    main.APP_BUILD = BUILD

    try:
        database.bootstrap_from_runtime(main)
    except Exception:
        pass

    def health_107():
        _, db_error = _db_health()
        return jsonify(
            status='ok',
            product='Control Center',
            version=main.APP_VERSION,
            build=main.APP_BUILD,
            edition=main._license_info()['edition'],
            database='degraded' if db_error else 'ok',
        )

    def notifications_107():
        raw = main._notifications() + _extra_notifications(main)
        try:
            _sync_runtime(main)
            database.sync_notifications(raw)
            items = database.list_notifications(150)
            return jsonify(
                items=items,
                count=len(items),
                unread=sum(1 for x in items if not x.get('read')),
                generated_at=int(time.time()),
                persistence='postgresql',
            )
        except Exception:
            for item in raw:
                item['read'] = False
            return jsonify(items=raw, count=len(raw), unread=len(raw), generated_at=int(time.time()), persistence='degraded')

    def mark_notifications_107():
        _, db_error = _db_health()
        if db_error:
            return jsonify(ok=False, error=f'PostgreSQL недоступен: {db_error}'), 503
        body = request.get_json(silent=True) or {}
        try:
            if body.get('all') is True:
                changed = database.mark_notifications(None)
            else:
                ids = body.get('ids')
                if not isinstance(ids, list):
                    return jsonify(ok=False, error='Передайте ids или all=true'), 400
                changed = database.mark_notifications(ids)
            return jsonify(ok=True, changed=changed)
        except Exception as exc:
            return jsonify(ok=False, error=str(exc)), 500

    def database_status_107():
        try:
            _sync_runtime(main)
            info = database.health()
            info['mode'] = database.get_setting('database.mode', 'local')
            info['cluster_enabled'] = bool(database.get_setting('cluster.enabled', False))
            info['nodes'] = database.cluster_nodes()
            return jsonify(info)
        except Exception as exc:
            return jsonify(ok=False, error=str(exc), cluster_ready=True), 503

    def web_settings_107():
        runtime = _runtime_port()
        status = main._read_json(WEB_STATUS, {})
        config = main._read_json(WEB_CONFIG, {})
        _, db_error = _db_health()
        if db_error:
            if request.method == 'POST':
                return jsonify(ok=False, error=f'PostgreSQL недоступен: {db_error}'), 503
            fallback_port = config.get('port', runtime)
            try:
                fallback_port = int(fallback_port)
            except Exception:
                fallback_port = runtime
            return jsonify(
                port=fallback_port,
                runtime_port=runtime,
                pending_port=None,
                status=status,
                config=config,
                min_port=1024,
                max_port=65535,
                persistence='degraded',
                database_error=db_error,
            )
        current = database.get_setting('web.port', runtime)
        try:
            current = int(current)
        except Exception:
            current = runtime
        if request.method == 'GET':
            return jsonify(
                port=current,
                runtime_port=runtime,
                pending_port=database.get_setting('web.port.requested', None),
                status=status,
                config=config,
                min_port=1024,
                max_port=65535,
                persistence='postgresql',
            )
        body = request.get_json(silent=True) or {}
        try:
            port = int(body.get('port'))
        except Exception:
            return jsonify(ok=False, error='Порт должен быть целым числом'), 400
        if port < 1024 or port > 65535:
            return jsonify(ok=False, error='Порт Web UI должен быть от 1024 до 65535'), 400
        if port == runtime:
            database.set_setting('web.port', port)
            database.set_setting('web.port.requested', None)
            return jsonify(ok=True, status='unchanged', port=port, message=f'Web UI уже работает на порту {port}')
        available, reason = _port_available(port)
        if not available:
            return jsonify(ok=False, error=f'Порт {port} уже занят или недоступен: {reason}'), 409
        job_id = f'web-port-{int(time.time())}'
        database.set_setting('web.port.requested', port)
        database.upsert_job(job_id, 'web-port-change', 'queued', payload={'port': port, 'previous_port': runtime})
        main._write_json(WEB_PENDING, {
            'port': port,
            'previous_port': runtime,
            'job_id': job_id,
            'requested_at': int(time.time()),
        })
        return jsonify(
            ok=True,
            status='pending',
            port=port,
            previous_port=runtime,
            job_id=job_id,
            message=f'Порт {port} передан на применение. Web-панель будет перезапущена.',
        ), 202

    def update_settings_107():
        fallback = main._normalized_update_settings()
        db_ok = True
        try:
            settings = database.get_setting('control_center.update', fallback)
        except Exception as exc:
            db_ok = False
            settings = fallback
            if request.method == 'POST':
                return jsonify(error=f'PostgreSQL недоступен: {exc}'), 503
        if request.method == 'POST':
            body = request.get_json(silent=True) or {}
            automatic = body.get('automatic_updates')
            if not isinstance(automatic, bool):
                return jsonify(error='automatic_updates must be boolean'), 400
            try:
                interval = int(body.get('interval_minutes'))
            except Exception:
                return jsonify(error='Интервал должен быть целым числом минут'), 400
            if interval < 5 or interval > 10080:
                return jsonify(error='Интервал должен быть от 5 до 10080 минут'), 400
            settings = {'automatic_updates': automatic, 'interval_minutes': interval, 'channel': 'production'}
            database.set_setting('control_center.update', settings)
            main._write_json(main.SETTINGS_FILE, settings)
        return jsonify(
            settings=settings,
            status=main._read_json(main.STATUS_FILE, {}),
            current_version=main.APP_VERSION,
            current_build=main.APP_BUILD,
            persistence='postgresql' if db_ok else 'compatibility-json',
        )

    def os_update_settings_107():
        fallback = main._normalized_os_update_settings()
        db_ok = True
        try:
            settings = database.get_setting('os.update', fallback)
        except Exception as exc:
            db_ok = False
            settings = fallback
            if request.method == 'POST':
                return jsonify(error=f'PostgreSQL недоступен: {exc}'), 503
        if request.method == 'POST':
            body = request.get_json(silent=True) or {}
            automatic = body.get('automatic_updates')
            if not isinstance(automatic, bool):
                return jsonify(error='automatic_updates must be boolean'), 400
            try:
                interval = int(body.get('interval_minutes'))
            except Exception:
                return jsonify(error='Интервал должен быть целым числом минут'), 400
            if interval < 60 or interval > 10080:
                return jsonify(error='Интервал обновления ОС: от 60 до 10080 минут'), 400
            settings = {'automatic_updates': automatic, 'interval_minutes': interval}
            database.set_setting('os.update', settings)
            main._write_json(main.OS_UPDATE_SETTINGS, settings)
        return jsonify(settings=settings, status=main._read_json(main.OS_UPDATE_STATUS, {}), persistence='postgresql' if db_ok else 'compatibility-json')

    app.view_functions['health'] = health_107
    app.view_functions['notifications'] = notifications_107
    app.view_functions['update_settings'] = update_settings_107
    app.view_functions['os_update_settings'] = os_update_settings_107
    app.add_url_rule('/api/notifications/read', 'notifications_read_107', mark_notifications_107, methods=['POST'])
    app.add_url_rule('/api/database/status', 'database_status_107', database_status_107, methods=['GET'])
    app.add_url_rule('/api/settings/web', 'web_settings_107', web_settings_107, methods=['GET', 'POST'])

    @app.after_request
    def audit_state_changes_107(response):
        if request.method in {'POST', 'PUT', 'PATCH', 'DELETE'} and request.path.startswith('/api/'):
            try:
                database.audit(
                    action=f'{request.method} {request.path}',
                    resource=request.endpoint or request.path,
                    status=str(response.status_code),
                    remote_addr=request.remote_addr,
                    details={'content_length': request.content_length or 0},
                )
            except Exception:
                pass
        return response
