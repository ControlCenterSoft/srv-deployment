from __future__ import annotations

import json
import os
import secrets
import socket
import time
from collections import defaultdict, deque
from pathlib import Path

from flask import jsonify, redirect, render_template, request, session
from psycopg.types.json import Jsonb

import database

SAMBA_MODULE = Path('/var/lib/control-center-system/modules/samba.json')
AUTH_SOCKET = '/run/control-center-auth/auth.sock'
MAX_ATTEMPTS = 8
WINDOW_SECONDS = 300
_attempts = defaultdict(deque)


def _audit(action, status, details=None):
    try:
        with database.connect() as conn:
            conn.execute(
                "INSERT INTO control_center.audit_events(action,resource,status,remote_addr,details) VALUES(%s,'auth',%s,%s,%s)",
                (action, status, request.remote_addr, Jsonb(details or {})),
            )
    except Exception:
        pass


def _rate_key(username):
    return f"{request.remote_addr or '-'}|{username.lower()}"


def _rate_allowed(username):
    now = time.time()
    q = _attempts[_rate_key(username)]
    while q and now - q[0] > WINDOW_SECONDS:
        q.popleft()
    return len(q) < MAX_ATTEMPTS


def _rate_fail(username):
    _attempts[_rate_key(username)].append(time.time())


def _rate_clear(username):
    _attempts.pop(_rate_key(username), None)


def _domain_module(main):
    m = main._read_json(SAMBA_MODULE, {})
    return m if m.get('managed') and m.get('state') == 'active' else {}


def _authd(mode, username, password):
    payload = json.dumps({'mode': mode, 'username': username, 'password': password}, ensure_ascii=False, separators=(',', ':')).encode('utf-8') + b'\n'
    try:
        s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        s.settimeout(18)
        s.connect(AUTH_SOCKET)
        s.sendall(payload)
        raw = b''
        while b'\n' not in raw and len(raw) <= 8192:
            part = s.recv(2048)
            if not part:
                break
            raw += part
        s.close()
    except OSError as exc:
        raise RuntimeError(f'Служба авторизации недоступна: {exc}') from exc
    try:
        result = json.loads(raw.split(b'\n', 1)[0].decode('utf-8'))
    except Exception as exc:
        raise RuntimeError('Служба авторизации вернула некорректный ответ') from exc
    if not result.get('ok'):
        return None
    identity = result.get('identity') or {}
    if identity.get('role') not in {'admin', 'viewer'} or not identity.get('principal'):
        raise RuntimeError('Служба авторизации вернула некорректную роль')
    return identity


def register(app, main):
    secret = os.getenv('CONTROL_CENTER_SESSION_SECRET', '').strip()
    if len(secret) < 32:
        # Installer always supplies a persistent random secret. This fallback is
        # deliberately process-local rather than derived from machine-id.
        secret = secrets.token_hex(32)
    app.secret_key = secret
    app.config.update(
        SESSION_COOKIE_HTTPONLY=True,
        SESSION_COOKIE_SAMESITE='Strict',
        SESSION_COOKIE_SECURE=str(os.getenv('CONTROL_CENTER_SSL', '0')).lower() in {'1', 'true', 'yes'},
        PERMANENT_SESSION_LIFETIME=8 * 60 * 60,
    )

    @app.get('/login')
    def login_111():
        if session.get('principal'):
            return redirect('/')
        module = _domain_module(main)
        return render_template(
            'login.html',
            version=main.APP_VERSION,
            build=main.APP_BUILD,
            domain_enabled=bool(module),
            domain_name=module.get('realm') or '',
        )

    @app.post('/api/auth/login')
    def auth_login_111():
        body = request.get_json(silent=True) or {}
        mode = str(body.get('mode') or 'local').lower()
        username = str(body.get('username') or '').strip()
        password = str(body.get('password') or '')
        if mode not in {'local', 'domain'} or not username or not password or len(username) > 256 or len(password) > 512:
            return jsonify(ok=False, error='Укажите корректные данные входа'), 400
        if mode == 'domain' and not _domain_module(main):
            return jsonify(ok=False, error='Доменная авторизация недоступна: Домен не активирован'), 409
        if not _rate_allowed(username):
            _audit('login', 'rate-limited', {'mode': mode, 'username': username})
            return jsonify(ok=False, error='Слишком много попыток. Повторите через несколько минут.'), 429
        try:
            identity = _authd(mode, username, password)
        except RuntimeError as exc:
            password = ''
            _audit('login', 'auth-service-unavailable', {'mode': mode, 'username': username})
            return jsonify(ok=False, error=str(exc)), 503
        password = ''
        if not identity:
            _rate_fail(username)
            _audit('login', 'denied', {'mode': mode, 'username': username})
            return jsonify(ok=False, error='Неверное имя пользователя или пароль'), 401
        _rate_clear(username)
        session.clear()
        session.permanent = True
        session['principal'] = identity['principal']
        session['username'] = identity.get('username') or username
        session['auth_source'] = identity.get('source') or mode
        session['role'] = identity['role']
        session['domain'] = identity.get('domain') or ''
        session['issued_at'] = int(time.time())
        _audit('login', 'success', {'source': session['auth_source'], 'principal': identity['principal'], 'role': identity['role']})
        return jsonify(ok=True, next='/', principal=identity['principal'], role=identity['role'], source=session['auth_source'])

    @app.post('/api/auth/logout')
    def auth_logout_111():
        principal = session.get('principal')
        session.clear()
        _audit('logout', 'success', {'principal': principal or ''})
        return jsonify(ok=True)

    @app.get('/api/auth/session')
    def auth_session_111():
        if not session.get('principal'):
            return jsonify(authenticated=False), 401
        return jsonify(
            authenticated=True,
            principal=session.get('principal'),
            username=session.get('username'),
            source=session.get('auth_source'),
            role=session.get('role'),
            domain=session.get('domain'),
            issued_at=session.get('issued_at'),
            rbac_mode='bootstrap',
        )

    original_index = app.view_functions.get('index')

    def index_auth_111():
        if not session.get('principal'):
            return redirect('/login')
        return original_index()

    if original_index:
        app.view_functions['index'] = index_auth_111

    def auth_guard_111():
        if os.getenv('CONTROL_CENTER_TEST_BYPASS_AUTH') == '1':
            return None
        path = request.path
        if path.startswith('/static/') or path in {'/login', '/api/auth/login', '/api/health'}:
            return None
        if path.startswith('/api/') or path == '/':
            if not session.get('principal'):
                if path.startswith('/api/'):
                    return jsonify(ok=False, error='Требуется авторизация'), 401
                return redirect('/login')
            if request.method in {'POST', 'PUT', 'PATCH', 'DELETE'} and session.get('role') != 'admin':
                _audit('authorize', 'denied', {'principal': session.get('principal'), 'path': path, 'method': request.method, 'role': session.get('role')})
                return jsonify(ok=False, error='Недостаточно прав. Требуется роль администратора Control Center.'), 403
        return None

    app.before_request_funcs.setdefault(None, []).insert(0, auth_guard_111)
