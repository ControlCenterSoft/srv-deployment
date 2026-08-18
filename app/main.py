from flask import Flask, jsonify, render_template, request
import os, platform, socket, time, shutil, pwd, grp, json, subprocess, urllib.request, ipaddress
from pathlib import Path

APP_VERSION = "1.0.2"
STATE_DIR = Path('/var/lib/control-center')
SETTINGS_FILE = STATE_DIR / 'update-settings.json'
STATUS_FILE = STATE_DIR / 'update-status.json'
NETWORK_FILE = STATE_DIR / 'network-config.json'
NETWORK_PENDING = STATE_DIR / 'network-pending.json'
NETWORK_STATUS = STATE_DIR / 'network-status.json'
DEPLOYMENT_URL = 'https://raw.githubusercontent.com/filosoff31/srv-deployment/main/deployment.json'
app = Flask(__name__, template_folder='templates', static_folder='static')
DEFAULT_SETTINGS = {'automatic_updates': True, 'frequency': 'hourly', 'channel': 'production'}


def _read(path, default=''):
    try: return Path(path).read_text().strip()
    except Exception: return default


def _read_json(path, default):
    try:
        data=json.loads(Path(path).read_text())
        return data if isinstance(data,dict) else default.copy()
    except Exception: return default.copy()


def _write_json(path,data):
    STATE_DIR.mkdir(parents=True,exist_ok=True)
    tmp=Path(str(path)+'.tmp'); tmp.write_text(json.dumps(data,ensure_ascii=False,indent=2)+'\n'); tmp.replace(path)


def _meminfo():
    data={}
    for line in _read('/proc/meminfo').splitlines():
        if ':' in line:
            k,v=line.split(':',1)
            try:data[k]=int(v.strip().split()[0])*1024
            except Exception:pass
    return data


def _cpu_usage():
    try:
        a=[int(x) for x in _read('/proc/stat').splitlines()[0].split()[1:]]; total=sum(a); idle=a[3]+(a[4] if len(a)>4 else 0)
        time.sleep(.08)
        b=[int(x) for x in _read('/proc/stat').splitlines()[0].split()[1:]]; total2=sum(b); idle2=b[3]+(b[4] if len(b)>4 else 0); dt=total2-total; di=idle2-idle
        return round((1-di/dt)*100,1) if dt else 0
    except Exception:return 0


def _ipv4_for(name):
    try:
        rows=json.loads(subprocess.check_output(['ip','-j','-4','addr','show','dev',name],text=True,timeout=2))
        return [x['local']+'/'+str(x['prefixlen']) for r in rows for x in r.get('addr_info',[]) if x.get('scope') in ('global','host')]
    except Exception:return []


def _interfaces():
    items=[]; base=Path('/sys/class/net')
    for p in sorted(base.iterdir()) if base.exists() else []:
        if p.name=='lo': continue
        items.append({'name':p.name,'state':_read(p/'operstate','unknown'),'mac':_read(p/'address',''),'mtu':_read(p/'mtu',''),'rx_bytes':int(_read(p/'statistics/rx_bytes','0') or 0),'tx_bytes':int(_read(p/'statistics/tx_bytes','0') or 0),'ipv4':_ipv4_for(p.name)})
    return items


def _mask_to_prefix(mask):
    value=str(mask or '').strip()
    if value.startswith('/'): value=value[1:]
    if value.isdigit():
        p=int(value)
        if 0<=p<=32:return p
        raise ValueError('Маска CIDR должна быть от 0 до 32')
    try:return ipaddress.IPv4Network('0.0.0.0/'+value).prefixlen
    except Exception:raise ValueError('Некорректная маска сети')


def _validate_network(body):
    if not isinstance(body,dict): raise ValueError('Некорректный запрос')
    known={x['name'] for x in _interfaces()}
    result={'wan':{},'lan':{}}
    used=set(); static_nets=[]
    for role in ('wan','lan'):
        src=body.get(role) or {}; iface=str(src.get('interface') or '').strip(); method=str(src.get('method') or 'dhcp').lower()
        if not iface or iface not in known: raise ValueError(f'{role.upper()}: выберите существующий интерфейс')
        if iface in used: raise ValueError('WAN и LAN должны использовать разные интерфейсы')
        used.add(iface)
        if method not in ('dhcp','static'): raise ValueError(f'{role.upper()}: неизвестный режим адресации')
        dst={'interface':iface,'method':method}
        if method=='static':
            ip=str(src.get('ip') or '').strip(); prefix=_mask_to_prefix(src.get('mask')); gateway=str(src.get('gateway') or '').strip(); dns=src.get('dns') or []
            if isinstance(dns,str): dns=[x.strip() for x in dns.replace(';',',').split(',') if x.strip()]
            try: addr=ipaddress.IPv4Interface(f'{ip}/{prefix}')
            except Exception: raise ValueError(f'{role.upper()}: некорректный IPv4 адрес')
            if addr.ip.is_unspecified or addr.ip.is_multicast or addr.ip.is_loopback: raise ValueError(f'{role.upper()}: IPv4 адрес недопустим')
            if gateway:
                try: gw=ipaddress.IPv4Address(gateway)
                except Exception: raise ValueError(f'{role.upper()}: некорректный шлюз')
                if gw not in addr.network: raise ValueError(f'{role.upper()}: шлюз должен находиться в той же подсети')
                if gw==addr.ip: raise ValueError(f'{role.upper()}: IP и шлюз не могут совпадать')
            clean_dns=[]
            for d in dns:
                try: clean_dns.append(str(ipaddress.IPv4Address(d)))
                except Exception: raise ValueError(f'{role.upper()}: некорректный DNS {d}')
            if role=='wan' and not gateway: raise ValueError('WAN Static: укажите шлюз')
            if not clean_dns: raise ValueError(f'{role.upper()} Static: укажите хотя бы один DNS')
            static_nets.append((role,addr.network))
            dst.update({'ip':str(addr.ip),'mask':prefix,'gateway':gateway,'dns':clean_dns})
        result[role]=dst
    if len(static_nets)==2 and static_nets[0][1].overlaps(static_nets[1][1]): raise ValueError('Подсети WAN и LAN не должны пересекаться')
    return result


def _remote_release():
    try:
        req=urllib.request.Request(DEPLOYMENT_URL,headers={'User-Agent':'Control-Center/1.0.2'})
        with urllib.request.urlopen(req,timeout=4) as response:data=json.loads(response.read().decode())
        return {'available':True,'release':data.get('release'),'channel':data.get('channel','production')}
    except Exception as exc:return {'available':False,'error':str(exc)}


@app.get('/')
def index(): return render_template('index.html',version=APP_VERSION)
@app.get('/api/health')
def health(): return jsonify(status='ok',product='Control Center',version=APP_VERSION)

@app.get('/api/system')
def system_info():
    mem=_meminfo(); total=mem.get('MemTotal',0); avail=mem.get('MemAvailable',0); disk=shutil.disk_usage('/')
    return jsonify(version=APP_VERSION,hostname=socket.gethostname(),os=platform.platform(),kernel=platform.release(),architecture=platform.machine(),uptime_seconds=float(_read('/proc/uptime','0').split()[0] or 0),cpu_percent=_cpu_usage(),cpu_count=os.cpu_count() or 0,memory={'total':total,'used':max(total-avail,0),'percent':round(((total-avail)/total*100),1) if total else 0},disk={'total':disk.total,'used':disk.used,'percent':round(disk.used/disk.total*100,1) if disk.total else 0},interfaces=len(_interfaces()))

@app.get('/api/networks')
def networks(): return jsonify(_interfaces())

@app.route('/api/network/config',methods=['GET','POST'])
def network_config():
    current=_read_json(NETWORK_FILE,{})
    if request.method=='POST':
        try: config=_validate_network(request.get_json(silent=True) or {})
        except ValueError as exc:return jsonify(ok=False,error=str(exc)),400
        _write_json(NETWORK_PENDING,config)
        return jsonify(ok=True,message='Конфигурация проверена и передана на применение',config=config,status='pending')
    return jsonify(config=current,status=_read_json(NETWORK_STATUS,{}),interfaces=_interfaces())

@app.get('/api/rbac')
def rbac():
    users=[{'name':u.pw_name,'uid':u.pw_uid,'gid':u.pw_gid,'home':u.pw_dir,'shell':u.pw_shell,'type':'local' if u.pw_uid>=1000 else 'system'} for u in pwd.getpwall()]
    groups=[{'name':g.gr_name,'gid':g.gr_gid,'members':g.gr_mem} for g in grp.getgrall()]
    return jsonify(users=users,groups=groups,mode='read-only',scope='local')

@app.get('/api/market')
def market(): return jsonify(items=[{'id':'dhcp','name':'DHCP Server','description':'Служба выдачи сетевых параметров','state':'planned'},{'id':'pxe','name':'PXE Server','description':'Сетевая установка ОС','state':'planned'},{'id':'samba','name':'Samba','description':'Файловые и доменные сервисы','state':'planned'},{'id':'adguard','name':'AdGuard','description':'DNS-фильтрация и сетевые сервисы','state':'planned'}],mode='catalog')

@app.route('/api/settings/update',methods=['GET','POST'])
def update_settings():
    settings=_read_json(SETTINGS_FILE,DEFAULT_SETTINGS)
    if request.method=='POST':
        body=request.get_json(silent=True) or {}; automatic=body.get('automatic_updates'); frequency=body.get('frequency'); channel=body.get('channel')
        if not isinstance(automatic,bool):return jsonify(error='automatic_updates must be boolean'),400
        if frequency not in ('hourly','daily','weekly'):return jsonify(error='invalid frequency'),400
        if channel!='production':return jsonify(error='only production channel is supported'),400
        settings={'automatic_updates':automatic,'frequency':frequency,'channel':channel}; _write_json(SETTINGS_FILE,settings)
    return jsonify(settings=settings,status=_read_json(STATUS_FILE,{}),current_version=APP_VERSION)

@app.get('/api/settings/update/check')
def update_check(): return jsonify(current_version=APP_VERSION,remote=_remote_release(),status=_read_json(STATUS_FILE,{}))

if __name__=='__main__': app.run(host=os.getenv('CONTROL_CENTER_HOST','0.0.0.0'),port=int(os.getenv('CONTROL_CENTER_PORT','8080')))
