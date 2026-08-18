from __future__ import annotations

import hashlib
import json
import time
from pathlib import Path

from flask import Response, jsonify, request

import database

VERSION = '1.0.8'
BUILD = '20260819.1'
MARKET_EVENTS = Path('/var/lib/control-center-system/market-events.jsonl')
UPDATE_NOW = Path('/var/lib/control-center/update-now')


def _read_json(path, default=None):
    try:
        data = json.loads(Path(path).read_text())
        return data if isinstance(data, dict) else (default or {})
    except Exception:
        return default or {}


def _semver(value):
    try:
        parts = tuple(int(x) for x in str(value).split('.'))
        return parts if len(parts) == 3 else None
    except Exception:
        return None


def _update_state(main):
    remote = main._remote_release()
    current = main.APP_VERSION
    current_build = main.APP_BUILD
    available = False
    reason = 'up-to-date'
    if remote.get('available'):
        rv = _semver(remote.get('release'))
        cv = _semver(current)
        if rv and cv and rv > cv:
            available, reason = True, 'new-version'
        elif rv and cv and rv == cv and remote.get('build') and remote.get('build') != current_build:
            available, reason = True, 'new-build'
    return {
        'current_version': current,
        'current_build': current_build,
        'remote': remote,
        'update_available': available,
        'reason': reason,
    }


def _market_event_notifications():
    if not MARKET_EVENTS.exists():
        return []
    try:
        lines = MARKET_EVENTS.read_text(errors='replace').splitlines()[-200:]
    except Exception:
        return []
    items = []
    for line in lines:
        try:
            event = json.loads(line)
            if not isinstance(event, dict):
                continue
            timestamp = int(event.get('timestamp') or 0)
            state = str(event.get('state') or event.get('phase') or 'info').lower()
            service = str(event.get('service') or event.get('module') or 'Сервис')
            message = str(event.get('message') or '').strip()
            detail = str(event.get('detail') or '').strip()
            if detail and detail not in message:
                message = f'{message}\n{detail}' if message else detail
            raw_id = json.dumps({
                'module': event.get('module'), 'action': event.get('action'),
                'phase': event.get('phase'), 'timestamp': timestamp,
                'message': message,
            }, ensure_ascii=False, sort_keys=True)
            items.append({
                'id': hashlib.sha256(raw_id.encode()).hexdigest()[:20],
                'source': f"market-{event.get('module') or 'service'}",
                'title': f'{service} · Маркет',
                'state': state,
                'severity': 'error' if state in {'error', 'failed', 'failure'} else 'ok',
                'message': message or state,
                'timestamp': timestamp,
            })
        except Exception:
            continue
    return items


def _dhcp_market_status(main):
    now = int(time.time())
    pending = main._read_json(main.MARKET_PENDING, {})
    status = main._read_json(main.MARKET_STATUS, {})
    installed = main._dhcp_installed()
    rc, out, _ = main._run(['dpkg-query', '-W', '-f=${Status}', 'dnsmasq'], 3)
    package_installed = rc == 0 and 'install ok installed' in out
    service = main._dhcp_service_status()

    if pending.get('module') == 'dhcp':
        action = pending.get('action')
        return {
            'code': 'installing' if action == 'install' else 'removing',
            'label': 'Установка…' if action == 'install' else 'Удаление…',
            'detail': 'Операция поставлена в очередь и ожидает root worker.',
            'timestamp': int(pending.get('requested_at') or now),
        }

    if status.get('module') in (None, '', 'dhcp') and status.get('state') in {'installing', 'applying', 'removing'}:
        ts = int(status.get('timestamp') or 0)
        if not ts or now - ts <= 1800:
            action = status.get('action')
            return {
                'code': 'installing' if action != 'remove' else 'removing',
                'label': 'Установка…' if action != 'remove' else 'Удаление…',
                'detail': status.get('detail') or status.get('message') or 'Операция выполняется.',
                'timestamp': ts,
            }
        return {
            'code': 'error', 'label': 'Ошибка',
            'detail': 'Предыдущая операция не завершилась более 30 минут. Проверьте журнал Market worker.',
            'timestamp': ts,
        }

    if status.get('module') == 'dhcp' and status.get('state') == 'error':
        return {
            'code': 'error', 'label': 'Ошибка',
            'detail': status.get('detail') or status.get('message') or 'Операция DHCP завершилась ошибкой.',
            'timestamp': int(status.get('timestamp') or 0),
        }

    if installed and not package_installed:
        return {
            'code': 'error', 'label': 'Ошибка',
            'detail': 'Модуль DHCP зарегистрирован, но пакет dnsmasq отсутствует.',
            'timestamp': int(status.get('timestamp') or 0),
        }

    if installed and package_installed:
        if service.get('configured') and not service.get('running'):
            return {
                'code': 'error', 'label': 'Ошибка',
                'detail': f"DHCP настроен, но служба не работает: {service.get('active_state')}/{service.get('sub_state')}",
                'timestamp': int(service.get('state_changed') or status.get('timestamp') or 0),
            }
        detail = 'DHCP Server установлен и готов к настройке.'
        if service.get('configured') and service.get('running'):
            detail = 'DHCP Server установлен, настроен и служба работает.'
        return {
            'code': 'running', 'label': 'Работает', 'detail': detail,
            'timestamp': int(status.get('timestamp') or service.get('state_changed') or 0),
        }

    if package_installed and not installed:
        return {
            'code': 'error', 'label': 'Ошибка',
            'detail': 'Пакет dnsmasq обнаружен без регистрации модуля Control Center. Нажмите «Установить» для безопасной проверки/восстановления установки.',
            'timestamp': int(status.get('timestamp') or 0),
        }

    return {'code': 'available', 'label': 'Не установлен', 'detail': 'Сервис доступен для установки.', 'timestamp': 0}


def _market_payload(main):
    dhcp_status = _dhcp_market_status(main)
    installed = main._dhcp_installed()
    items = [
        {
            'id': 'dhcp', 'name': 'DHCP Server', 'description': 'DHCPv4 на базе dnsmasq',
            'state': 'installed' if installed else 'available', 'installable': True,
            'status': dhcp_status,
        },
        {
            'id': 'pxe', 'name': 'PXE Server', 'description': 'Сетевая установка ОС',
            'state': 'planned', 'installable': False,
            'status': {'code': 'planned', 'label': 'Запланировано', 'detail': 'Установка PXE Server будет доступна в одном из следующих релизов.', 'timestamp': 0},
        },
        {
            'id': 'samba', 'name': 'Samba', 'description': 'Файловые и доменные сервисы',
            'state': 'planned', 'installable': False,
            'status': {'code': 'planned', 'label': 'Запланировано', 'detail': 'Установка Samba будет доступна в одном из следующих релизов.', 'timestamp': 0},
        },
        {
            'id': 'adguard', 'name': 'AdGuard', 'description': 'DNS-фильтрация и сетевые сервисы',
            'state': 'planned', 'installable': False,
            'status': {'code': 'planned', 'label': 'Запланировано', 'detail': 'Установка AdGuard будет доступна в одном из следующих релизов.', 'timestamp': 0},
        },
    ]
    return {
        'items': items,
        'dhcp_installed': installed,
        'status': main._read_json(main.MARKET_STATUS, {}),
        'generated_at': int(time.time()),
    }


def register(app, main):
    main.APP_VERSION = VERSION
    main.APP_BUILD = BUILD

    try:
        lic = main._license_info()
        database.upsert_local_node(edition=lic.get('edition', 'Home'), version=VERSION, build=BUILD)
    except Exception:
        pass

    previous_notifications = app.view_functions.get('notifications')

    def market_108():
        return jsonify(_market_payload(main))

    def market_dhcp_108():
        body = request.get_json(silent=True) or {}
        action = str(body.get('action') or '').lower()
        if action not in {'install', 'remove'}:
            return jsonify(ok=False, error='action must be install or remove'), 400
        current = _dhcp_market_status(main)
        if current.get('code') in {'installing', 'removing'}:
            return jsonify(ok=False, error='Операция DHCP уже выполняется'), 409
        if action == 'remove' and not main._dhcp_installed():
            return jsonify(ok=False, error='DHCP Server не установлен Control Center'), 409
        main._write_json(main.MARKET_PENDING, {
            'module': 'dhcp', 'action': action,
            'requested_at': int(time.time()),
            'request_id': f'dhcp-{action}-{int(time.time() * 1000)}',
        })
        return jsonify(ok=True, status='pending', action=action, message='Операция передана Market worker'), 202

    def update_check_108():
        return jsonify(_update_state(main))

    def update_install_108():
        state = _update_state(main)
        if not state.get('remote', {}).get('available'):
            return jsonify(ok=False, error='Не удалось получить Production metadata'), 503
        if not state.get('update_available'):
            return jsonify(ok=False, error='Доступных обновлений Control Center нет'), 409
        remote = state['remote']
        main._write_json(UPDATE_NOW, {
            'requested_at': int(time.time()),
            'release': remote.get('release'),
            'build': remote.get('build'),
        })
        return jsonify(
            ok=True, status='pending',
            message=f"Установка Control Center {remote.get('release')} запущена",
            release=remote.get('release'), build=remote.get('build'),
        ), 202

    def notifications_108():
        base_response = previous_notifications() if previous_notifications else jsonify(items=[], count=0, unread=0)
        try:
            database.sync_notifications(_market_event_notifications())
            items = database.list_notifications(200)
            return jsonify(
                items=items,
                count=len(items),
                unread=sum(1 for x in items if not x.get('read')),
                generated_at=int(time.time()),
                persistence='postgresql',
            )
        except Exception:
            try:
                payload = base_response.get_json() or {}
            except Exception:
                payload = {}
            items = list(payload.get('items') or []) + _market_event_notifications()
            dedup = {}
            for item in items:
                dedup[item.get('id') or hashlib.sha256(repr(item).encode()).hexdigest()[:20]] = item
            result = sorted(dedup.values(), key=lambda x: x.get('timestamp', 0), reverse=True)[:200]
            return jsonify(
                items=result, count=len(result),
                unread=sum(1 for x in result if not x.get('read')),
                generated_at=int(time.time()), persistence='degraded',
            )

    app.view_functions['market'] = market_108
    app.view_functions['market_dhcp'] = market_dhcp_108
    app.view_functions['update_check'] = update_check_108
    app.view_functions['notifications'] = notifications_108
    app.add_url_rule('/api/settings/update/install', 'update_install_108', update_install_108, methods=['POST'])

    static_dir = Path(app.root_path) / 'static'

    @app.before_request
    def release_assets_108():
        if request.method != 'GET':
            return None
        if request.path == '/static/app.js':
            try:
                base = (static_dir / 'app.js').read_text()
                extra = (static_dir / 'release-108.js').read_text()
                return Response(base + '\n\n/* Control Center 1.0.8 */\n' + extra, mimetype='application/javascript')
            except Exception:
                return None
        if request.path == '/static/app.css':
            try:
                base = (static_dir / 'app.css').read_text()
                extra = (static_dir / 'release-108.css').read_text()
                return Response(base + '\n\n/* Control Center 1.0.8 */\n' + extra, mimetype='text/css')
            except Exception:
                return None
        return None
