from flask import Flask, jsonify, render_template, request
import os, platform, socket, time, shutil, pwd, grp, json, subprocess, urllib.request, ipaddress, hashlib
from pathlib import Path

APP_VERSION='1.0.5'
STATE_DIR=Path('/var/lib/control-center')
SETTINGS_FILE=STATE_DIR/'update-settings.json'; STATUS_FILE=STATE_DIR/'update-status.json'
OS_UPDATE_SETTINGS=STATE_DIR/'os-update-settings.json'; OS_UPDATE_STATUS=STATE_DIR/'os-update-status.json'; OS_UPDATE_NOW=STATE_DIR/'os-update-now'
LICENSE_FILE=STATE_DIR/'license.json'; LICENSE_PENDING=STATE_DIR/'license-pending.json'
NETWORK_FILE=STATE_DIR/'network-config.json'; NETWORK_PENDING=STATE_DIR/'network-pending.json'; NETWORK_STATUS=STATE_DIR/'network-status.json'
MODULE_DIR=STATE_DIR/'modules'; DHCP_STATE=MODULE_DIR/'dhcp.json'; MARKET_PENDING=STATE_DIR/'market-pending.json'
DHCP_CONFIG=STATE_DIR/'dhcp-config.json'; DHCP_PENDING=STATE_DIR/'dhcp-pending.json'; DHCP_STATUS=STATE_DIR/'dhcp-status.json'
DEPLOYMENT_URL='https://raw.githubusercontent.com/filosoff31/srv-deployment/main/deployment.json'
app=Flask(__name__,template_folder='templates',static_folder='static')
DEFAULT_SETTINGS={'automatic_updates':True,'interval_minutes':60,'channel':'production'}
DEFAULT_OS_UPDATES={'automatic_updates':False,'interval_minutes':1440}

def _read(path,default=''):
    try:return Path(path).read_text().strip()
    except Exception:return default

def _read_json(path,default):
    try:
        data=json.loads(Path(path).read_text()); return data if isinstance(data,dict) else default.copy()
    except Exception:return default.copy()

def _write_json(path,data):
    Path(path).parent.mkdir(parents=True,exist_ok=True); tmp=Path(str(path)+'.tmp'); tmp.write_text(json.dumps(data,ensure_ascii=False,indent=2)+'\n'); tmp.replace(path)

def _normalized_update_settings():
    raw=_read_json(SETTINGS_FILE,DEFAULT_SETTINGS); legacy={'hourly':60,'daily':1440,'weekly':10080}
    try:interval=int(raw.get('interval_minutes',legacy.get(raw.get('frequency'),60)))
    except Exception:interval=60
    return {'automatic_updates':bool(raw.get('automatic_updates',True)),'interval_minutes':max(5,min(interval,10080)),'channel':'production'}

def _normalized_os_update_settings():
    raw=_read_json(OS_UPDATE_SETTINGS,DEFAULT_OS_UPDATES)
    try:interval=int(raw.get('interval_minutes',1440))
    except Exception:interval=1440
    return {'automatic_updates':bool(raw.get('automatic_updates',False)),'interval_minutes':max(60,min(interval,10080))}

def _device_id():
    mid=_read('/etc/machine-id','unknown')
    return hashlib.sha256(mid.encode()).hexdigest()[:24]

def _license_info():
    lic=_read_json(LICENSE_FILE,{})
    if lic.get('activated') and lic.get('edition')=='Professional' and lic.get('device_id')==_device_id():
        exp=lic.get('expires_at')
        if not exp or int(exp)>int(time.time()):
            return {'edition':'Professional','activated':True,'device_id':_device_id(),'license_id':lic.get('license_id',''),'expires_at':exp}
    return {'edition':'Home','activated':False,'device_id':_device_id(),'license_id':'','expires_at':None}

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
        a=[int(x) for x in _read('/proc/stat').splitlines()[0].split()[1:]]; total=sum(a); idle=a[3]+(a[4] if len(a)>4 else 0); time.sleep(.08)
        b=[int(x) for x in _read('/proc/stat').splitlines()[0].split()[1:]]; dt=sum(b)-total; di=(b[3]+(b[4] if len(b)>4 else 0))-idle
        return round((1-di/dt)*100,1) if dt else 0
    except Exception:return 0

def _top_processes():
    try:
        out=subprocess.check_output(['ps','-eo','pid=,comm=,%cpu=,%mem=','--sort=-%cpu'],text=True,timeout=2); rows=[]
        for line in out.splitlines()[:3]:
            p=line.split(None,3)
            if len(p)==4:rows.append({'pid':int(p[0]),'name':p[1],'cpu_percent':float(p[2]),'memory_percent':float(p[3])})
        return rows
    except Exception:return []

def _storage():
    try:
        out=subprocess.check_output(['df','-B1','-P','-x','tmpfs','-x','devtmpfs','-x','squashfs'],text=True,timeout=3); rows=[]
        for line in out.splitlines()[1:]:
            p=line.split()
            if len(p)<6:continue
            try:rows.append({'device':p[0],'mount':p[5],'total':int(p[1]),'used':int(p[2]),'available':int(p[3]),'percent':float(p[4].rstrip('%'))})
            except Exception:pass
        return rows[:8]
    except Exception:return []

def _ipv4_for(name):
    try:
        rows=json.loads(subprocess.check_output(['ip','-j','-4','addr','show','dev',name],text=True,timeout=2)); return [x['local']+'/'+str(x['prefixlen']) for r in rows for x in r.get('addr_info',[]) if x.get('scope') in ('global','host')]
    except Exception:return []

def _interfaces():
    items=[]; base=Path('/sys/class/net')
    for p in sorted(base.iterdir()) if base.exists() else []:
        if p.name=='lo':continue
        items.append({'name':p.name,'state':_read(p/'operstate','unknown'),'mac':_read(p/'address',''),'mtu':_read(p/'mtu',''),'rx_bytes':int(_read(p/'statistics/rx_bytes','0') or 0),'tx_bytes':int(_read(p/'statistics/tx_bytes','0') or 0),'ipv4':_ipv4_for(p.name)})
    return items

def _wan_telemetry():
    name=(_read_json(NETWORK_FILE,{}).get('wan') or {}).get('interface'); row={x['name']:x for x in _interfaces()}.get(name)
    return {'interface':name or '','state':row['state'] if row else 'unassigned','rx_bytes':row['rx_bytes'] if row else 0,'tx_bytes':row['tx_bytes'] if row else 0,'ipv4':row['ipv4'] if row else []}

def _mask_to_prefix(mask):
    value=str(mask or '').strip().lstrip('/')
    if value.isdigit():
        p=int(value)
        if 0<=p<=32:return p
        raise ValueError('Маска CIDR должна быть от 0 до 32')
    try:return ipaddress.IPv4Network('0.0.0.0/'+value).prefixlen
    except Exception:raise ValueError('Некорректная маска сети')

def _validate_network(body):
    known={x['name'] for x in _interfaces()}; result={'wan':{},'lan':{}}; used=set(); nets=[]
    for role in ('wan','lan'):
        src=body.get(role) or {}; iface=str(src.get('interface') or '').strip(); method=str(src.get('method') or 'dhcp').lower()
        if iface not in known:raise ValueError(f'{role.upper()}: выберите существующий интерфейс')
        if iface in used:raise ValueError('WAN и LAN должны использовать разные интерфейсы')
        used.add(iface)
        if method not in ('dhcp','static'):raise ValueError(f'{role.upper()}: неизвестный режим адресации')
        dst={'interface':iface,'method':method}
        if method=='static':
            ip=str(src.get('ip') or '').strip(); prefix=_mask_to_prefix(src.get('mask')); gateway=str(src.get('gateway') or '').strip(); dns=src.get('dns') or []
            if isinstance(dns,str):dns=[x.strip() for x in dns.replace(';',',').split(',') if x.strip()]
            try:addr=ipaddress.IPv4Interface(f'{ip}/{prefix}')
            except Exception:raise ValueError(f'{role.upper()}: некорректный IPv4 адрес')
            if gateway:
                try:gw=ipaddress.IPv4Address(gateway)
                except Exception:raise ValueError(f'{role.upper()}: некорректный шлюз')
                if gw not in addr.network or gw==addr.ip:raise ValueError(f'{role.upper()}: некорректный шлюз для выбранной подсети')
            clean=[]
            for d in dns:
                try:clean.append(str(ipaddress.IPv4Address(d)))
                except Exception:raise ValueError(f'{role.upper()}: некорректный DNS {d}')
            if role=='wan' and not gateway:raise ValueError('WAN Static: укажите шлюз')
            if not clean:raise ValueError(f'{role.upper()} Static: укажите DNS')
            nets.append(addr.network); dst.update({'ip':str(addr.ip),'mask':prefix,'gateway':gateway,'dns':clean})
        result[role]=dst
    if len(nets)==2 and nets[0].overlaps(nets[1]):raise ValueError('Подсети WAN и LAN не должны пересекаться')
    return result

def _dhcp_installed():return bool(_read_json(DHCP_STATE,{}).get('installed',False))

def _validate_dhcp(body):
    known={x['name'] for x in _interfaces()}; iface=str(body.get('interface') or '').strip()
    if iface not in known:raise ValueError('Выберите существующий интерфейс DHCP')
    try:start=ipaddress.IPv4Address(str(body.get('range_start') or '').strip()); end=ipaddress.IPv4Address(str(body.get('range_end') or '').strip())
    except Exception:raise ValueError('Некорректный диапазон DHCP')
    prefix=_mask_to_prefix(body.get('mask')); net=ipaddress.IPv4Network(f'{start}/{prefix}',strict=False)
    if end not in net or int(end)<int(start):raise ValueError('Начало и конец диапазона должны находиться в одной подсети')
    gateway=str(body.get('gateway') or '').strip()
    try:gw=ipaddress.IPv4Address(gateway)
    except Exception:raise ValueError('Некорректный шлюз DHCP')
    if gw not in net:raise ValueError('Шлюз DHCP должен находиться в той же подсети')
    dns=body.get('dns') or []
    if isinstance(dns,str):dns=[x.strip() for x in dns.replace(';',',').split(',') if x.strip()]
    clean=[]
    for d in dns:
        try:clean.append(str(ipaddress.IPv4Address(d)))
        except Exception:raise ValueError(f'Некорректный DNS {d}')
    if not clean:raise ValueError('Укажите хотя бы один DNS')
    lease=int(body.get('lease_minutes',720))
    if lease<10 or lease>10080:raise ValueError('Срок аренды: от 10 до 10080 минут')
    return {'interface':iface,'range_start':str(start),'range_end':str(end),'mask':prefix,'gateway':str(gw),'dns':clean,'lease_minutes':lease}

def _remote_release():
    try:
        req=urllib.request.Request(DEPLOYMENT_URL,headers={'User-Agent':'Control-Center/1.0.5'}); data=json.loads(urllib.request.urlopen(req,timeout=4).read().decode()); return {'available':True,'release':data.get('release'),'channel':data.get('channel','production')}
    except Exception as exc:return {'available':False,'error':str(exc)}

@app.get('/')
def index():return render_template('index.html',version=APP_VERSION)
@app.get('/api/health')
def health():return jsonify(status='ok',product='Control Center',version=APP_VERSION,edition=_license_info()['edition'])
@app.get('/api/system')
def system_info():
    mem=_meminfo(); total=mem.get('MemTotal',0); avail=mem.get('MemAvailable',0); disk=shutil.disk_usage('/')
    return jsonify(version=APP_VERSION,edition=_license_info()['edition'],hostname=socket.gethostname(),os=platform.platform(),kernel=platform.release(),architecture=platform.machine(),uptime_seconds=float(_read('/proc/uptime','0').split()[0] or 0),cpu_percent=_cpu_usage(),cpu_count=os.cpu_count() or 0,memory={'total':total,'used':max(total-avail,0),'percent':round(((total-avail)/total*100),1) if total else 0},disk={'total':disk.total,'used':disk.used,'percent':round(disk.used/disk.total*100,1) if disk.total else 0},storage=_storage(),top_processes=_top_processes(),wan=_wan_telemetry(),interfaces=len(_interfaces()))
@app.get('/api/networks')
def networks():return jsonify(_interfaces())
@app.route('/api/network/config',methods=['GET','POST'])
def network_config():
    if request.method=='POST':
        try:cfg=_validate_network(request.get_json(silent=True) or {})
        except ValueError as exc:return jsonify(ok=False,error=str(exc)),400
        _write_json(NETWORK_PENDING,cfg); return jsonify(ok=True,message='Конфигурация проверена и передана на применение')
    return jsonify(config=_read_json(NETWORK_FILE,{}),status=_read_json(NETWORK_STATUS,{}),interfaces=_interfaces())
@app.get('/api/rbac')
def rbac():return jsonify(users=[{'name':u.pw_name,'uid':u.pw_uid,'type':'local' if u.pw_uid>=1000 else 'system'} for u in pwd.getpwall()],groups=[{'name':g.gr_name,'gid':g.gr_gid} for g in grp.getgrall()],mode='read-only',scope='local')
@app.get('/api/market')
def market():
    installed=_dhcp_installed(); return jsonify(items=[{'id':'dhcp','name':'DHCP Server','description':'DHCPv4 на базе dnsmasq','state':'installed' if installed else 'available','installable':True},{'id':'pxe','name':'PXE Server','description':'Сетевая установка ОС','state':'planned','installable':False},{'id':'samba','name':'Samba','description':'Файловые и доменные сервисы','state':'planned','installable':False},{'id':'adguard','name':'AdGuard','description':'DNS-фильтрация и сетевые сервисы','state':'planned','installable':False}],dhcp_installed=installed)
@app.post('/api/market/dhcp')
def market_dhcp():
    action=str((request.get_json(silent=True) or {}).get('action') or '').lower()
    if action not in ('install','remove'):return jsonify(error='action must be install or remove'),400
    _write_json(MARKET_PENDING,{'module':'dhcp','action':action,'requested_at':int(time.time())}); return jsonify(ok=True,status='pending',action=action)
@app.route('/api/dhcp/config',methods=['GET','POST'])
def dhcp_config():
    if not _dhcp_installed():return jsonify(error='DHCP Server не установлен'),404
    if request.method=='POST':
        try:cfg=_validate_dhcp(request.get_json(silent=True) or {})
        except (ValueError,TypeError) as exc:return jsonify(ok=False,error=str(exc)),400
        _write_json(DHCP_PENDING,cfg); return jsonify(ok=True,status='pending',message='Настройки DHCP проверены и переданы на применение')
    net=_read_json(NETWORK_FILE,{}); return jsonify(config=_read_json(DHCP_CONFIG,{}),status=_read_json(DHCP_STATUS,{}),interfaces=_interfaces(),suggested_interface=(net.get('lan') or {}).get('interface',''))
@app.get('/api/license')
def license_info():return jsonify(version=APP_VERSION,license=_license_info())
@app.post('/api/license/activate')
def license_activate():
    body=request.get_json(silent=True) or {}; payload=str(body.get('payload') or '').strip(); signature=str(body.get('signature') or '').strip()
    if not payload or not signature:return jsonify(error='Укажите payload и signature ключа активации'),400
    _write_json(LICENSE_PENDING,{'payload':payload,'signature':signature,'requested_at':int(time.time())}); return jsonify(ok=True,status='pending',message='Ключ передан на проверку')
@app.route('/api/settings/update',methods=['GET','POST'])
def update_settings():
    settings=_normalized_update_settings()
    if request.method=='POST':
        body=request.get_json(silent=True) or {}; automatic=body.get('automatic_updates')
        if not isinstance(automatic,bool):return jsonify(error='automatic_updates must be boolean'),400
        try:interval=int(body.get('interval_minutes'))
        except Exception:return jsonify(error='Интервал должен быть целым числом минут'),400
        if interval<5 or interval>10080:return jsonify(error='Интервал должен быть от 5 до 10080 минут'),400
        settings={'automatic_updates':automatic,'interval_minutes':interval,'channel':'production'}; _write_json(SETTINGS_FILE,settings)
    return jsonify(settings=settings,status=_read_json(STATUS_FILE,{}),current_version=APP_VERSION)
@app.get('/api/settings/update/check')
def update_check():return jsonify(current_version=APP_VERSION,remote=_remote_release(),status=_read_json(STATUS_FILE,{}))
@app.route('/api/settings/os-update',methods=['GET','POST'])
def os_update_settings():
    settings=_normalized_os_update_settings()
    if request.method=='POST':
        body=request.get_json(silent=True) or {}; automatic=body.get('automatic_updates')
        if not isinstance(automatic,bool):return jsonify(error='automatic_updates must be boolean'),400
        try:interval=int(body.get('interval_minutes'))
        except Exception:return jsonify(error='Интервал должен быть целым числом минут'),400
        if interval<60 or interval>10080:return jsonify(error='Интервал обновления ОС: от 60 до 10080 минут'),400
        settings={'automatic_updates':automatic,'interval_minutes':interval}; _write_json(OS_UPDATE_SETTINGS,settings)
    return jsonify(settings=settings,status=_read_json(OS_UPDATE_STATUS,{}))
@app.post('/api/settings/os-update/run')
def os_update_run():
    OS_UPDATE_NOW.write_text(str(int(time.time()))+'\n'); return jsonify(ok=True,status='pending',message='Ручное обновление ОС и пакетов запущено')
if __name__=='__main__':app.run(host=os.getenv('CONTROL_CENTER_HOST','0.0.0.0'),port=int(os.getenv('CONTROL_CENTER_PORT','8080')))
