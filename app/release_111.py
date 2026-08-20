from __future__ import annotations

import hashlib
import ipaddress
import json
import os
import re
import secrets
import socket
import time
from pathlib import Path

from flask import Response, jsonify, request
from psycopg.types.json import Jsonb

import database
import release_110

VERSION = '1.0.11'
BUILD = '20260819.5'
SAMBA_PENDING = Path('/run/control-center/samba-provision.json')
SAMBA_STATUS = Path('/var/lib/control-center-system/samba-status.json')
SAMBA_MODULE = Path('/var/lib/control-center-system/modules/samba.json')
SAMBA_READINESS = Path('/var/lib/control-center-system/samba-readiness.json')


def _active_role(main, role):
    config, interfaces, _ = main._effective_network_config()
    cfg = dict(config.get(role) or {})
    enabled = bool(cfg.get('enabled', bool(cfg.get('interface')))) and cfg.get('method') != 'disabled'
    if not enabled:
        return None, interfaces
    return cfg, interfaces


def _realm(value):
    value = str(value or '').strip().rstrip('.').lower()
    if len(value) > 253 or '.' not in value or value.endswith('.local'):
        raise ValueError('Realm должен быть полноценным DNS-доменом и не должен оканчиваться на .local')
    labels = value.split('.')
    for label in labels:
        if not re.fullmatch(r'[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?', label):
            raise ValueError('Realm содержит недопустимую DNS-метку')
    return value.upper()


def _netbios(value, hostname):
    value = str(value or '').strip().upper()
    if not re.fullmatch(r'[A-Z0-9](?:[A-Z0-9-]{0,13}[A-Z0-9])?', value):
        raise ValueError('NetBIOS domain: 1–15 символов, A-Z, 0-9 и дефис')
    if value == str(hostname or '').split('.')[0].upper():
        raise ValueError('NetBIOS domain не должен совпадать с коротким именем контроллера домена')
    return value


def _password(value, confirm):
    value = str(value or '')
    if value != str(confirm or ''):
        raise ValueError('Пароли Administrator не совпадают')
    if not 12 <= len(value) <= 128 or any(ord(c) < 32 for c in value):
        raise ValueError('Пароль Administrator должен содержать 12–128 печатных символов')
    categories = sum([
        any(c.islower() for c in value),
        any(c.isupper() for c in value),
        any(c.isdigit() for c in value),
        any(not c.isalnum() for c in value),
    ])
    if categories < 3:
        raise ValueError('Пароль Administrator должен содержать минимум 3 категории: строчные, прописные, цифры, спецсимволы')
    return value


def _suggest_forwarder(cfg, interfaces, ad_ip):
    values = []
    for source in (cfg.get('dns') or [], cfg.get('live_dns') or []):
        values.extend(source if isinstance(source, list) else [])
    for row in interfaces:
        values.extend(row.get('dns') or [])
    for value in values:
        try:
            ip = ipaddress.IPv4Address(str(value))
        except Exception:
            continue
        if str(ip) != ad_ip and not ip.is_loopback and not ip.is_multicast and not ip.is_unspecified:
            return str(ip)
    return ''


def _public_request(main, body, require_secret=False):
    if not isinstance(body, dict):
        raise ValueError('Некорректный запрос')
    hostname = socket.gethostname().split('.')[0]
    realm = _realm(body.get('realm'))
    domain = _netbios(body.get('netbios_domain'), hostname)
    role = str(body.get('network_role') or '').lower()
    if role not in {'lan', 'wan'}:
        raise ValueError('Выберите сетевую роль домена')
    cfg, interfaces = _active_role(main, role)
    if not cfg:
        raise ValueError(f'{role.upper()} выключен')
    if str(cfg.get('method') or '').lower() != 'static':
        raise ValueError('Контроллер домена требует статический IPv4 на выбранной роли')
    iface = str(cfg.get('interface') or '')
    if not iface:
        raise ValueError('У выбранной роли нет интерфейса')
    ip = str(cfg.get('ip') or '').strip()
    prefix = int(cfg.get('mask'))
    addr = ipaddress.IPv4Interface(f'{ip}/{prefix}')
    if role == 'wan' and not bool(body.get('allow_wan')):
        raise ValueError('AD-DC на WAN требует отдельного подтверждения. Используйте LAN, если она доступна.')
    forwarder = str(body.get('dns_forwarder') or '').strip() or _suggest_forwarder(cfg, interfaces, str(addr.ip))
    if not forwarder:
        raise ValueError('Укажите внешний DNS forwarder для Samba Internal DNS')
    try:
        fwd = ipaddress.IPv4Address(forwarder)
    except Exception:
        raise ValueError('DNS forwarder должен быть IPv4-адресом')
    if fwd == addr.ip or fwd.is_loopback or fwd.is_multicast or fwd.is_unspecified:
        raise ValueError('DNS forwarder не должен указывать на сам контроллер, loopback или multicast')
    fqdn = f"{hostname}.{realm.lower()}"
    if len(fqdn) > 253:
        raise ValueError('FQDN контроллера слишком длинный')
    result = {
        'realm': realm,
        'dns_domain': realm.lower(),
        'netbios_domain': domain,
        'network_role': role,
        'interface': iface,
        'ipv4': str(addr.ip),
        'prefix': prefix,
        'network': str(addr.network),
        'dns_forwarder': str(fwd),
        'fqdn': fqdn,
        'replace_existing': bool(body.get('replace_existing')),
        'allow_wan': bool(body.get('allow_wan')),
    }
    if require_secret:
        if body.get('confirmation') is not True:
            raise ValueError('Подтвердите создание нового домена')
        result['administrator_password'] = _password(body.get('administrator_password'), body.get('confirm_password'))
        code = str(body.get('approval_code') or '').strip().lower()
        if not re.fullmatch(r'[0-9a-f]{8}', code):
            raise ValueError('Введите одноразовый 8-символьный код из sudo control-center-samba-approve')
        result['approval_code'] = code
    return result


def _package_checks(main):
    names = ['samba', 'samba-dsdb-modules', 'samba-vfs-modules', 'winbind', 'krb5-user', 'dnsutils', 'acl', 'attr', 'smbclient', 'chrony']
    return [release_110._pkg_candidate(main, name) for name in names]


def _readiness(main, body=None, persist=True):
    body = body or {}
    base = release_110._samba_readiness(main, persist=False)
    checks = dict(base.get('checks') or {})
    public = None
    config_error = ''
    try:
        public = _public_request(main, body, require_secret=False)
    except Exception as exc:
        config_error = str(exc)
    checks['domain_config'] = {
        'ok': public is not None,
        'severity': 'blocker',
        'value': public or {},
        'message': 'Параметры нового домена проверены' if public else config_error or 'Заполните параметры домена',
    }
    # Current host FQDN does not need to exist before first provisioning: the helper
    # creates the AD FQDN mapping before samba-tool runs.
    if public:
        checks['fqdn'] = {'ok': True, 'severity': 'info', 'value': public['fqdn'], 'message': 'Целевой FQDN будет подготовлен перед provisioning'}
    packages = _package_checks(main)
    checks['packages'] = {
        'ok': all(x['available'] for x in packages),
        'severity': 'blocker',
        'value': packages,
        'message': 'Все production-пакеты Samba AD-DC доступны в APT' if all(x['available'] for x in packages) else 'Не все production-пакеты Samba AD-DC доступны в APT',
    }
    existing = Path('/etc/samba/smb.conf').exists() and not (main._read_json(SAMBA_MODULE, {}).get('managed'))
    replace = bool(body.get('replace_existing'))
    checks['existing_samba'] = {
        'ok': not existing or replace,
        'severity': 'blocker' if existing else 'info',
        'value': '/etc/samba/smb.conf' if existing else 'none',
        'message': 'Существующая Samba будет сохранена в backup и явно заменена' if existing and replace else ('Обнаружена внешняя Samba-конфигурация: требуется явное разрешение на замену' if existing else 'Внешняя Samba-конфигурация не обнаружена'),
    }
    ufw_rc, ufw_out, _ = main._run(['ufw', 'status'], 4)
    firewall_active = ufw_rc == 0 and ufw_out.lower().startswith('status: active')
    checks['firewall'] = {
        'ok': True,
        'severity': 'warning',
        'value': 'active' if firewall_active else 'inactive-or-other',
        'message': 'UFW активен: после provisioning проверьте интерфейсные AD-DC правила' if firewall_active else 'UFW не блокирует provisioning-проверку',
    }
    blockers = [k for k, v in checks.items() if v.get('severity') == 'blocker' and not v.get('ok')]
    warnings = [k for k, v in checks.items() if v.get('severity') == 'warning' and not v.get('ok')]
    ready = not blockers
    details = dict(base.get('details') or {})
    details.update({
        'packages': packages,
        'installation_enabled': True,
        'provisioning_enabled': True,
        'production_release': VERSION,
        'approval_required': True,
        'approval_command': 'sudo control-center-samba-approve',
        'password_persisted': False,
        'target': public or {},
    })
    payload = {
        'ready': ready,
        'hostname': socket.gethostname(),
        'fqdn': (public or {}).get('fqdn', socket.getfqdn()),
        'checks': checks,
        'blockers': blockers,
        'warnings': warnings,
        'details': details,
        'checked_at': int(time.time()),
    }
    if persist:
        try:
            main._write_json(SAMBA_READINESS, payload)
        except Exception:
            pass
        try:
            with database.connect() as conn:
                conn.execute(
                    "INSERT INTO control_center.ad_dc_readiness_runs(hostname,fqdn,ready,blockers,warnings,checks,details) VALUES(%s,%s,%s,%s,%s,%s,%s)",
                    (payload['hostname'], payload['fqdn'], ready, Jsonb(blockers), Jsonb(warnings), Jsonb(checks), Jsonb(details)),
                )
        except Exception:
            pass
    return payload


def _quick_health(main, persist=True):
    module = main._read_json(SAMBA_MODULE, {})
    if not module.get('managed') or module.get('state') != 'active':
        return {'healthy': False, 'state': 'not-provisioned', 'checks': {}, 'details': module, 'checked_at': int(time.time())}
    ip = module.get('ipv4')
    realm = str(module.get('realm') or '').lower()
    fqdn = module.get('fqdn')
    checks = {}
    rc, out, err = main._run(['systemctl', 'is-active', 'samba-ad-dc.service'], 4)
    checks['service'] = {'ok': rc == 0 and out.strip() == 'active', 'value': out.strip() or err.strip(), 'message': 'samba-ad-dc active'}
    rc, out, err = main._run(['samba-tool', 'domain', 'info', str(ip)], 8)
    checks['domain_info'] = {'ok': rc == 0, 'value': out[-1500:] if out else err[-1500:], 'message': 'samba-tool domain info'}
    rc, out, err = main._run(['samba-tool', 'drs', 'showrepl', '--summary'], 10)
    checks['replication'] = {'ok': rc == 0, 'value': out[-1500:] if out else err[-1500:], 'message': 'DRS replication summary'}
    for key, record in [('dns_a', str(fqdn)), ('dns_ldap', f'_ldap._tcp.{realm}'), ('dns_kerberos', f'_kerberos._udp.{realm}')]:
        qtype = 'A' if key == 'dns_a' else 'SRV'
        rc, out, err = main._run(['host', '-W', '3', '-t', qtype, record, str(ip)], 6)
        checks[key] = {'ok': rc == 0, 'value': out.strip() or err.strip(), 'message': f'DNS {qtype} {record}'}
    rc, out, err = main._run(['samba-tool', 'ntacl', 'sysvolcheck'], 10)
    checks['sysvol'] = {'ok': rc == 0, 'value': out.strip() or err.strip(), 'message': 'SYSVOL ACL'}
    healthy = all(x.get('ok') for x in checks.values())
    payload = {'healthy': healthy, 'state': 'healthy' if healthy else 'degraded', 'checks': checks, 'details': module, 'checked_at': int(time.time())}
    if persist:
        try:
            module['health_state'] = payload['state']
            module['last_health_at'] = payload['checked_at']
            main._write_json(SAMBA_MODULE, module)
        except Exception:
            pass
        try:
            profile = 'primary-' + str(module.get('netbios_domain') or '').lower()
            with database.connect() as conn:
                conn.execute("INSERT INTO control_center.ad_dc_health_runs(profile_id,healthy,checks,details) VALUES(%s,%s,%s,%s)", (profile, healthy, Jsonb(checks), Jsonb(module)))
                conn.execute("UPDATE control_center.ad_dc_profiles SET health_state=%s,last_health_at=now(),updated_at=now() WHERE profile_id=%s", (payload['state'], profile))
        except Exception:
            pass
    return payload


def _status(main):
    module = main._read_json(SAMBA_MODULE, {})
    status = main._read_json(SAMBA_STATUS, {})
    config, interfaces, _ = main._effective_network_config()
    roles = []
    for role in ('lan', 'wan'):
        cfg = config.get(role) or {}
        if cfg.get('enabled', bool(cfg.get('interface'))) and cfg.get('method') != 'disabled':
            roles.append({
                'role': role,
                'interface': cfg.get('interface', ''),
                'method': cfg.get('method', ''),
                'ipv4': cfg.get('ip', ''),
                'prefix': cfg.get('mask', ''),
                'dns': cfg.get('dns') or cfg.get('live_dns') or [],
                'eligible': cfg.get('method') == 'static' and bool(cfg.get('ip')),
            })
    service = {'active': False, 'state': 'not-installed'}
    if module.get('installed'):
        rc, out, _ = main._run(['systemctl', 'is-active', 'samba-ad-dc.service'], 4)
        service = {'active': rc == 0 and out.strip() == 'active', 'state': out.strip() or 'inactive'}
    return {
        'version': VERSION,
        'module': module,
        'status': status,
        'service': service,
        'network_roles': roles,
        'suggested_role': 'lan' if any(x['role'] == 'lan' and x['eligible'] for x in roles) else next((x['role'] for x in roles if x['eligible']), ''),
        'approval_required': True,
        'approval_command': 'sudo control-center-samba-approve',
        'password_persisted': False,
        'provisioned': bool(module.get('managed') and module.get('state') == 'active'),
    }


def _market_status(main):
    module = main._read_json(SAMBA_MODULE, {})
    status = main._read_json(SAMBA_STATUS, {})
    now = int(time.time())
    state = str(status.get('state') or '')
    if state in {'provisioning', 'installing', 'applying'}:
        return {'code': 'installing', 'label': 'Создание домена…', 'detail': status.get('message') or 'Samba AD-DC provisioning выполняется.', 'timestamp': int(status.get('timestamp') or now)}
    if state in {'rollback', 'error', 'failed', 'rejected'}:
        return {'code': 'error', 'label': 'Ошибка', 'detail': status.get('detail') or status.get('message') or 'Samba AD-DC provisioning завершился ошибкой.', 'timestamp': int(status.get('timestamp') or 0)}
    if module.get('managed') and module.get('state') == 'active':
        rc, out, _ = main._run(['systemctl', 'is-active', 'samba-ad-dc.service'], 4)
        running = rc == 0 and out.strip() == 'active'
        return {'code': 'running' if running else 'error', 'label': 'Работает' if running else 'Ошибка', 'detail': f"{module.get('fqdn','Samba AD-DC')} · {module.get('realm','')}" if running else 'Домен создан, но samba-ad-dc.service не активен.', 'timestamp': int(module.get('provisioned_at') or 0)}
    return {'code': 'available', 'label': 'Готов к настройке', 'detail': 'Создание нового Samba Active Directory Domain Controller доступно в 1.0.11.', 'timestamp': 0}


def register(app, main):
    main.APP_VERSION = VERSION
    main.APP_BUILD = BUILD
    previous_market = app.view_functions.get('market')
    previous_notifications = app.view_functions.get('notifications')

    try:
        lic = main._license_info()
        database.upsert_local_node(edition=lic.get('edition', 'Home'), version=VERSION, build=BUILD)
    except Exception:
        pass

    def samba_status_111():
        return jsonify(_status(main))

    def samba_readiness_111():
        body = request.get_json(silent=True) or {} if request.method == 'POST' else {}
        return jsonify(_readiness(main, body, persist=True))

    def samba_plan_111():
        body = request.get_json(silent=True) or {}
        readiness = _readiness(main, body, persist=True)
        target = readiness.get('details', {}).get('target') or {}
        plan = {
            'phase': 'production-provision',
            'target_release': VERSION,
            'provisioning_enabled': True,
            'approval_required': True,
            'target': target,
            'dns_backend': 'SAMBA_INTERNAL',
            'password_persisted': False,
            'backup': ['/etc/samba', '/var/lib/samba', '/var/cache/samba', '/etc/krb5.conf', '/etc/resolv.conf', '/etc/hosts', '/etc/systemd/resolved.conf', '/etc/chrony', 'Control Center DHCP config'],
            'cutover': ['backup', 'install packages', 'stop conflicting Samba/resolved services', 'prepare DC FQDN', 'domain provision', 'Kerberos resolver cutover', 'Samba AD-DC start', 'signed NTP', 'DHCP DNS integration', 'acceptance'],
            'rollback': ['stop generated Samba/chrony runtime', 'restore archived configs and Samba state', 'restore previous services', 'restore DHCP config', 'publish rollback notification'],
            'acceptance': ['samba-tool testparm', 'samba-tool ntacl sysvolcheck', 'samba-tool domain info', 'samba-tool drs showrepl --summary', 'DNS A/SRV', 'kinit Administrator', 'smbclient'],
        }
        digest = hashlib.sha256(json.dumps(plan, ensure_ascii=False, sort_keys=True).encode()).hexdigest()
        return jsonify(ready=readiness['ready'], blockers=readiness['blockers'], warnings=readiness['warnings'], plan=plan, sha256=digest, created_at=int(time.time()))

    def samba_provision_111():
        if main._read_json(SAMBA_MODULE, {}).get('state') == 'active':
            return jsonify(ok=False, error='Samba AD-DC уже создан и управляется Control Center'), 409
        if SAMBA_PENDING.exists():
            return jsonify(ok=False, error='Операция Samba AD-DC уже ожидает root worker'), 409
        body = request.get_json(silent=True) or {}
        try:
            public = _public_request(main, body, require_secret=False)
            readiness = _readiness(main, body, persist=True)
            if not readiness['ready']:
                return jsonify(ok=False, error='Readiness содержит блокеры', blockers=readiness['blockers'], readiness=readiness), 409
            full = _public_request(main, body, require_secret=True)
        except ValueError as exc:
            return jsonify(ok=False, error=str(exc)), 400
        if not SAMBA_PENDING.parent.exists():
            return jsonify(ok=False, error='Runtime-каталог Samba не подготовлен. Переустановите 1.0.11 или перезапустите systemd-tmpfiles.'), 503
        job_id = f"samba-provision-{int(time.time())}-{secrets.token_hex(4)}"
        full['job_id'] = job_id
        full['requested_at'] = int(time.time())
        try:
            main._write_json(SAMBA_PENDING, full)
            os.chmod(SAMBA_PENDING, 0o600)
        except Exception as exc:
            return jsonify(ok=False, error=f'Не удалось передать секрет root worker: {exc}'), 500
        db_request = dict(public)
        db_request.update({'replace_existing': bool(body.get('replace_existing')), 'allow_wan': bool(body.get('allow_wan')), 'approval_required': True})
        try:
            with database.connect() as conn:
                conn.execute("INSERT INTO control_center.ad_dc_lifecycle_jobs(job_id,action,state,request) VALUES(%s,'provision','queued',%s)", (job_id, Jsonb(db_request)))
        except Exception:
            pass
        return jsonify(ok=True, status='pending', job_id=job_id, message='Создание Samba AD-DC передано root worker. Пароль и одноразовый код находятся только в /run и будут удалены после чтения.'), 202

    def samba_health_111():
        return jsonify(_quick_health(main, persist=True))

    def market_111():
        try:
            payload = previous_market().get_json() if previous_market else {'items': []}
        except Exception:
            payload = {'items': []}
        for item in payload.get('items', []):
            if item.get('id') == 'samba':
                module = main._read_json(SAMBA_MODULE, {})
                item.update({
                    'name': 'Samba AD-DC',
                    'description': 'Active Directory Domain Controller: Kerberos, LDAP, DNS, SYSVOL/NETLOGON и signed NTP',
                    'state': 'installed' if module.get('state') == 'active' else 'available',
                    'installable': True,
                    'status': _market_status(main),
                    'action_mode': 'configure',
                })
        payload['samba_installed'] = bool(main._read_json(SAMBA_MODULE, {}).get('state') == 'active')
        return jsonify(payload)

    def notifications_111():
        try:
            payload = previous_notifications().get_json() if previous_notifications else {'items': []}
        except Exception:
            payload = {'items': []}
        items = [x for x in (payload.get('items') or []) if x.get('source') != 'samba']
        status = main._read_json(SAMBA_STATUS, {})
        module = main._read_json(SAMBA_MODULE, {})
        now = int(time.time())
        if status:
            st = str(status.get('state') or '')
            severity = 'error' if st in {'error', 'rollback', 'failed', 'rejected'} else ('ok' if st == 'active' else 'info')
            items.append(release_110._notification_item(
                'samba-lifecycle-' + str(status.get('job_id') or status.get('timestamp') or now),
                'samba', 'Samba AD-DC', severity, st,
                str(status.get('message') or st) + (('\n' + str(status.get('detail'))) if status.get('detail') else ''),
                status.get('timestamp') or now,
            ))
        elif module.get('state') == 'active':
            items.append(release_110._notification_item('samba-active', 'samba', 'Samba AD-DC', 'ok', 'active', f"Домен {module.get('realm','')} работает на {module.get('fqdn','')}", module.get('provisioned_at') or now))
        dedup = {x.get('id') or hashlib.sha256(repr(x).encode()).hexdigest()[:20]: x for x in items}
        rows = sorted(dedup.values(), key=lambda x: x.get('timestamp', 0), reverse=True)[:200]
        return jsonify(items=rows, count=len(rows), unread=sum(1 for x in rows if not x.get('read')), generated_at=now, persistence=payload.get('persistence', 'degraded'))

    app.view_functions['market'] = market_111
    app.view_functions['notifications'] = notifications_111
    if 'samba_readiness_110' in app.view_functions:
        app.view_functions['samba_readiness_110'] = samba_readiness_111
    if 'samba_plan_110' in app.view_functions:
        app.view_functions['samba_plan_110'] = samba_plan_111
    if 'samba_preflight_109' in app.view_functions:
        app.view_functions['samba_preflight_109'] = samba_readiness_111

    app.add_url_rule('/api/samba/status', 'samba_status_111', samba_status_111, methods=['GET'])
    app.add_url_rule('/api/samba/provision', 'samba_provision_111', samba_provision_111, methods=['POST'])
    app.add_url_rule('/api/samba/health', 'samba_health_111', samba_health_111, methods=['GET', 'POST'])

    static_dir = Path(app.root_path) / 'static'

    def release_assets_111():
        if request.method != 'GET':
            return None
        if request.path == '/static/app.js':
            try:
                payload = (
                    (static_dir / 'app.js').read_text()
                    + '\n\n' + (static_dir / 'release-108.js').read_text()
                    + '\n\n' + (static_dir / 'release-110.js').read_text()
                    + '\n\n' + (static_dir / 'release-110-fix.js').read_text()
                    + '\n\n' + (static_dir / 'release-111.js').read_text()
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
                    + '\n\n' + (static_dir / 'release-111.css').read_text()
                )
                return Response(payload, mimetype='text/css')
            except Exception:
                return None
        return None

    app.before_request_funcs.setdefault(None, []).insert(0, release_assets_111)
