from flask import Flask, jsonify, render_template, request
import os, platform, socket, time, shutil, pwd, grp, json, subprocess, urllib.request, ipaddress, hashlib, re
from pathlib import Path

APP_VERSION = '1.0.7'
APP_BUILD = '20260818.2'
STATE_DIR = Path('/var/lib/control-center')
SYSTEM_STATE_DIR = Path('/var/lib/control-center-system')
LICENSE_DIR = Path('/var/lib/control-center-license')
SETTINGS_FILE = STATE_DIR / 'update-settings.json'
STATUS_FILE = SYSTEM_STATE_DIR / 'update-status.json'
OS_UPDATE_SETTINGS = STATE_DIR / 'os-update-settings.json'
OS_UPDATE_STATUS = SYSTEM_STATE_DIR / 'os-update-status.json'
OS_UPDATE_NOW = STATE_DIR / 'os-update-now'
LICENSE_FILE = LICENSE_DIR / 'license.json'
LICENSE_PENDING = STATE_DIR / 'license-pending.json'
LICENSE_STATUS = SYSTEM_STATE_DIR / 'license-status.json'
NETWORK_FILE = SYSTEM_STATE_DIR / 'network-config.json'
NETWORK_PENDING = STATE_DIR / 'network-pending.json'
NETWORK_STATUS = SYSTEM_STATE_DIR / 'network-status.json'
MODULE_DIR = SYSTEM_STATE_DIR / 'modules'
DHCP_STATE = MODULE_DIR / 'dhcp.json'
MARKET_PENDING = STATE_DIR / 'market-pending.json'
MARKET_STATUS = SYSTEM_STATE_DIR / 'market-status.json'
DHCP_CONFIG = SYSTEM_STATE_DIR / 'dhcp-config.json'
DHCP_PENDING = STATE_DIR / 'dhcp-pending.json'
DHCP_STATUS = SYSTEM_STATE_DIR / 'dhcp-status.json'
DHCP_CONF = Path('/etc/dnsmasq.d/control-center-dhcp.conf')
NETPLAN_CONF = Path('/etc/netplan/90-control-center.yaml')
DEPLOYMENT_URL = 'https://raw.githubusercontent.com/filosoff31/srv-deployment/main/deployment.json'
DEFAULT_SETTINGS = {'automatic_updates': True, 'interval_minutes': 60, 'channel': 'production'}
DEFAULT_OS_UPDATES = {'automatic_updates': False, 'interval_minutes': 1440}
app = Flask(__name__, template_folder='templates', static_folder='static')


def _read(path, default=''):
    try:
        return Path(path).read_text().strip()
    except Exception:
        return default


def _read_json(path, default):
    try:
        data = json.loads(Path(path).read_text())
        return data if isinstance(data, dict) else default.copy()
    except Exception:
        return default.copy()


def _write_json(path, data):
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = Path(str(path) + '.tmp')
    tmp.write_text(json.dumps(data, ensure_ascii=False, indent=2) + '\n')
    tmp.replace(path)


def _run(args, timeout=3):
    try:
        p = subprocess.run(args, text=True, capture_output=True, timeout=timeout, check=False)
        return p.returncode, (p.stdout or '').strip(), (p.stderr or '').strip()
    except Exception as exc:
        return 127, '', str(exc)


def _normalized_update_settings():
    raw = _read_json(SETTINGS_FILE, DEFAULT_SETTINGS)
    legacy = {'hourly': 60, 'daily': 1440, 'weekly': 10080}
    try:
        interval = int(raw.get('interval_minutes', legacy.get(raw.get('frequency'), 60)))
    except Exception:
        interval = 60
    return {'automatic_updates': bool(raw.get('automatic_updates', True)), 'interval_minutes': max(5, min(interval, 10080)), 'channel': 'production'}


def _normalized_os_update_settings():
    raw = _read_json(OS_UPDATE_SETTINGS, DEFAULT_OS_UPDATES)
    try:
        interval = int(raw.get('interval_minutes', 1440))
    except Exception:
        interval = 1440
    return {'automatic_updates': bool(raw.get('automatic_updates', False)), 'interval_minutes': max(60, min(interval, 10080))}


def _device_id():
    return hashlib.sha256(_read('/etc/machine-id', 'unknown').encode()).hexdigest()[:24]


def _license_info():
    lic = _read_json(LICENSE_FILE, {})
    device = _device_id()
    if lic.get('activated') and lic.get('edition') == 'Professional' and lic.get('device_id') == device:
        try:
            exp = lic.get('expires_at')
            if exp is None or int(exp) > int(time.time()):
                return {'edition': 'Professional', 'activated': True, 'device_id': device, 'license_id': lic.get('license_id', ''), 'expires_at': exp}
        except Exception:
            pass
    return {'edition': 'Home', 'activated': False, 'device_id': device, 'license_id': '', 'expires_at': None}


def _meminfo():
    data = {}
    for line in _read('/proc/meminfo').splitlines():
        if ':' not in line:
            continue
        k, v = line.split(':', 1)
        try:
            data[k] = int(v.strip().split()[0]) * 1024
        except Exception:
            pass
    return data


def _cpu_usage():
    try:
        a = [int(x) for x in _read('/proc/stat').splitlines()[0].split()[1:]]
        total, idle = sum(a), a[3] + (a[4] if len(a) > 4 else 0)
        time.sleep(.08)
        b = [int(x) for x in _read('/proc/stat').splitlines()[0].split()[1:]]
        dt = sum(b) - total
        di = (b[3] + (b[4] if len(b) > 4 else 0)) - idle
        return round((1 - di / dt) * 100, 1) if dt else 0
    except Exception:
        return 0


def _top_processes():
    try:
        out = subprocess.check_output(['ps', '-eo', 'pid=,comm=,%cpu=,%mem=', '--sort=-%cpu'], text=True, timeout=2)
        rows = []
        for line in out.splitlines()[:3]:
            p = line.split(None, 3)
            if len(p) == 4:
                rows.append({'pid': int(p[0]), 'name': p[1], 'cpu_percent': float(p[2]), 'memory_percent': float(p[3])})
        return rows
    except Exception:
        return []


def _storage():
    try:
        out = subprocess.check_output(['df', '-B1', '-P', '-x', 'tmpfs', '-x', 'devtmpfs', '-x', 'squashfs'], text=True, timeout=3)
        rows = []
        for line in out.splitlines()[1:]:
            p = line.split()
            if len(p) < 6:
                continue
            try:
                rows.append({'device': p[0], 'mount': p[5], 'total': int(p[1]), 'used': int(p[2]), 'available': int(p[3]), 'percent': float(p[4].rstrip('%'))})
            except Exception:
                pass
        rows.sort(key=lambda x: (x['mount'] != '/', x['mount']))
        return rows[:8]
    except Exception:
        return []


def _ipv4_for(name):
    rc, out, _ = _run(['ip', '-j', '-4', 'addr', 'show', 'dev', name], 2)
    if rc != 0 or not out:
        return []
    try:
        rows = json.loads(out)
        return [x['local'] + '/' + str(x['prefixlen']) for r in rows for x in r.get('addr_info', []) if x.get('scope') in ('global', 'host')]
    except Exception:
        return []


def _route_map():
    rc, out, _ = _run(['ip', '-j', '-4', 'route', 'show'], 2)
    result = {}
    if rc != 0 or not out:
        return result
    try:
        for row in json.loads(out):
            dev = row.get('dev')
            if not dev:
                continue
            entry = result.setdefault(dev, {'gateway': '', 'default_route': False, 'metric': row.get('metric')})
            if row.get('dst') == 'default':
                entry['default_route'] = True
                entry['gateway'] = row.get('gateway') or ''
                entry['metric'] = row.get('metric')
    except Exception:
        pass
    return result


def _dns_for(name):
    rc, out, _ = _run(['resolvectl', 'dns', name], 2)
    if rc == 0 and ':' in out:
        return [x for x in out.split(':', 1)[1].split() if re.fullmatch(r'\d+\.\d+\.\d+\.\d+', x)]
    return []


def _interfaces():
    items, routes = [], _route_map()
    base = Path('/sys/class/net')
    for p in sorted(base.iterdir()) if base.exists() else []:
        if p.name == 'lo':
            continue
        kind = 'wifi' if (p / 'wireless').exists() else ('ethernet' if (p / 'device').exists() else 'virtual')
        speed = _read(p / 'speed', '')
        route = routes.get(p.name, {})
        items.append({
            'name': p.name,
            'kind': kind,
            'state': _read(p / 'operstate', 'unknown'),
            'carrier': _read(p / 'carrier', ''),
            'mac': _read(p / 'address', ''),
            'mtu': _read(p / 'mtu', ''),
            'speed_mbps': int(speed) if str(speed).isdigit() and int(speed) > 0 else None,
            'rx_bytes': int(_read(p / 'statistics/rx_bytes', '0') or 0),
            'tx_bytes': int(_read(p / 'statistics/tx_bytes', '0') or 0),
            'ipv4': _ipv4_for(p.name),
            'gateway': route.get('gateway', ''),
            'default_route': bool(route.get('default_route')),
            'dns': _dns_for(p.name),
        })
    return items


def _parse_netplan_config():
    text = _read(NETPLAN_CONF)
    result = {}
    if not text:
        return result
    current = None
    block = []
    blocks = {}
    for line in text.splitlines():
        m = re.match(r'^    ([A-Za-z0-9_.:-]+):\s*$', line)
        if m:
            if current:
                blocks[current] = '\n'.join(block)
            current, block = m.group(1), []
        elif current:
            block.append(line)
    if current:
        blocks[current] = '\n'.join(block)
    for iface, body in blocks.items():
        dhcp = bool(re.search(r'^      dhcp4:\s*true\s*$', body, re.M))
        cfg = {'interface': iface, 'method': 'dhcp' if dhcp else 'static'}
        if not dhcp:
            am = re.search(r'^      addresses:\s*\[([^\]]+)\]', body, re.M)
            if am:
                first = am.group(1).split(',')[0].strip()
                try:
                    addr = ipaddress.IPv4Interface(first)
                    cfg['ip'], cfg['mask'] = str(addr.ip), addr.network.prefixlen
                except Exception:
                    pass
            gm = re.search(r'^\s+via:\s*([^\s#]+)', body, re.M)
            if gm:
                cfg['gateway'] = gm.group(1).strip()
            dm = re.search(r'^        addresses:\s*\[([^\]]*)\]', body, re.M)
            if dm:
                cfg['dns'] = [x.strip() for x in dm.group(1).split(',') if x.strip()]
        result[iface] = cfg
    return result


def _effective_network_config():
    stored = _read_json(NETWORK_FILE, {})
    parsed = _parse_netplan_config()
    interfaces = _interfaces()
    by_name = {x['name']: x for x in interfaces}
    roles = {}
    for role in ('wan', 'lan'):
        cfg = dict(stored.get(role) or {})
        iface = cfg.get('interface')
        if iface and iface in parsed:
            merged = dict(parsed[iface]); merged.update({k: v for k, v in cfg.items() if v not in ('', None, [])})
            cfg = merged
        roles[role] = cfg
    if not roles['wan'].get('interface'):
        default_iface = next((x['name'] for x in interfaces if x.get('default_route')), '')
        if default_iface:
            roles['wan'] = dict(parsed.get(default_iface) or {'interface': default_iface, 'method': 'dhcp'})
    if not roles['lan'].get('interface'):
        used = roles['wan'].get('interface')
        candidate = next((x['name'] for x in interfaces if x['name'] != used and x['name'] in parsed), '')
        if candidate:
            roles['lan'] = dict(parsed[candidate])
    for role, cfg in roles.items():
        live = by_name.get(cfg.get('interface'), {})
        cfg['live_ipv4'] = live.get('ipv4', [])
        cfg['live_gateway'] = live.get('gateway', '')
        cfg['live_dns'] = live.get('dns', [])
        cfg['link_state'] = live.get('state', 'unknown')
    source = 'stored' if stored else ('netplan/live' if any(roles[x].get('interface') for x in roles) else 'none')
    return roles, interfaces, source


def _wan_telemetry():
    config, interfaces, _ = _effective_network_config()
    name = (config.get('wan') or {}).get('interface')
    row = {x['name']: x for x in interfaces}.get(name)
    return {'interface': name or '', 'state': row['state'] if row else 'unassigned', 'rx_bytes': row['rx_bytes'] if row else 0, 'tx_bytes': row['tx_bytes'] if row else 0, 'ipv4': row['ipv4'] if row else []}


def _mask_to_prefix(mask):
    value = str(mask or '').strip().lstrip('/')
    if value.isdigit():
        prefix = int(value)
        if 0 <= prefix <= 32:
            return prefix
        raise ValueError('Маска CIDR должна быть от 0 до 32')
    try:
        return ipaddress.IPv4Network('0.0.0.0/' + value).prefixlen
    except Exception:
        raise ValueError('Некорректная маска сети')


def _validate_network(body):
    if not isinstance(body, dict):
        raise ValueError('Некорректный запрос')
    known = {x['name'] for x in _interfaces()}
    result, used, nets = {'wan': {}, 'lan': {}}, set(), []
    for role in ('wan', 'lan'):
        src = body.get(role) or {}
        iface = str(src.get('interface') or '').strip()
        method = str(src.get('method') or 'dhcp').lower()
        if iface not in known:
            raise ValueError(f'{role.upper()}: выберите существующий интерфейс')
        if iface in used:
            raise ValueError('WAN и LAN должны использовать разные интерфейсы')
        used.add(iface)
        if method not in ('dhcp', 'static'):
            raise ValueError(f'{role.upper()}: неизвестный режим адресации')
        dst = {'interface': iface, 'method': method}
        if method == 'static':
            ip = str(src.get('ip') or '').strip()
            prefix = _mask_to_prefix(src.get('mask'))
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
            if gateway:
                try:
                    gw = ipaddress.IPv4Address(gateway)
                except Exception:
                    raise ValueError(f'{role.upper()}: некорректный шлюз')
                if gw not in addr.network or gw == addr.ip:
                    raise ValueError(f'{role.upper()}: некорректный шлюз для выбранной подсети')
            clean = []
            for d in dns:
                try:
                    clean.append(str(ipaddress.IPv4Address(d)))
                except Exception:
                    raise ValueError(f'{role.upper()}: некорректный DNS {d}')
            if role == 'wan' and not gateway:
                raise ValueError('WAN Static: укажите шлюз')
            if not clean:
                raise ValueError(f'{role.upper()} Static: укажите DNS')
            nets.append(addr.network)
            dst.update({'ip': str(addr.ip), 'mask': prefix, 'gateway': gateway, 'dns': clean})
        result[role] = dst
    if len(nets) == 2 and nets[0].overlaps(nets[1]):
        raise ValueError('Подсети WAN и LAN не должны пересекаться')
    return result


def _dhcp_installed():
    return bool(_read_json(DHCP_STATE, {}).get('installed', False))


def _parse_dhcp_config():
    text = _read(DHCP_CONF)
    cfg, extras = {}, []
    if not text:
        return cfg
    for raw in text.splitlines():
        line = raw.strip()
        if not line or line.startswith('#'):
            continue
        if line.startswith('interface='):
            cfg['interface'] = line.split('=', 1)[1].strip()
        elif line.startswith('dhcp-range='):
            parts = [x.strip() for x in line.split('=', 1)[1].split(',')]
            if len(parts) >= 4:
                cfg['range_start'], cfg['range_end'] = parts[0], parts[1]
                try:
                    cfg['mask'] = _mask_to_prefix(parts[2])
                except Exception:
                    pass
                lease = parts[3].lower()
                try:
                    cfg['lease_minutes'] = int(lease[:-1]) if lease.endswith('m') else int(lease)
                except Exception:
                    pass
        elif line.startswith('dhcp-option='):
            value = line.split('=', 1)[1]
            first, _, rest = value.partition(',')
            key = first.strip().lower()
            rest = rest.strip()
            if key in ('option:router', '3'):
                cfg['gateway'] = rest
            elif key in ('option:dns-server', '6'):
                cfg['dns'] = [x.strip() for x in rest.split(',') if x.strip()]
            elif key.isdigit() and rest:
                extras.append({'code': int(key), 'value': rest})
    cfg['extra_options'] = extras
    return cfg


def _effective_dhcp_config():
    stored = _read_json(DHCP_CONFIG, {})
    live = _parse_dhcp_config()
    result = dict(stored)
    if live:
        result.update({k: v for k, v in live.items() if v not in ('', None, []) or k == 'extra_options'})
    result.setdefault('extra_options', stored.get('extra_options', []))
    return result, ('dnsmasq' if live else ('stored' if stored else 'none'))


def _validate_extra_options(raw):
    if raw in (None, ''):
        return []
    if not isinstance(raw, list):
        raise ValueError('Дополнительные DHCP параметры должны быть списком')
    if len(raw) > 32:
        raise ValueError('Допускается не более 32 дополнительных DHCP параметров')
    managed = {1, 3, 6, 51}
    seen, result = set(), []
    for item in raw:
        if not isinstance(item, dict):
            raise ValueError('Некорректный дополнительный DHCP параметр')
        try:
            code = int(item.get('code'))
        except Exception:
            raise ValueError('Код DHCP параметра должен быть числом')
        if code < 1 or code > 254:
            raise ValueError('Код DHCP параметра: от 1 до 254')
        if code in managed:
            raise ValueError(f'DHCP option {code} управляется основными полями Control Center')
        if code in seen:
            raise ValueError(f'DHCP option {code} добавлен повторно')
        value = str(item.get('value') or '').strip()
        if not value or len(value) > 512 or any(ord(c) < 32 for c in value):
            raise ValueError(f'Некорректное значение DHCP option {code}')
        seen.add(code)
        result.append({'code': code, 'value': value})
    return sorted(result, key=lambda x: x['code'])


def _validate_dhcp(body):
    if not isinstance(body, dict):
        raise ValueError('Некорректный запрос')
    known = {x['name'] for x in _interfaces()}
    iface = str(body.get('interface') or '').strip()
    if iface not in known:
        raise ValueError('Выберите существующий интерфейс DHCP')
    try:
        start = ipaddress.IPv4Address(str(body.get('range_start') or '').strip())
        end = ipaddress.IPv4Address(str(body.get('range_end') or '').strip())
    except Exception:
        raise ValueError('Некорректный диапазон DHCP')
    prefix = _mask_to_prefix(body.get('mask'))
    net = ipaddress.IPv4Network(f'{start}/{prefix}', strict=False)
    if end not in net or int(end) < int(start):
        raise ValueError('Начало и конец диапазона должны находиться в одной подсети')
    if start in (net.network_address, net.broadcast_address) or end in (net.network_address, net.broadcast_address):
        raise ValueError('Диапазон DHCP не может включать адрес сети или broadcast')
    gateway = str(body.get('gateway') or '').strip()
    try:
        gw = ipaddress.IPv4Address(gateway)
    except Exception:
        raise ValueError('Некорректный шлюз DHCP')
    if gw not in net:
        raise ValueError('Шлюз DHCP должен находиться в той же подсети')
    if start <= gw <= end:
        raise ValueError('Шлюз DHCP не должен входить в выдаваемый диапазон')
    dns = body.get('dns') or []
    if isinstance(dns, str):
        dns = [x.strip() for x in dns.replace(';', ',').split(',') if x.strip()]
    clean = []
    for d in dns:
        try:
            clean.append(str(ipaddress.IPv4Address(d)))
        except Exception:
            raise ValueError(f'Некорректный DNS {d}')
    if not clean:
        raise ValueError('Укажите хотя бы один DNS')
    try:
        lease = int(body.get('lease_minutes', 720))
    except Exception:
        raise ValueError('Срок аренды должен быть числом минут')
    if lease < 10 or lease > 10080:
        raise ValueError('Срок аренды: от 10 до 10080 минут')
    return {'interface': iface, 'range_start': str(start), 'range_end': str(end), 'mask': prefix, 'gateway': str(gw), 'dns': clean, 'lease_minutes': lease, 'extra_options': _validate_extra_options(body.get('extra_options', []))}


def _service_status(unit):
    rc, out, _ = _run(['systemctl', 'show', unit, '--property=LoadState,ActiveState,SubState,UnitFileState,StateChangeTimestampUSec', '--value'], 2)
    values = out.splitlines() if rc == 0 else []
    while len(values) < 5:
        values.append('')
    load, active, sub, enabled, changed = values[:5]
    return {'unit': unit, 'load_state': load or 'unknown', 'active_state': active or 'unknown', 'sub_state': sub or 'unknown', 'enabled_state': enabled or 'unknown', 'running': active == 'active', 'state_changed': int(changed) // 1000000 if str(changed).isdigit() else 0}


def _dhcp_service_status():
    info = _service_status('control-center-dhcp-server.service')
    info['installed'] = _dhcp_installed()
    info['configured'] = bool(_parse_dhcp_config().get('range_start'))
    return info


def _check_dhcp_config():
    if not DHCP_CONF.exists():
        return {'ok': False, 'message': 'Конфигурационный файл DHCP отсутствует', 'output': '', 'checked_at': int(time.time())}
    binary = shutil.which('dnsmasq') or '/usr/sbin/dnsmasq'
    rc, out, err = _run([binary, '--test', f'--conf-file={DHCP_CONF}'], 5)
    text = '\n'.join(x for x in (out, err) if x).strip()
    return {'ok': rc == 0, 'message': 'Конфигурация DHCP корректна' if rc == 0 else 'Конфигурация DHCP содержит ошибку', 'output': text[-3000:], 'checked_at': int(time.time())}


def _remote_release():
    try:
        req = urllib.request.Request(DEPLOYMENT_URL, headers={'User-Agent': f'Control-Center/{APP_VERSION}'})
        data = json.loads(urllib.request.urlopen(req, timeout=4).read().decode())
        return {'available': True, 'release': data.get('release'), 'build': data.get('build'), 'channel': data.get('channel', 'production')}
    except Exception as exc:
        return {'available': False, 'error': str(exc)}


def _status_notification(source, title, path):
    data = _read_json(path, {})
    if not data:
        return None
    state = str(data.get('state') or data.get('result') or data.get('status') or 'info').lower()
    message = str(data.get('message') or '').strip()
    ts = int(data.get('timestamp') or data.get('last_run') or data.get('last_check') or 0)
    if not message and state == 'info':
        return None
    bad = state in {'error', 'failed', 'failure', 'rejected', 'rollback'} or any(x in message.lower() for x in ('ошиб', 'error', 'failed', 'отклон'))
    identity = f'{source}|{state}|{message}|{ts}'
    return {'id': hashlib.sha256(identity.encode()).hexdigest()[:20], 'source': source, 'title': title, 'state': state, 'severity': 'error' if bad else 'ok', 'message': message or state, 'timestamp': ts}


def _notifications():
    sources = [
        ('network', 'Сеть', NETWORK_STATUS),
        ('market', 'Маркет', MARKET_STATUS),
        ('dhcp', 'DHCP', DHCP_STATUS),
        ('license', 'Лицензия', LICENSE_STATUS),
        ('control-update', 'Обновление Control Center', STATUS_FILE),
        ('os-update', 'Обновление ОС и пакетов', OS_UPDATE_STATUS),
    ]
    items = [x for x in (_status_notification(*s) for s in sources) if x]
    service = _dhcp_service_status()
    if service.get('installed') and service.get('configured'):
        state = service.get('active_state', 'unknown')
        msg = 'DHCP Server работает' if service.get('running') else f'DHCP Server: {state}/{service.get("sub_state", "unknown")}'
        ts = int(service.get('state_changed') or 0)
        ident = f'dhcp-service|{state}|{service.get("sub_state")}|{ts}'
        items.append({'id': hashlib.sha256(ident.encode()).hexdigest()[:20], 'source': 'dhcp-service', 'title': 'DHCP Service', 'state': state, 'severity': 'ok' if service.get('running') else 'error', 'message': msg, 'timestamp': ts})
    items.sort(key=lambda x: x.get('timestamp', 0), reverse=True)
    return items


@app.get('/')
def index():
    return render_template('index.html', version=APP_VERSION, build=APP_BUILD)


@app.get('/api/health')
def health():
    return jsonify(status='ok', product='Control Center', version=APP_VERSION, build=APP_BUILD, edition=_license_info()['edition'])


@app.get('/api/system')
def system_info():
    mem = _meminfo(); total = mem.get('MemTotal', 0); avail = mem.get('MemAvailable', 0); disk = shutil.disk_usage('/')
    return jsonify(version=APP_VERSION, build=APP_BUILD, edition=_license_info()['edition'], hostname=socket.gethostname(), os=platform.platform(), kernel=platform.release(), architecture=platform.machine(), uptime_seconds=float(_read('/proc/uptime', '0').split()[0] or 0), cpu_percent=_cpu_usage(), cpu_count=os.cpu_count() or 0, memory={'total': total, 'used': max(total - avail, 0), 'percent': round(((total - avail) / total * 100), 1) if total else 0}, disk={'total': disk.total, 'used': disk.used, 'percent': round(disk.used / disk.total * 100, 1) if disk.total else 0}, storage=_storage(), top_processes=_top_processes(), wan=_wan_telemetry(), interfaces=len(_interfaces()))


@app.get('/api/networks')
def networks():
    config, interfaces, source = _effective_network_config()
    roles = {v.get('interface'): k.upper() for k, v in config.items() if v.get('interface')}
    for item in interfaces:
        item['role'] = roles.get(item['name'], '')
    return jsonify(interfaces=interfaces, config=config, source=source)


@app.route('/api/network/config', methods=['GET', 'POST'])
def network_config():
    if request.method == 'POST':
        try:
            cfg = _validate_network(request.get_json(silent=True) or {})
        except ValueError as exc:
            return jsonify(ok=False, error=str(exc)), 400
        _write_json(NETWORK_PENDING, cfg)
        return jsonify(ok=True, message='Конфигурация проверена и передана на применение')
    config, interfaces, source = _effective_network_config()
    return jsonify(config=config, source=source, status=_read_json(NETWORK_STATUS, {}), interfaces=interfaces)


@app.get('/api/rbac')
def rbac():
    return jsonify(users=[{'name': u.pw_name, 'uid': u.pw_uid, 'type': 'local' if u.pw_uid >= 1000 else 'system'} for u in pwd.getpwall()], groups=[{'name': g.gr_name, 'gid': g.gr_gid} for g in grp.getgrall()], mode='read-only', scope='local')


@app.get('/api/market')
def market():
    installed = _dhcp_installed()
    return jsonify(items=[{'id': 'dhcp', 'name': 'DHCP Server', 'description': 'DHCPv4 на базе dnsmasq', 'state': 'installed' if installed else 'available', 'installable': True}, {'id': 'pxe', 'name': 'PXE Server', 'description': 'Сетевая установка ОС', 'state': 'planned', 'installable': False}, {'id': 'samba', 'name': 'Samba', 'description': 'Файловые и доменные сервисы', 'state': 'planned', 'installable': False}, {'id': 'adguard', 'name': 'AdGuard', 'description': 'DNS-фильтрация и сетевые сервисы', 'state': 'planned', 'installable': False}], dhcp_installed=installed, status=_read_json(MARKET_STATUS, {}))


@app.post('/api/market/dhcp')
def market_dhcp():
    action = str((request.get_json(silent=True) or {}).get('action') or '').lower()
    if action not in ('install', 'remove'):
        return jsonify(error='action must be install or remove'), 400
    _write_json(MARKET_PENDING, {'module': 'dhcp', 'action': action, 'requested_at': int(time.time())})
    return jsonify(ok=True, status='pending', action=action)


@app.route('/api/dhcp/config', methods=['GET', 'POST'])
def dhcp_config():
    if not _dhcp_installed():
        return jsonify(error='DHCP Server не установлен'), 404
    if request.method == 'POST':
        try:
            cfg = _validate_dhcp(request.get_json(silent=True) or {})
        except (ValueError, TypeError) as exc:
            return jsonify(ok=False, error=str(exc)), 400
        _write_json(DHCP_PENDING, cfg)
        return jsonify(ok=True, status='pending', message='Настройки DHCP проверены и переданы на применение')
    net, _, _ = _effective_network_config()
    cfg, source = _effective_dhcp_config()
    return jsonify(config=cfg, source=source, status=_read_json(DHCP_STATUS, {}), service=_dhcp_service_status(), interfaces=_interfaces(), suggested_interface=(net.get('lan') or {}).get('interface', ''))


@app.post('/api/dhcp/check')
def dhcp_check():
    if not _dhcp_installed():
        return jsonify(ok=False, error='DHCP Server не установлен'), 404
    result = _check_dhcp_config()
    return jsonify(result), (200 if result['ok'] else 400)


@app.get('/api/notifications')
def notifications():
    items = _notifications()
    return jsonify(items=items, count=len(items), generated_at=int(time.time()))


@app.get('/api/license')
def license_info():
    return jsonify(version=APP_VERSION, build=APP_BUILD, license=_license_info(), status=_read_json(LICENSE_STATUS, {}))


@app.post('/api/license/activate')
def license_activate():
    body = request.get_json(silent=True) or {}
    payload = str(body.get('payload') or '').strip(); signature = str(body.get('signature') or '').strip()
    if not payload or not signature:
        return jsonify(error='Укажите payload и signature ключа активации'), 400
    _write_json(LICENSE_PENDING, {'payload': payload, 'signature': signature, 'requested_at': int(time.time())})
    return jsonify(ok=True, status='pending', message='Ключ передан на проверку')


@app.route('/api/settings/update', methods=['GET', 'POST'])
def update_settings():
    settings = _normalized_update_settings()
    if request.method == 'POST':
        body = request.get_json(silent=True) or {}; automatic = body.get('automatic_updates')
        if not isinstance(automatic, bool):
            return jsonify(error='automatic_updates must be boolean'), 400
        try:
            interval = int(body.get('interval_minutes'))
        except Exception:
            return jsonify(error='Интервал должен быть целым числом минут'), 400
        if interval < 5 or interval > 10080:
            return jsonify(error='Интервал должен быть от 5 до 10080 минут'), 400
        settings = {'automatic_updates': automatic, 'interval_minutes': interval, 'channel': 'production'}
        _write_json(SETTINGS_FILE, settings)
    return jsonify(settings=settings, status=_read_json(STATUS_FILE, {}), current_version=APP_VERSION, current_build=APP_BUILD)


@app.get('/api/settings/update/check')
def update_check():
    return jsonify(current_version=APP_VERSION, current_build=APP_BUILD, remote=_remote_release(), status=_read_json(STATUS_FILE, {}))


@app.route('/api/settings/os-update', methods=['GET', 'POST'])
def os_update_settings():
    settings = _normalized_os_update_settings()
    if request.method == 'POST':
        body = request.get_json(silent=True) or {}; automatic = body.get('automatic_updates')
        if not isinstance(automatic, bool):
            return jsonify(error='automatic_updates must be boolean'), 400
        try:
            interval = int(body.get('interval_minutes'))
        except Exception:
            return jsonify(error='Интервал должен быть целым числом минут'), 400
        if interval < 60 or interval > 10080:
            return jsonify(error='Интервал обновления ОС: от 60 до 10080 минут'), 400
        settings = {'automatic_updates': automatic, 'interval_minutes': interval}
        _write_json(OS_UPDATE_SETTINGS, settings)
    return jsonify(settings=settings, status=_read_json(OS_UPDATE_STATUS, {}))


@app.post('/api/settings/os-update/run')
def os_update_run():
    OS_UPDATE_NOW.write_text(str(int(time.time())) + '\n')
    return jsonify(ok=True, status='pending', message='Ручное обновление ОС и пакетов запущено')


if __name__ == '__main__':
    app.run(host=os.getenv('CONTROL_CENTER_HOST', '0.0.0.0'), port=int(os.getenv('CONTROL_CENTER_PORT', '8080')))