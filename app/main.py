from flask import Flask, jsonify, render_template
import os, platform, socket, time, shutil, pwd, grp
from pathlib import Path

APP_VERSION = "1.0.0"
app = Flask(__name__, template_folder="templates", static_folder="static")
BOOT = time.time()


def _read(path, default=""):
    try:
        return Path(path).read_text().strip()
    except Exception:
        return default


def _meminfo():
    data = {}
    for line in _read('/proc/meminfo').splitlines():
        if ':' in line:
            k, v = line.split(':', 1)
            try: data[k] = int(v.strip().split()[0]) * 1024
            except Exception: pass
    return data


def _cpu_usage():
    try:
        a = [int(x) for x in _read('/proc/stat').splitlines()[0].split()[1:]]
        total = sum(a); idle = a[3] + (a[4] if len(a) > 4 else 0)
        time.sleep(0.08)
        b = [int(x) for x in _read('/proc/stat').splitlines()[0].split()[1:]]
        total2 = sum(b); idle2 = b[3] + (b[4] if len(b) > 4 else 0)
        dt = total2-total; di = idle2-idle
        return round((1 - di/dt) * 100, 1) if dt else 0
    except Exception:
        return 0


def _ipv4_for(name):
    import subprocess, json
    try:
        out = subprocess.check_output(['ip','-j','-4','addr','show','dev',name], text=True, timeout=2)
        rows = json.loads(out)
        return [x['local'] + '/' + str(x['prefixlen']) for r in rows for x in r.get('addr_info', []) if x.get('scope') in ('global','host')]
    except Exception:
        return []


@app.get('/')
def index():
    return render_template('index.html', version=APP_VERSION)


@app.get('/api/health')
def health():
    return jsonify(status='ok', product='Control Center', version=APP_VERSION)


@app.get('/api/system')
def system_info():
    mem = _meminfo(); total = mem.get('MemTotal',0); avail = mem.get('MemAvailable',0)
    disk = shutil.disk_usage('/')
    return jsonify(
        version=APP_VERSION,
        hostname=socket.gethostname(),
        os=platform.platform(),
        kernel=platform.release(),
        architecture=platform.machine(),
        uptime_seconds=float(_read('/proc/uptime','0').split()[0] or 0),
        cpu_percent=_cpu_usage(),
        memory={'total': total, 'used': max(total-avail,0), 'percent': round(((total-avail)/total*100),1) if total else 0},
        disk={'total': disk.total, 'used': disk.used, 'percent': round(disk.used/disk.total*100,1) if disk.total else 0}
    )


@app.get('/api/networks')
def networks():
    items=[]
    base=Path('/sys/class/net')
    for p in sorted(base.iterdir()) if base.exists() else []:
        name=p.name
        items.append({
            'name':name,
            'state':_read(p/'operstate','unknown'),
            'mac':_read(p/'address',''),
            'mtu':_read(p/'mtu',''),
            'rx_bytes':int(_read(p/'statistics/rx_bytes','0') or 0),
            'tx_bytes':int(_read(p/'statistics/tx_bytes','0') or 0),
            'ipv4':_ipv4_for(name)
        })
    return jsonify(items)


@app.get('/api/rbac')
def rbac():
    users=[]
    for u in pwd.getpwall():
        users.append({'name':u.pw_name,'uid':u.pw_uid,'gid':u.pw_gid,'home':u.pw_dir,'shell':u.pw_shell,'type':'local' if u.pw_uid >= 1000 else 'system'})
    groups=[]
    for g in grp.getgrall():
        groups.append({'name':g.gr_name,'gid':g.gr_gid,'members':g.gr_mem})
    return jsonify(users=users, groups=groups, mode='read-only', scope='local')


@app.get('/api/market')
def market():
    catalog=[
        {'id':'dhcp','name':'DHCP Server','description':'Служба выдачи сетевых параметров','state':'planned'},
        {'id':'pxe','name':'PXE Server','description':'Сетевая установка ОС','state':'planned'},
        {'id':'samba','name':'Samba','description':'Файловые и доменные сервисы','state':'planned'},
        {'id':'adguard','name':'AdGuard','description':'DNS-фильтрация и сетевые сервисы','state':'planned'}
    ]
    return jsonify(items=catalog, mode='catalog')


if __name__ == '__main__':
    app.run(host=os.getenv('CONTROL_CENTER_HOST','0.0.0.0'), port=int(os.getenv('CONTROL_CENTER_PORT','8080')))
