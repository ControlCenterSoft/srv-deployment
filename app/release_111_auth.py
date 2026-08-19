from __future__ import annotations

import grp
import os
import pwd
import secrets
import subprocess
import time
from collections import defaultdict, deque
from pathlib import Path

from flask import jsonify, redirect, render_template, request, session
from psycopg.types.json import Jsonb

import database

SAMBA_MODULE = Path('/var/lib/control-center-system/modules/samba.json')
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


def _local_role(username):
    try:
        user = pwd.getpwnam(username)
    except KeyError:
        return None
    if user.pw_uid < 1000:
        # System accounts are not portal identities. root is intentionally excluded.
        return None
    groups = set()
    for g in grp.getgrall():
        if username in g.gr_mem or user.pw_gid == g.gr_gid:
            groups.add(g.gr_name)
    return 'admin' if groups.intersection({'sudo', 'wheel', 'control-center-admins'}) else 'viewer'


def _pam_auth(username, password):
    role = _local_role(username)
    if role is None:
        return None
    try:
        p = subprocess.run(
            ['pamtester', 'control-center-web', username, 'authenticate', 'acct_mgmt'],
            input=password + '\n',
            text=True,
            capture_output=True,
            timeout=12,
            check=False,
        )
    except Exception:
        return None
    return role if p.returncode == 0 else None


def _domain_module(main):
    m = main._read_json(SAMBA_MODULE, {})
    return m if m.get('managed') and m.get('state') == 'active' else {}


def _domain_auth(main, username, password):
    module = _domain_module(main)
    domain = str(module.get('netbios_domain') or '').strip().upper()
    if not domain or not username or '\n' in username or '\r' in username:
        return None
    # Accept DOMAIN\\user, user@realm and plain user, but always bind to the
    # locally managed domain to avoid accidental cross-domain authentication.
    raw = username.strip()
    if '\\' in raw:
        supplied_domain, raw = raw.split('\\', 1)
        if supplied_domain.upper() != domain:
            return None
    elif '@' in raw:
        raw, supplied_realm = raw.rsplit('@', 1)
        if supplied_realm.lower() != str(module.get('realm') or '').lower():
            return None
    if not raw or len(raw) > 128:
        return None
    base = ['ntlm_auth', f'--username={raw}', f'--domain={domain}']
    try:
        p = subprocess.run(base, input=password + '\n', text=True, capture_output=True, timeout=15, check=False)
    except Exception:
        return None
    if p.returncode != 0:
        return None
    # RBAC-ready bootstrap policy: only the dedicated domain group receives
    # administrative writes. All other successfully authenticated domain users
    # can enter the portal in viewer mode until RBAC replaces this mapping.
    admin_group = f'{domain}\\Control Center Admins'
    try:
        p2 = subprocess.run(
            base + [f'--require-membership-of={admin_group}'],
            input=password + '\n', text=True, capture_output=True, timeout=15, check=False,
        )
        role = 'admin' if p2.returncode == 0 else 'viewer'
    except Exception:
        role = 'viewer'
    return {'principal': f'{domain}\\{raw}', 'username': raw, 'domain': domain, 'role': role}


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
        if not _rate_allowed(username):
            _audit('login', 'rate-limited', {'mode': mode, 'username': username})
            return jsonify(ok=False, error='Слишком много попыток. Повторите через несколько минут.'), 429
        identity = None
        if mode == 'local':
            role = _pam_auth(username, password)
            if role:
                identity = {'principal': username, 'username': username, 'domain': '', 'role': role}
        else:
            identity = _domain_auth(main, username, password)
        # Make a best effort to remove the Python reference promptly; neither the
        # password nor request body is persisted in audit/database/session.
        password = ''
        if not identity:
            _rate_fail(username)
            _audit('login', 'denied', {'mode': mode, 'username': username})
            return jsonify(ok=False, error='Неверное имя пользователя или пароль'), 401
        _rate_clear(username)
        session.clear()
        session.permanent = True
        session['principal'] = identity['principal']
        session['username'] = identity['username']
        session['auth_source'] = mode
        session['role'] = identity['role']
        session['domain'] = identity.get('domain') or ''
        session['issued_at'] = int(time.time())
        _audit('login', 'success', {'source': mode, 'principal': identity['principal'], 'role': identity['role']})
        return jsonify(ok=True, next='/', principal=identity['principal'], role=identity['role'], source=mode)

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
