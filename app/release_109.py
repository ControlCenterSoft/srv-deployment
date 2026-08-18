from __future__ import annotations

import os
import re
import socket
import subprocess
import time
from pathlib import Path

from flask import jsonify, request
from psycopg.types.json import Jsonb

import database
import release_108

VERSION = '1.0.9'
BUILD = '20260819.3'
WEB_PENDING = Path('/var/lib/control-center/web-pending.json')
WEB_STATUS = Path('/var/lib/control-center-system/web-status.json')
WEB_CONFIG = Path('/var/lib/control-center-system/web-config.json')


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


def _port_in_use(main, port):
    runtime = _runtime_web()
    if port == runtime['port']:
        return False, ''
    rc, out, err = main._run(['ss', '-H', '-ltn'], 3)
    if rc != 0:
        return False, err
    needle = f':{port}'
    for line in out.splitlines():
        local = line.split()[3] if len(line.split()) >= 4 else ''
        if local.endswith(needle):
            return True, line.strip()
    return False, ''


def _process_rows(sort_key, limit=5):
    flag = '-%cpu' if sort_key == 'cpu' else '-%mem'
    try:
        out = subprocess.check_output(
            ['ps', '-eo', 'pid=,comm=,%cpu=,%mem=', f'--sort={flag}'],
            text=True,
            timeout=3,
        )
        rows = []
        for line in out.splitlines():
            p = line.split(None, 3)
            if len(p) != 4:
                continue
            rows.append({
                'pid': int(p[0]),
                'name': p[1],
                'cpu_percent': float(p[2]),
                'memory_percent': float(p[3]),
            })
            if len(rows) >= limit:
                break
        return rows
    except Exception:
        return []


def _role_telemetry(main, role):
    config, interfaces, _ = main._effective_network_config()
    name = (config.get(role) or {}).get('interface')
    row = {x['name']: x for x in interfaces}.get(name)
    return {
        'interface': name or '',
        'state': row['state'] if row else 'unassigned',
        'rx_bytes': row['rx_bytes'] if row else 0,
        'tx_bytes': row['tx_bytes'] if row else 0,
        'ipv4': row['ipv4'] if row else [],
    }


def _samba_preflight(main):
    hostname = socket.gethostname()
    try:
        fqdn = socket.getfqdn() or hostname
    except Exception:
        fqdn = hostname
    network, interfaces, source = main._effective_network_config()
    lan = network.get('lan') or {}
    lan_static = bool(lan.get('interface')) and lan.get('method') == 'static' and bool(lan.get('ip') or lan.get('live_ipv4'))
    fqdn_ok = '.' in fqdn and not fqdn.endswith('.local')
    rc, ntp_out, _ = main._run(['timedatectl', 'show', '-p', 'NTPSynchronized', '--value'], 3)
    ntp_ok = rc == 0 and ntp_out.strip().lower() == 'yes'
    rc, listen_out, _ = main._run(['ss', '-H', '-lntup'], 3)
    port53 = []
    if rc == 0:
        for line in listen_out.splitlines():
            if re.search(r'[:.]53\s', line) or re.search(r':53$', line.split()[4] if len(line.split()) > 4 else ''):
                port53.append(line.strip()[:300])
    dns_ready = not port53
    samba_rc, samba_out, _ = main._run(['samba', '--version'], 3)
    package_installed = samba_rc == 0
    checks = {
        'fqdn': {'ok': fqdn_ok, 'value': fqdn, 'message': 'FQDN корректен' if fqdn_ok else 'Требуется полноценное доменное имя сервера'},
        'lan_static': {'ok': lan_static, 'value': lan.get('interface') or '', 'message': 'LAN имеет статическую конфигурацию' if lan_static else 'Для AD-DC рекомендуется статический LAN IPv4'},
        'time_sync': {'ok': ntp_ok, 'value': ntp_out.strip() if rc == 0 else 'unknown', 'message': 'Синхронизация времени активна' if ntp_ok else 'Синхронизация времени не подтверждена'},
        'dns_port_53': {'ok': dns_ready, 'value': port53, 'message': 'Порт 53 свободен для будущего AD DNS' if dns_ready else 'Порт 53 уже занят; потребуется согласовать DNS runtime'},
        'samba_package': {'ok': True, 'value': samba_out.strip() if package_installed else 'not-installed', 'message': 'Samba уже установлен' if package_installed else 'Samba пока не установлен — это ожидаемо для этапа подготовки'},
    }
    ready = fqdn_ok and lan_static and ntp_ok
    details = {
        'network_source': source,
        'interfaces': [x.get('name') for x in interfaces],
        'planned_dns_backend': 'SAMBA_INTERNAL',
        'installation_enabled': False,
        'package_installed': package_installed,
    }
    try:
        with database.connect() as conn:
            conn.execute(
                "INSERT INTO control_center.ad_dc_preflight_runs(hostname,fqdn,ready,checks,details) VALUES(%s,%s,%s,%s,%s)",
                (hostname, fqdn, ready, Jsonb(checks), Jsonb(details)),
            )
    except Exception:
        pass
    return {'ready': ready, 'hostname': hostname, 'fqdn': fqdn, 'checks': checks, 'details': details, 'checked_at': int(time.time())}


def register(app, main):
    main.APP_VERSION = VERSION
    main.APP_BUILD = BUILD
    try:
        lic = main._license_info()
        database.upsert_local_node(edition=lic.get('edition', 'Home'), version=VERSION, build=BUILD)
        database.set_setting_if_missing('web.ssl_enabled', False)
        database.set_setting_if_missing('web.standard_port', False)
    except Exception:
        pass

    def system_109():
        mem = main._meminfo()
        total = mem.get('MemTotal', 0)
        avail = mem.get('MemAvailable', 0)
        disk = __import__('shutil').disk_usage('/')
        return jsonify(
            version=VERSION,
            build=BUILD,
            edition=main._license_info()['edition'],
            hostname=socket.gethostname(),
            os=__import__('platform').platform(),
            kernel=__import__('platform').release(),
            architecture=__import__('platform').machine(),
            uptime_seconds=float(main._read('/proc/uptime', '0').split()[0] or 0),
            cpu_percent=main._cpu_usage(),
            cpu_count=os.cpu_count() or 0,
            memory={
                'total': total,
                'used': max(total - avail, 0),
                'percent': round(((total - avail) / total * 100), 1) if total else 0,
            },
            disk={'total': disk.total, 'used': disk.used, 'percent': round(disk.used / disk.total * 100, 1) if disk.total else 0},
            storage=main._storage(),
            top_cpu=_process_rows('cpu', 5),
            top_ram=_process_rows('ram', 5),
            lan=_role_telemetry(main, 'lan'),
            wan=_role_telemetry(main, 'wan'),
            interfaces=len(main._interfaces()),
        )

    def market_109():
        payload = release_108._market_payload(main)
        for item in payload.get('items', []):
            if item.get('id') == 'samba':
                item.update({
                    'name': 'Samba AD-DC',
                    'description': 'Домен Active Directory, DNS и файловые сервисы',
                    'state': 'prepared',
                    'installable': False,
                    'status': {
                        'code': 'prepared',
                        'label': 'Подготовлено',
                        'detail': 'PostgreSQL schema и preflight API готовы. Установка/провижининг AD-DC будет включена отдельным релизом.',
                        'timestamp': 0,
                    },
                })
        return jsonify(payload)

    def web_settings_109():
        runtime = _runtime_web()
        status = main._read_json(WEB_STATUS, {})
        config = main._read_json(WEB_CONFIG, {})
        try:
            saved_port = int(database.get_setting('web.port', runtime['port']))
            saved_ssl = bool(database.get_setting('web.ssl_enabled', runtime['ssl_enabled']))
            saved_standard = bool(database.get_setting('web.standard_port', runtime['standard_port']))
        except Exception as exc:
            if request.method == 'POST':
                return jsonify(ok=False, error=f'PostgreSQL недоступен: {exc}'), 503
            saved_port = int(config.get('port', runtime['port']) or runtime['port'])
            saved_ssl = bool(config.get('ssl_enabled', runtime['ssl_enabled']))
            saved_standard = bool(config.get('standard_port', runtime['standard_port']))
        if request.method == 'GET':
            return jsonify(
                port=saved_port,
                runtime_port=runtime['port'],
                ssl_enabled=saved_ssl,
                runtime_ssl=runtime['ssl_enabled'],
                standard_port=saved_standard,
                runtime_standard_port=runtime['standard_port'],
                scheme='https' if runtime['ssl_enabled'] else 'http',
                status=status,
                config=config,
                min_port=1024,
                max_port=65535,
                standard_http_port=80,
                standard_https_port=443,
                certificate=config.get('certificate', 'self-signed' if runtime['ssl_enabled'] else 'none'),
                persistence='postgresql',
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
            database.set_setting('web.port', port)
            database.set_setting('web.ssl_enabled', ssl_enabled)
            database.set_setting('web.standard_port', standard_port)
            return jsonify(ok=True, status='unchanged', port=port, ssl_enabled=ssl_enabled, message='Web-панель уже работает с указанными параметрами')
        job_id = f'web-runtime-{int(time.time())}'
        database.set_setting('web.port.requested', port)
        database.set_setting('web.ssl.requested', ssl_enabled)
        database.set_setting('web.standard.requested', standard_port)
        database.upsert_job(job_id, 'web-runtime-change', 'queued', payload={
            'port': port,
            'ssl_enabled': ssl_enabled,
            'standard_port': standard_port,
            'previous': runtime,
        })
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
        return jsonify(
            ok=True,
            status='pending',
            port=port,
            ssl_enabled=ssl_enabled,
            standard_port=standard_port,
            scheme='https' if ssl_enabled else 'http',
            message=f"Web-панель будет перезапущена: {'https' if ssl_enabled else 'http'}://SERVER:{port}",
        ), 202

    def samba_preflight_109():
        return jsonify(_samba_preflight(main))

    app.view_functions['system_info'] = system_109
    app.view_functions['market'] = market_109
    app.view_functions['web_settings_107'] = web_settings_109
    app.add_url_rule('/api/samba/preflight', 'samba_preflight_109', samba_preflight_109, methods=['GET', 'POST'])
