from __future__ import annotations

import hashlib
import ipaddress
import json
import os
import platform
import re
import shutil
import socket
import subprocess
import time
from pathlib import Path

from flask import Response, jsonify, request
from psycopg.types.json import Jsonb

import database
import release_108
import release_109

VERSION = '1.0.10'
BUILD = '20260819.4'
HOSTNAME_PENDING = Path('/var/lib/control-center/hostname-pending.json')
HOSTNAME_STATUS = Path('/var/lib/control-center-system/hostname-status.json')
WEB_PENDING = Path('/var/lib/control-center/web-pending.json')
WEB_STATUS = Path('/var/lib/control-center-system/web-status.json')
WEB_CONFIG = Path('/var/lib/control-center-system/web-config.json')
SAMBA_READINESS = Path('/var/lib/control-center-system/samba-readiness.json')


def _bool(value, default=False):
    return value if isinstance(value, bool) else default


def _runtime_web():
    try:
        port = int(os.getenv('CONTROL_CENTER_PORT', '8080'))
    except Exception:
        port = 8080
    ssl_enabled = str(os.getenv('CONTROL_CENTER_SSL', '0')).strip().lower() in {'1', 'true', 'yes', 'on'}
    standard = str(os.getenv('CONTROL_CENTER_STANDARD_PORT', '0')).strip().lower() in {'1', 'true', 'yes', 'on'}
    return {
        'port': port,
        'ssl_enabled': ssl_enabled,
        'standard_port': standard,
        'scheme': 'https' if ssl_enabled else 'http',
    }


def _file_web(main):
    runtime = _runtime_web()
    cfg = main._read_json(WEB_CONFIG, {})
    try:
        port = int(cfg.get('port', runtime['port']))
    except Exception:
        port = runtime['port']
    return {
        'port': port,
        'ssl_enabled': bool(cfg.get('ssl_enabled', runtime['ssl_enabled'])),
        'standard_port': bool(cfg.get('standard_port', runtime['standard_port'])),
        'certificate': cfg.get('certificate', 'self-signed' if runtime['ssl_enabled'] else 'none'),
        'scheme': cfg.get('scheme', 'https' if runtime['ssl_enabled'] else 'http'),
    }


def _port_in_use(main, port):
    runtime = _runtime_web()
    if port == runtime['port']:
        return False, ''
    rc, out, err = main._run(['ss', '-H', '-ltn'], 3)
    if rc != 0:
        return False, err
    needle = f':{port}'
    for line in out.splitlines():
        parts = line.split()
        local = parts[3] if len(parts) >= 4 else ''
        if local.endswith(needle):
            return True, line.strip()
    return False, ''


def _role_disabled(src):
    if not isinstance(src, dict):
        return True
    iface = str(src.get('interface') or '').strip().lower()
    method = str(src.get('method') or '').strip().lower()
    return src.get('enabled') is False or iface in {'', 'disabled', '__disabled__', 'off'} or method == 'disabled'


def _effective_network_110(main, legacy_effective):
    stored = main._read_json(main.NETWORK_FILE, {})
    if not stored:
        roles, interfaces, source = legacy_effective()
        for role in ('wan', 'lan'):
            cfg = roles.get(role) or {}
            cfg['enabled'] = bool(cfg.get('interface'))
            if not cfg.get('interface'):
                cfg['method'] = 'disabled'
            roles[role] = cfg
        return roles, interfaces, source

    parsed = main._parse_netplan_config()
    interfaces = main._interfaces()
    by_name = {x['name']: x for x in interfaces}
    roles = {}
    for role in ('wan', 'lan'):
        cfg = dict(stored.get(role) or {})
        if _role_disabled(cfg):
            roles[role] = {
                'enabled': False,
                'interface': '',
                'method': 'disabled',
                'live_ipv4': [],
                'live_gateway': '',
                'live_dns': [],
                'link_state': 'disabled',
            }
            continue
        iface = str(cfg.get('interface') or '')
        merged = dict(parsed.get(iface) or {})
        merged.update({k: v for k, v in cfg.items() if v not in ('', None, [])})
        merged['enabled'] = True
        live = by_name.get(iface, {})
        merged['live_ipv4'] = live.get('ipv4', [])
        merged['live_gateway'] = live.get('gateway', '')
        merged['live_dns'] = live.get('dns', [])
        merged['link_state'] = live.get('state', 'unknown')
        roles[role] = merged
    return roles, interfaces, 'stored'


def _validate_network_110(main, body):
    if not isinstance(body, dict):
        raise ValueError('Некорректный запрос')
    known = {x['name'] for x in main._interfaces()}
    requested = {role: dict(body.get(role) or {}) for role in ('wan', 'lan')}
    enabled = {role: not _role_disabled(requested[role]) for role in ('wan', 'lan')}
    if not any(enabled.values()):
        raise ValueError('WAN и LAN не могут быть одновременно выключены')

    result = {'wan': {}, 'lan': {}}
    used = set()
    static_nets = []
    for role in ('wan', 'lan'):
        src = requested[role]
        if not enabled[role]:
            result[role] = {'enabled': False, 'interface': '', 'method': 'disabled'}
            continue

        iface = str(src.get('interface') or '').strip()
        method = str(src.get('method') or 'dhcp').strip().lower()
        if iface not in known:
            raise ValueError(f'{role.upper()}: выберите существующий интерфейс или «Выключен»')
        if iface in used:
            raise ValueError('WAN и LAN должны использовать разные интерфейсы')
        used.add(iface)
        if method not in {'dhcp', 'static'}:
            raise ValueError(f'{role.upper()}: неизвестный режим адресации')

        dst = {'enabled': True, 'interface': iface, 'method': method}
        if method == 'static':
            ip = str(src.get('ip') or '').strip()
            prefix = main._mask_to_prefix(src.get('mask'))
            gateway = str(src.get('gateway') or '').strip()
            dns = src.get('dns') or []
            if isinstance(dns, str):
                dns = [x.strip() for x in dns.replace(';', ',').split(',') if x.strip()]
            try:
                addr = ipaddress.IPv4Interface(f'{ip}/{prefix}')
            except Exception:
                raise ValueError(f'{role.upper()}: некорректный IPv4 адрес')
            if addr.ip.is_unspecified or addr.ip.is_multicast or addr.ip.is_loopback:
                raise ValueError(f'{role.upper()}: IPv4 адрес недопустим')
            if role == 'wan' and not gateway:
                raise ValueError('WAN: для Static требуется шлюз')
            if role == 'lan' and enabled['wan'] and gateway:
                raise ValueError('LAN: при включённом WAN шлюз должен быть пустым, чтобы не создавать второй default route')
            if gateway:
                try:
                    gw = ipaddress.IPv4Address(gateway)
                except Exception:
                    raise ValueError(f'{role.upper()}: некорректный шлюз')
                if gw not in addr.network or gw == addr.ip:
                    raise ValueError(f'{role.upper()}: шлюз должен находиться в той же подсети')
            if not dns:
                raise ValueError(f'{role.upper()}: укажите хотя бы один DNS')
            clean_dns = []
            for value in dns:
                try:
                    clean_dns.append(str(ipaddress.IPv4Address(str(value))))
                except Exception:
                    raise ValueError(f'{role.upper()}: некорректный DNS {value}')
            dst.update({'ip': str(addr.ip), 'mask': prefix, 'gateway': gateway, 'dns': clean_dns})
            static_nets.append((role, addr.network))
        result[role] = dst

    if len(static_nets) == 2 and static_nets[0][1].overlaps(static_nets[1][1]):
        raise ValueError('WAN и LAN не должны использовать пересекающиеся подсети')
    return result


def _role_telemetry(main, role):
    config, interfaces, _ = main._effective_network_config()
    cfg = config.get(role) or {}
    enabled = bool(cfg.get('enabled', bool(cfg.get('interface')))) and cfg.get('method') != 'disabled'
    if not enabled:
        return {'enabled': False, 'interface': '', 'state': 'disabled', 'rx_bytes': 0, 'tx_bytes': 0, 'ipv4': []}
    name = cfg.get('interface')
    row = {x['name']: x for x in interfaces}.get(name)
    return {
        'enabled': True,
        'interface': name or '',
        'state': row['state'] if row else 'unassigned',
        'rx_bytes': row['rx_bytes'] if row else 0,
        'tx_bytes': row['tx_bytes'] if row else 0,
        'ipv4': row['ipv4'] if row else [],
    }


def _pkg_candidate(main, package):
    rc, out, _ = main._run(['apt-cache', 'policy', package], 4)
    candidate = ''
    installed = ''
    if rc == 0:
        for line in out.splitlines():
            s = line.strip()
            if s.startswith('Candidate:'):
                candidate = s.split(':', 1)[1].strip()
            elif s.startswith('Installed:'):
                installed = s.split(':', 1)[1].strip()
    available = bool(candidate and candidate != '(none)')
    return {'package': package, 'available': available, 'candidate': candidate or 'unknown', 'installed': installed or 'unknown'}


def _port_owners(main, port):
    rc, out, _ = main._run(['ss', '-H', '-lntup'], 4)
    rows = []
    if rc == 0:
        pattern = re.compile(rf'(^|[:\]]){int(port)}\s')
        for line in out.splitlines():
            if pattern.search(line) or f':{int(port)} ' in line:
                rows.append(line.strip()[:500])
    return rows


def _samba_readiness(main, persist=True):
    hostname = socket.gethostname()
    fqdn = socket.getfqdn() or hostname
    network, interfaces, source = main._effective_network_config()
    lan = network.get('lan') or {}
    wan = network.get('wan') or {}
    active_roles = [r for r in ('wan', 'lan') if (network.get(r) or {}).get('enabled', bool((network.get(r) or {}).get('interface'))) and (network.get(r) or {}).get('method') != 'disabled']

    host_ok = bool(re.fullmatch(r'[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?', hostname))
    fqdn_ok = '.' in fqdn and not fqdn.endswith('.local') and len(fqdn) <= 253
    static_candidates = []
    for role in active_roles:
        cfg = network.get(role) or {}
        if cfg.get('method') == 'static' and (cfg.get('ip') or cfg.get('live_ipv4')):
            static_candidates.append(role)
    preferred_role = 'lan' if 'lan' in static_candidates else (static_candidates[0] if static_candidates else '')
    static_ok = bool(preferred_role)

    ntp_rc, ntp_out, _ = main._run(['timedatectl', 'show', '-p', 'NTPSynchronized', '--value'], 4)
    ntp_ok = ntp_rc == 0 and ntp_out.strip().lower() == 'yes'
    dns_owners = _port_owners(main, 53)
    kerberos_owners = _port_owners(main, 88)
    ldap_owners = _port_owners(main, 389)
    smb_owners = _port_owners(main, 445)

    package_names = ['samba', 'samba-dsdb-modules', 'samba-vfs-modules', 'winbind', 'krb5-user', 'dnsutils', 'acl', 'attr']
    packages = [_pkg_candidate(main, name) for name in package_names]
    packages_ok = all(x['available'] for x in packages)

    root_usage = shutil.disk_usage('/')
    free_gb = round(root_usage.free / (1024 ** 3), 2)
    disk_ok = root_usage.free >= 2 * 1024 ** 3

    resolv_target = ''
    try:
        resolv_target = os.path.realpath('/etc/resolv.conf')
    except Exception:
        pass
    resolved_active = main._run(['systemctl', 'is-active', 'systemd-resolved.service'], 3)[1].strip() == 'active'
    dnsmasq_active = main._run(['systemctl', 'is-active', 'control-center-dhcp-server.service'], 3)[1].strip() == 'active'
    samba_conf_exists = Path('/etc/samba/smb.conf').exists()
    samba_rc, samba_ver, _ = main._run(['samba', '--version'], 3)
    samba_installed = samba_rc == 0

    checks = {
        'hostname': {'ok': host_ok, 'severity': 'blocker', 'value': hostname, 'message': 'Имя компьютера допустимо для AD' if host_ok else 'Имя компьютера должно быть DNS-совместимым single-label именем'},
        'fqdn': {'ok': fqdn_ok, 'severity': 'blocker', 'value': fqdn, 'message': 'FQDN выглядит корректно' if fqdn_ok else 'Для AD-DC требуется полноценный FQDN, не .local'},
        'static_network': {'ok': static_ok, 'severity': 'blocker', 'value': preferred_role or active_roles, 'message': f'Статический IPv4 доступен на {preferred_role.upper()}' if static_ok else 'Для AD-DC нужен хотя бы один активный интерфейс со статическим IPv4'},
        'time_sync': {'ok': ntp_ok, 'severity': 'blocker', 'value': ntp_out.strip() if ntp_rc == 0 else 'unknown', 'message': 'Синхронизация времени подтверждена' if ntp_ok else 'Синхронизация времени не подтверждена'},
        'packages': {'ok': packages_ok, 'severity': 'blocker', 'value': packages, 'message': 'Все пакеты доступны в APT' if packages_ok else 'Не все обязательные пакеты Samba AD-DC доступны в APT'},
        'disk_space': {'ok': disk_ok, 'severity': 'blocker', 'value': f'{free_gb} GiB free', 'message': 'Свободного места достаточно' if disk_ok else 'Для подготовки AD-DC требуется не менее 2 GiB свободного места'},
        'dns_53': {'ok': not dns_owners, 'severity': 'warning', 'value': dns_owners, 'message': 'TCP/UDP 53 свободен' if not dns_owners else 'Порт 53 занят; перед provisioning потребуется управляемый DNS cutover'},
        'kerberos_88': {'ok': not kerberos_owners, 'severity': 'warning', 'value': kerberos_owners, 'message': 'Порт 88 свободен' if not kerberos_owners else 'Порт 88 уже занят'},
        'ldap_389': {'ok': not ldap_owners, 'severity': 'warning', 'value': ldap_owners, 'message': 'Порт 389 свободен' if not ldap_owners else 'Порт 389 уже занят'},
        'smb_445': {'ok': not smb_owners, 'severity': 'warning', 'value': smb_owners, 'message': 'Порт 445 свободен' if not smb_owners else 'Порт 445 уже занят'},
        'existing_samba': {'ok': not samba_conf_exists, 'severity': 'warning', 'value': '/etc/samba/smb.conf' if samba_conf_exists else 'none', 'message': 'Существующая Samba-конфигурация не обнаружена' if not samba_conf_exists else 'Обнаружен /etc/samba/smb.conf; перед provisioning потребуется backup/import decision'},
    }

    blockers = [key for key, value in checks.items() if value['severity'] == 'blocker' and not value['ok']]
    warnings = [key for key, value in checks.items() if value['severity'] == 'warning' and not value['ok']]
    ready = not blockers
    details = {
        'network_source': source,
        'active_roles': active_roles,
        'preferred_ad_role': preferred_role,
        'interfaces': [x.get('name') for x in interfaces],
        'packages': packages,
        'systemd_resolved_active': resolved_active,
        'dnsmasq_active': dnsmasq_active,
        'resolv_conf_target': resolv_target,
        'samba_installed': samba_installed,
        'samba_version': samba_ver.strip() if samba_installed else '',
        'dns_backend': 'SAMBA_INTERNAL',
        'installation_enabled': False,
        'provisioning_enabled': False,
        'next_release_target': '1.0.11',
        'rollback_required': True,
    }
    payload = {
        'ready': ready,
        'hostname': hostname,
        'fqdn': fqdn,
        'checks': checks,
        'blockers': blockers,
        'warnings': warnings,
        'details': details,
        'checked_at': int(time.time()),
    }
    if persist:
        try:
            SAMBA_READINESS.parent.mkdir(parents=True, exist_ok=True)
            main._write_json(SAMBA_READINESS, payload)
        except Exception:
            pass
        try:
            with database.connect() as conn:
                row = conn.execute(
                    "INSERT INTO control_center.ad_dc_readiness_runs(hostname,fqdn,ready,blockers,warnings,checks,details) VALUES(%s,%s,%s,%s,%s,%s,%s) RETURNING id",
                    (hostname, fqdn, ready, Jsonb(blockers), Jsonb(warnings), Jsonb(checks), Jsonb(details)),
                ).fetchone()
                payload['readiness_id'] = row['id'] if row else None
        except Exception:
            payload['persistence'] = 'system-json'
    return payload


def _samba_plan(main):
    readiness = _samba_readiness(main, persist=True)
    network, _, _ = main._effective_network_config()
    role = readiness['details'].get('preferred_ad_role')
    cfg = network.get(role) or {} if role else {}
    planned_ip = cfg.get('ip') or ((cfg.get('live_ipv4') or [''])[0].split('/')[0] if cfg.get('live_ipv4') else '')
    plan = {
        'phase': 'dry-run-only',
        'target_release': '1.0.11',
        'provisioning_enabled': False,
        'required_packages': [x['package'] for x in readiness['details']['packages']],
        'network_role': role,
        'planned_ipv4': planned_ip,
        'dns_backend': 'SAMBA_INTERNAL',
        'pre_provision_backups': ['/etc/samba', '/etc/krb5.conf', '/etc/resolv.conf', '/etc/netplan/90-control-center.yaml', '/var/lib/samba'],
        'service_cutover_order': ['stop conflicting DNS service', 'install packages', 'backup configs', 'domain provision', 'DNS resolver cutover', 'service start', 'Kerberos/DNS/LDAP/SMB acceptance'],
        'rollback_order': ['stop samba-ad-dc', 'restore resolver/network configs', 'restore Samba backup if present', 'restart previous DNS/DHCP services', 'run health acceptance'],
        'acceptance': ['samba-tool domain info', 'samba-tool drs showrepl', 'kinit Administrator', 'host -t SRV _ldap._tcp', 'host -t SRV _kerberos._udp', 'smbclient -L localhost', 'timedatectl NTPSynchronized=yes'],
    }
    digest = hashlib.sha256(json.dumps(plan, ensure_ascii=False, sort_keys=True).encode()).hexdigest()
    result = {'ready': readiness['ready'], 'blockers': readiness['blockers'], 'warnings': readiness['warnings'], 'plan': plan, 'sha256': digest, 'created_at': int(time.time())}
    try:
        with database.connect() as conn:
            conn.execute(
                "INSERT INTO control_center.ad_dc_change_plans(plan_id,state,plan,rollback,checksum) VALUES(%s,'draft',%s,%s,%s) ON CONFLICT(plan_id) DO UPDATE SET plan=EXCLUDED.plan,rollback=EXCLUDED.rollback,checksum=EXCLUDED.checksum,updated_at=now()",
                (f'plan-{digest[:16]}', Jsonb(plan), Jsonb({'steps': plan['rollback_order']}), digest),
            )
    except Exception:
        pass
    return result


def _notification_item(event_id, source, title, severity, state, message, timestamp=0):
    return {
        'id': event_id,
        'source': source,
        'title': title,
        'state': state,
        'severity': severity,
        'message': message,
        'timestamp': int(timestamp or 0),
        'read': False,
    }


def register(app, main):
    main.APP_VERSION = VERSION
    main.APP_BUILD = BUILD

    legacy_effective = main._effective_network_config
    main._effective_network_config = lambda: _effective_network_110(main, legacy_effective)

    try:
        lic = main._license_info()
        database.upsert_local_node(edition=lic.get('edition', 'Home'), version=VERSION, build=BUILD)
    except Exception:
        pass

    previous_notifications = app.view_functions.get('notifications')

    def system_110():
        mem = main._meminfo()
        total = mem.get('MemTotal', 0)
        avail = mem.get('MemAvailable', 0)
        disk = shutil.disk_usage('/')
        return jsonify(
            version=VERSION,
            build=BUILD,
            edition=main._license_info()['edition'],
            hostname=socket.gethostname(),
            os=platform.platform(),
            kernel=platform.release(),
            architecture=platform.machine(),
            uptime_seconds=float(main._read('/proc/uptime', '0').split()[0] or 0),
            cpu_percent=main._cpu_usage(),
            cpu_count=os.cpu_count() or 0,
            memory={'total': total, 'used': max(total-avail, 0), 'percent': round(((total-avail)/total*100), 1) if total else 0},
            disk={'total': disk.total, 'used': disk.used, 'percent': round(disk.used/disk.total*100, 1) if disk.total else 0},
            storage=main._storage(),
            top_cpu=release_109._process_rows('cpu', 5),
            top_ram=release_109._process_rows('ram', 5),
            lan=_role_telemetry(main, 'lan'),
            wan=_role_telemetry(main, 'wan'),
            interfaces=len(main._interfaces()),
        )

    def network_config_110():
        if request.method == 'POST':
            try:
                cfg = _validate_network_110(main, request.get_json(silent=True) or {})
            except ValueError as exc:
                return jsonify(ok=False, error=str(exc)), 400
            main._write_json(main.NETWORK_PENDING, cfg)
            return jsonify(ok=True, message='Сетевая конфигурация проверена и передана на применение', config=cfg), 202
        config, interfaces, source = main._effective_network_config()
        return jsonify(config=config, source=source, status=main._read_json(main.NETWORK_STATUS, {}), interfaces=interfaces)

    def web_settings_110():
        runtime = _runtime_web()
        file_cfg = _file_web(main)
        status = main._read_json(WEB_STATUS, {})
        db_error = None
        db_cfg = {}
        try:
            db_cfg = {
                'port': int(database.get_setting('web.port', file_cfg['port'])),
                'ssl_enabled': bool(database.get_setting('web.ssl_enabled', file_cfg['ssl_enabled'])),
                'standard_port': bool(database.get_setting('web.standard_port', file_cfg['standard_port'])),
            }
        except Exception as exc:
            db_error = str(exc)

        if request.method == 'GET':
            return jsonify(
                port=file_cfg['port'],
                runtime_port=runtime['port'],
                ssl_enabled=file_cfg['ssl_enabled'],
                runtime_ssl=runtime['ssl_enabled'],
                standard_port=file_cfg['standard_port'],
                runtime_standard_port=runtime['standard_port'],
                scheme=runtime['scheme'],
                status=status,
                config=file_cfg,
                min_port=1024,
                max_port=65535,
                standard_http_port=80,
                standard_https_port=443,
                certificate=file_cfg['certificate'],
                persistence='runtime-file+postgresql' if not db_error else 'runtime-file',
                database_synced=not db_error and db_cfg == {'port': file_cfg['port'], 'ssl_enabled': file_cfg['ssl_enabled'], 'standard_port': file_cfg['standard_port']},
                database_error=db_error,
            )

        body = request.get_json(silent=True) or {}
        ssl_enabled = body.get('ssl_enabled')
        standard_port = body.get('standard_port')
        if not isinstance(ssl_enabled, bool) or not isinstance(standard_port, bool):
            return jsonify(ok=False, error='ssl_enabled и standard_port должны быть boolean'), 400
        if standard_port:
            port = 443 if ssl_enabled else 80
        else:
            try:
                port = int(body.get('port'))
            except Exception:
                return jsonify(ok=False, error='Пользовательский порт должен быть целым числом'), 400
            if port < 1024 or port > 65535:
                return jsonify(ok=False, error='Пользовательский порт должен быть от 1024 до 65535'), 400

        if port != runtime['port']:
            used, reason = _port_in_use(main, port)
            if used:
                return jsonify(ok=False, error=f'Порт {port} уже занят: {reason}'), 409

        if port == runtime['port'] and ssl_enabled == runtime['ssl_enabled'] and standard_port == runtime['standard_port']:
            return jsonify(ok=True, status='unchanged', port=port, ssl_enabled=ssl_enabled, standard_port=standard_port, message='Web-панель уже работает с указанными параметрами')

        job_id = f'web-runtime-{int(time.time() * 1000)}'
        main._write_json(WEB_PENDING, {
            'port': port,
            'previous_port': runtime['port'],
            'ssl_enabled': ssl_enabled,
            'previous_ssl_enabled': runtime['ssl_enabled'],
            'standard_port': standard_port,
            'previous_standard_port': runtime['standard_port'],
            'job_id': job_id,
            'requested_at': int(time.time()),
        })
        try:
            database.set_setting('web.port.requested', port)
            database.set_setting('web.ssl.requested', ssl_enabled)
            database.set_setting('web.standard.requested', standard_port)
            database.upsert_job(job_id, 'web-runtime-change', 'queued', payload={'port': port, 'ssl_enabled': ssl_enabled, 'standard_port': standard_port, 'previous': runtime})
        except Exception:
            pass
        return jsonify(
            ok=True,
            status='pending',
            port=port,
            ssl_enabled=ssl_enabled,
            standard_port=standard_port,
            scheme='https' if ssl_enabled else 'http',
            message='Web runtime передан root-helper. Результат появится в уведомлениях.',
            persistence='runtime-file',
        ), 202

    def hostname_settings_110():
        current = socket.gethostname()
        status = main._read_json(HOSTNAME_STATUS, {})
        if request.method == 'GET':
            return jsonify(hostname=current, status=status)
        body = request.get_json(silent=True) or {}
        new_name = str(body.get('hostname') or '').strip().lower()
        if not re.fullmatch(r'[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?', new_name):
            return jsonify(ok=False, error='Имя компьютера: 1–63 символа, латинские буквы, цифры и дефис; без дефиса в начале/конце'), 400
        if new_name == current.lower():
            return jsonify(ok=True, status='unchanged', hostname=current, message='Имя компьютера уже установлено')
        main._write_json(HOSTNAME_PENDING, {'hostname': new_name, 'previous_hostname': current, 'requested_at': int(time.time()), 'request_id': f'hostname-{int(time.time()*1000)}'})
        return jsonify(ok=True, status='pending', hostname=new_name, message='Переименование передано root-helper. Результат появится в уведомлениях.'), 202

    def samba_readiness_110():
        return jsonify(_samba_readiness(main, persist=True))

    def samba_plan_110():
        return jsonify(_samba_plan(main))

    def market_110():
        payload = release_108._market_payload(main)
        readiness = main._read_json(SAMBA_READINESS, {})
        for item in payload.get('items', []):
            if item.get('id') == 'samba':
                ready = bool(readiness.get('ready'))
                blockers = readiness.get('blockers') or []
                detail = 'Production provisioning отключён в 1.0.10. Выполните readiness/plan; включение планируется в 1.0.11.'
                if blockers:
                    detail = 'Подготовка AD-DC: блокеры — ' + ', '.join(blockers)
                item.update({
                    'name': 'Samba AD-DC',
                    'description': 'Домен Active Directory, Kerberos, DNS и файловые сервисы',
                    'state': 'prepared',
                    'installable': False,
                    'status': {
                        'code': 'prepared',
                        'label': 'Готово к проверке' if ready else 'Подготовка',
                        'detail': detail,
                        'timestamp': int(readiness.get('checked_at') or 0),
                    },
                })
        return jsonify(payload)

    def notifications_110():
        try:
            base_response = previous_notifications() if previous_notifications else jsonify(items=[])
            payload = base_response.get_json() or {}
            items = list(payload.get('items') or [])
        except Exception:
            items = []

        now = int(time.time())
        try:
            database.health()
            db_ok = True
        except Exception as exc:
            db_ok = False
            items.append(_notification_item('postgresql-unavailable', 'database', 'PostgreSQL', 'error', 'unavailable', f'PostgreSQL недоступен: {exc}', now))

        web_status = main._read_json(WEB_STATUS, {})
        if web_status.get('state') in {'rollback', 'rejected', 'error', 'failed'}:
            items.append(_notification_item('web-runtime-error-' + str(web_status.get('timestamp') or 0), 'web', 'Web-панель', 'error', str(web_status.get('state')), str(web_status.get('message') or 'Ошибка Web runtime'), web_status.get('timestamp')))
        elif web_status.get('state') == 'applied':
            items.append(_notification_item('web-runtime-applied-' + str(web_status.get('timestamp') or 0), 'web', 'Web-панель', 'ok', 'applied', str(web_status.get('message') or 'Web runtime применён'), web_status.get('timestamp')))

        host_status = main._read_json(HOSTNAME_STATUS, {})
        if host_status.get('state') in {'applied', 'rollback', 'rejected', 'error'}:
            items.append(_notification_item('hostname-' + str(host_status.get('timestamp') or 0), 'hostname', 'Имя компьютера', 'ok' if host_status.get('state') == 'applied' else 'error', str(host_status.get('state')), str(host_status.get('message') or host_status.get('state')), host_status.get('timestamp')))

        readiness = main._read_json(SAMBA_READINESS, {})
        if readiness:
            blockers = readiness.get('blockers') or []
            warnings = readiness.get('warnings') or []
            if blockers:
                items.append(_notification_item('samba-readiness-' + str(readiness.get('checked_at') or 0), 'samba', 'Samba AD-DC', 'error', 'not-ready', 'Readiness: блокеры — ' + ', '.join(blockers), readiness.get('checked_at')))
            elif warnings:
                items.append(_notification_item('samba-readiness-' + str(readiness.get('checked_at') or 0), 'samba', 'Samba AD-DC', 'info', 'ready-with-warnings', 'Readiness пройден, предупреждения — ' + ', '.join(warnings), readiness.get('checked_at')))
            else:
                items.append(_notification_item('samba-readiness-' + str(readiness.get('checked_at') or 0), 'samba', 'Samba AD-DC', 'ok', 'ready', 'Readiness пройден. Production provisioning остаётся отключён до следующего релиза.', readiness.get('checked_at')))

        dedup = {}
        for item in items:
            dedup[item.get('id') or hashlib.sha256(repr(item).encode()).hexdigest()[:20]] = item
        items = sorted(dedup.values(), key=lambda x: x.get('timestamp', 0), reverse=True)[:200]

        if db_ok:
            try:
                database.sync_notifications(items)
                rows = database.list_notifications(200)
                return jsonify(items=rows, count=len(rows), unread=sum(1 for x in rows if not x.get('read')), generated_at=now, persistence='postgresql')
            except Exception:
                pass
        for item in items:
            item.setdefault('read', False)
        return jsonify(items=items, count=len(items), unread=sum(1 for x in items if not x.get('read')), generated_at=now, persistence='degraded')

    app.view_functions['system_info'] = system_110
    app.view_functions['network_config'] = network_config_110
    app.view_functions['web_settings_107'] = web_settings_110
    app.view_functions['market'] = market_110
    app.view_functions['notifications'] = notifications_110
    if 'samba_preflight_109' in app.view_functions:
        app.view_functions['samba_preflight_109'] = samba_readiness_110

    app.add_url_rule('/api/settings/hostname', 'hostname_settings_110', hostname_settings_110, methods=['GET', 'POST'])
    app.add_url_rule('/api/samba/readiness', 'samba_readiness_110', samba_readiness_110, methods=['GET', 'POST'])
    app.add_url_rule('/api/samba/plan', 'samba_plan_110', samba_plan_110, methods=['GET', 'POST'])

    static_dir = Path(app.root_path) / 'static'

    def release_assets_110():
        if request.method != 'GET':
            return None
        if request.path == '/static/app.js':
            try:
                payload = (static_dir / 'app.js').read_text() + '\n\n' + (static_dir / 'release-108.js').read_text() + '\n\n' + (static_dir / 'release-110.js').read_text()
                return Response(payload, mimetype='application/javascript')
            except Exception:
                return None
        if request.path == '/static/app.css':
            try:
                payload = (static_dir / 'app.css').read_text() + '\n\n' + (static_dir / 'release-108.css').read_text() + '\n\n' + (static_dir / 'release-110.css').read_text()
                return Response(payload, mimetype='text/css')
            except Exception:
                return None
        return None

    app.before_request_funcs.setdefault(None, []).insert(0, release_assets_110)
