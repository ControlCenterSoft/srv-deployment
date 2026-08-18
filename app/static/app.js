const $ = s => document.querySelector(s);
const $$ = s => [...document.querySelectorAll(s)];
const esc = v => String(v ?? '').replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
const api = async (url, options = {}) => {
  const r = await fetch(url, options);
  let d = {};
  try { d = await r.json(); } catch (_) {}
  if (!r.ok) throw new Error(d.error || d.message || `HTTP ${r.status}`);
  return d;
};
const fmt = n => { const u=['B','KB','MB','GB','TB']; let i=0; n=+n||0; while(n>=1024&&i<4){n/=1024;i++;} return n.toFixed(i?1:0)+' '+u[i]; };
const rate = n => fmt(n) + '/s';
const stateLabel = s => ({up:'UP',down:'DOWN',unknown:'UNKNOWN',active:'ACTIVE',inactive:'INACTIVE',failed:'FAILED'}[String(s||'').toLowerCase()] || String(s||'—').toUpperCase());
const statusClass = s => ['up','active','running'].includes(String(s||'').toLowerCase()) ? 'ok' : ['down','failed','inactive','error'].includes(String(s||'').toLowerCase()) ? 'bad' : 'neutral-status';

function isMobile(){ return matchMedia('(max-width: 900px)').matches; }
function closeMobileNav(){ document.body.classList.remove('mobile-nav-open'); $('#sidebarToggle')?.setAttribute('aria-expanded','false'); }
function toggleSidebar(){
  if(isMobile()){
    const open=document.body.classList.toggle('mobile-nav-open');
    $('#sidebarToggle')?.setAttribute('aria-expanded',String(open));
  }else{
    document.body.classList.toggle('sidebar-collapsed');
  }
}
$('#sidebarToggle')?.addEventListener('click', toggleSidebar);
$('#sidebarClose')?.addEventListener('click', closeMobileNav);
$('#mobileBackdrop')?.addEventListener('click', closeMobileNav);
window.addEventListener('resize',()=>{ if(!isMobile()) closeMobileNav(); });

function tab(t){
  $$('.nav-item,.panel').forEach(x=>x.classList.remove('active'));
  $(`.nav-item[data-tab="${t}"]`)?.classList.add('active');
  $('#'+t)?.classList.add('active');
  closeMobileNav();
  load(t);
}
$$('.nav-item').forEach(b=>b.addEventListener('click',()=>tab(b.dataset.tab)));

const search=$('#menuSearch');
function filterNav(){
  const q=(search?.value||'').trim().toLowerCase();
  $$('.nav-item').forEach(b=>{
    if(b.classList.contains('hidden')){ b.style.display='none'; return; }
    b.style.display=!q || (b.dataset.title||b.textContent).toLowerCase().includes(q) ? '' : 'none';
  });
}
search?.addEventListener('input',filterNav);
search?.addEventListener('keydown',e=>{ if(e.key==='Enter'){ const item=$$('.nav-item').find(x=>x.style.display!=='none'&&!x.classList.contains('hidden')); if(item) tab(item.dataset.tab); } });
document.addEventListener('keydown',e=>{ if((e.ctrlKey||e.metaKey)&&e.key.toLowerCase()==='k'){e.preventDefault();search?.focus();search?.select();} if(e.key==='Escape'){closeMobileNav();closeNotifications();} });

let charts={cpu:[],ram:[],wan:[]},lastWan=null,lastTs=0;
function spark(id,data,idx=0,max=100,clear=true){
  const c=$(id); if(!c) return; const x=c.getContext('2d'),w=c.width,h=c.height;
  if(clear)x.clearRect(0,0,w,h); x.beginPath();
  data.forEach((p,i)=>{const v=Array.isArray(p)?p[idx]:p,px=i*w/Math.max(data.length-1,1),py=h-7-Math.min(Math.max(v,0)/Math.max(max,1),1)*(h-14);i?x.lineTo(px,py):x.moveTo(px,py);});
  x.strokeStyle=idx?'#e7b85d':'#36d6b4'; x.lineWidth=2; x.stroke();
}
async function system(){
  try{
    const d=await api('/api/system'),now=Date.now();
    charts.cpu.push(d.cpu_percent); charts.ram.push(d.memory.percent); charts.cpu=charts.cpu.slice(-36); charts.ram=charts.ram.slice(-36);
    $('#cpuValue').textContent=d.cpu_percent+'%'; $('#ramValue').textContent=d.memory.percent+'%'; spark('#cpuChart',charts.cpu); spark('#ramChart',charts.ram);
    $('#storageValue').textContent=(d.storage[0]?.percent??d.disk.percent)+'%';
    $('#storageBars').innerHTML=(d.storage||[]).slice(0,4).map(s=>`<div class="barrow"><span>${esc(s.mount)} <b>${Number(s.percent)||0}%</b></span><i><em style="width:${Math.min(Number(s.percent)||0,100)}%"></em></i></div>`).join('');
    $('#topProcesses').innerHTML=(d.top_processes||[]).map((p,i)=>`<div class="listrow"><span>${i+1}. ${esc(p.name)}</span><b>${Number(p.cpu_percent)||0}% CPU · ${Number(p.memory_percent)||0}% RAM</b></div>`).join('') || '<div class="empty-state">Нет данных</div>';
    let rx=0,tx=0;
    if(lastWan&&lastTs&&lastWan.interface===d.wan.interface){const sec=Math.max((now-lastTs)/1000,.1);rx=Math.max(0,(d.wan.rx_bytes-lastWan.rx_bytes)/sec);tx=Math.max(0,(d.wan.tx_bytes-lastWan.tx_bytes)/sec);}
    lastWan=d.wan;lastTs=now;charts.wan.push([rx,tx]);charts.wan=charts.wan.slice(-36);const mx=Math.max(1024,...charts.wan.flat());spark('#wanChart',charts.wan,0,mx,true);spark('#wanChart',charts.wan,1,mx,false);
    $('#wanValue').textContent=d.wan.interface||'Не назначен';$('#wanRx').textContent=rate(rx);$('#wanTx').textContent=rate(tx);
    $('#systemDetails').innerHTML=`<div><span>Hostname</span><b>${esc(d.hostname)}</b></div><div><span>ОС</span><b>${esc(d.os)}</b></div><div><span>Kernel</span><b>${esc(d.kernel)}</b></div><div><span>Архитектура</span><b>${esc(d.architecture)}</b></div><div><span>Редакция</span><b>${esc(d.edition)}</b></div><div><span>Версия</span><b>${esc(d.version)} · ${esc(d.build||'')}</b></div>`;
  }catch(e){console.error(e);}
}

function method(r){ return document.querySelector(`input[name="${r}Method"]:checked`)?.value || 'dhcp'; }
function tog(r){ $('#'+r+'Static')?.classList.toggle('active',method(r)==='static'); }
$$('input[name="wanMethod"],input[name="lanMethod"]').forEach(x=>x.addEventListener('change',()=>tog(x.name.startsWith('wan')?'wan':'lan')));
function setRole(r,c){
  c=c||{};
  $('#'+r+'Interface').value=c.interface||'';
  const radio=document.querySelector(`input[name="${r}Method"][value="${c.method||'dhcp'}"]`); if(radio)radio.checked=true;
  const values={Ip:c.ip||'',Mask:c.mask??'',Gateway:c.gateway||'',Dns:(c.dns||[]).join(', ')};
  Object.entries(values).forEach(([k,v])=>{const el=$('#'+r+k);if(el)el.value=v;});
  tog(r);
  const live=[...(c.live_ipv4||[])]; if(c.live_gateway)live.push('GW '+c.live_gateway); if((c.live_dns||[]).length)live.push('DNS '+c.live_dns.join(', '));
  $('#'+r+'LiveHint').textContent=live.join(' · ')||'Текущие IPv4 параметры не обнаружены';
  const pill=$('#'+r+'LiveState'); pill.textContent=stateLabel(c.link_state); pill.className='status-pill compact '+statusClass(c.link_state);
}
function interfaceOption(x){ return `<option value="${esc(x.name)}">${esc(x.name)} · ${esc(x.mac)} · ${esc(x.state)}</option>`; }
function renderInterfaces(items,config){
  const roles={}; ['wan','lan'].forEach(r=>{const n=config?.[r]?.interface;if(n)roles[n]=r.toUpperCase();});
  $('#interfacesTable').innerHTML=(items||[]).map(x=>`<tr><td><span class="role-badge ${roles[x.name]?.toLowerCase()||''}">${esc(roles[x.name]||'—')}</span></td><td><b>${esc(x.name)}</b></td><td>${esc(x.kind||'—')}</td><td><span class="status-dot ${statusClass(x.state)}">${esc(stateLabel(x.state))}</span></td><td>${esc((x.ipv4||[]).join(', ')||'—')}</td><td>${esc(x.gateway||'—')}</td><td>${esc((x.dns||[]).join(', ')||'—')}</td><td class="mono">${esc(x.mac||'—')}</td><td>${esc(x.mtu||'—')}</td><td>${x.speed_mbps?esc(x.speed_mbps+' Мбит/с'):'—'}</td></tr>`).join('') || '<tr><td colspan="10">Интерфейсы не обнаружены</td></tr>';
}
async function networks(){
  try{
    const d=await api('/api/network/config');
    const options='<option value="">Выберите интерфейс</option>'+(d.interfaces||[]).map(interfaceOption).join('');
    $('#wanInterface').innerHTML=options;$('#lanInterface').innerHTML=options;
    setRole('wan',d.config?.wan);setRole('lan',d.config?.lan);renderInterfaces(d.interfaces,d.config);
    $('#networkSource').textContent=d.source==='stored'?'Применённое состояние':d.source==='netplan/live'?'Netplan / live':'Не настроено';
    if(d.status?.message)$('#networkMessage').textContent=d.status.message;
  }catch(e){$('#networkMessage').textContent=e.message;}
}
function rolePayload(r){const o={interface:$('#'+r+'Interface').value,method:method(r)};if(o.method==='static'){o.ip=$('#'+r+'Ip').value;o.mask=$('#'+r+'Mask').value;o.gateway=$('#'+r+'Gateway').value;o.dns=$('#'+r+'Dns').value;}return o;}
$('#applyNetwork')?.addEventListener('click',async()=>{try{const d=await api('/api/network/config',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({wan:rolePayload('wan'),lan:rolePayload('lan')})});$('#networkMessage').textContent=d.message;setTimeout(networks,1800);setTimeout(loadNotifications,2000);}catch(e){$('#networkMessage').textContent=e.message;}});
$('#refreshNetworks')?.addEventListener('click',networks);

async function market(){
  try{
    const d=await api('/api/market'); $('#dhcpNav').classList.toggle('hidden',!d.dhcp_installed); filterNav();
    $('#marketList').innerHTML=d.items.map(x=>`<article class="service-card"><div><small>SERVICE</small><h3>${esc(x.name)}</h3><p>${esc(x.description)}</p></div>${x.id==='dhcp'?`<button class="${x.state==='installed'?'danger':'primary'}" data-dhcp="${x.state==='installed'?'remove':'install'}">${x.state==='installed'?'Удалить':'Установить'}</button>`:'<span class="planned">Запланировано</span>'}</article>`).join('');
    if(d.status?.message)$('#marketMessage').textContent=d.status.message;
    $$('[data-dhcp]').forEach(b=>b.addEventListener('click',async()=>{b.disabled=true;$('#marketMessage').textContent=b.dataset.dhcp==='install'?'Установка DHCP…':'Удаление DHCP…';try{await api('/api/market/dhcp',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({action:b.dataset.dhcp})});setTimeout(async()=>{await market();await loadNotifications();},3500);}catch(e){$('#marketMessage').textContent=e.message;b.disabled=false;}}));
  }catch(e){$('#marketMessage').textContent=e.message;}
}

let dhcpOptions=[];
function renderDhcpOptions(){
  const rows=$('#dhcpOptionsTable'),empty=$('#dhcpOptionsEmpty');
  rows.innerHTML=dhcpOptions.map((x,i)=>`<tr><td><b>${Number(x.code)}</b></td><td class="mono">${esc(x.value)}</td><td class="right"><button class="icon-button small danger-text" data-remove-option="${i}" aria-label="Удалить">×</button></td></tr>`).join('');
  empty.classList.toggle('hidden',dhcpOptions.length>0);
  $$('[data-remove-option]').forEach(b=>b.addEventListener('click',()=>{dhcpOptions.splice(Number(b.dataset.removeOption),1);renderDhcpOptions();}));
}
$('#addDhcpOption')?.addEventListener('click',()=>{
  const code=Number($('#dhcpOptionCode').value),value=$('#dhcpOptionValue').value.trim();
  if(!Number.isInteger(code)||code<1||code>254){$('#dhcpMessage').textContent='Код DHCP option должен быть от 1 до 254';return;}
  if([1,3,6,51].includes(code)){ $('#dhcpMessage').textContent=`DHCP option ${code} управляется основными полями`; return; }
  if(dhcpOptions.some(x=>Number(x.code)===code)){ $('#dhcpMessage').textContent=`DHCP option ${code} уже добавлен`; return; }
  if(!value){$('#dhcpMessage').textContent='Укажите значение DHCP option';return;}
  dhcpOptions.push({code,value});dhcpOptions.sort((a,b)=>a.code-b.code);$('#dhcpOptionCode').value='';$('#dhcpOptionValue').value='';$('#dhcpMessage').textContent='';renderDhcpOptions();
});
function setDhcpService(service){
  const pill=$('#dhcpServiceStatus');
  if(!service?.installed){pill.textContent='Не установлен';pill.className='status-pill bad';return;}
  if(!service.configured){pill.textContent='Установлен · не настроен';pill.className='status-pill neutral-status';return;}
  pill.textContent=service.running?'● Работает':`● ${stateLabel(service.active_state)}`;pill.className='status-pill '+(service.running?'ok':'bad');
}
async function dhcp(){
  try{
    const d=await api('/api/dhcp/config'),o='<option value="">Выберите интерфейс</option>'+(d.interfaces||[]).map(interfaceOption).join('');
    $('#dhcpInterface').innerHTML=o;const c=d.config||{};
    $('#dhcpInterface').value=c.interface||d.suggested_interface||'';$('#dhcpStart').value=c.range_start||'';$('#dhcpEnd').value=c.range_end||'';$('#dhcpMask').value=c.mask??'';$('#dhcpGateway').value=c.gateway||'';$('#dhcpDns').value=(c.dns||[]).join(', ');$('#dhcpLease').value=c.lease_minutes||720;
    dhcpOptions=(c.extra_options||[]).map(x=>({code:Number(x.code),value:String(x.value)}));renderDhcpOptions();setDhcpService(d.service);
    $('#dhcpSource').textContent=d.source==='dnsmasq'?'Фактический dnsmasq.conf':d.source==='stored'?'Применённое состояние':'Не настроено';
    if(d.status?.message)$('#dhcpMessage').textContent=d.status.message;
  }catch(e){ if(e.message.includes('не установлен')){tab('market');return;} $('#dhcpMessage').textContent=e.message; }
}
async function refreshDhcpRuntime(){
  if(!$('#dhcp')?.classList.contains('active')) return;
  try{
    const d=await api('/api/dhcp/config');
    setDhcpService(d.service);
    if(d.status?.message) $('#dhcpMessage').textContent=d.status.message;
  }catch(e){
    if(e.message.includes('не установлен')){ $('#dhcpNav')?.classList.add('hidden'); filterNav(); }
  }
}
$('#saveDhcp')?.addEventListener('click',async()=>{const p={interface:$('#dhcpInterface').value,range_start:$('#dhcpStart').value,range_end:$('#dhcpEnd').value,mask:$('#dhcpMask').value,gateway:$('#dhcpGateway').value,dns:$('#dhcpDns').value,lease_minutes:+$('#dhcpLease').value,extra_options:dhcpOptions};try{const d=await api('/api/dhcp/config',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(p)});$('#dhcpMessage').textContent=d.message;setTimeout(dhcp,1700);setTimeout(loadNotifications,1900);}catch(e){$('#dhcpMessage').textContent=e.message;}});
$('#checkDhcp')?.addEventListener('click',async()=>{const out=$('#dhcpCheckOutput');out.classList.remove('hidden');out.textContent='Проверка…';try{const d=await api('/api/dhcp/check',{method:'POST'});out.textContent=d.message+(d.output?'\n\n'+d.output:'');$('#dhcpMessage').textContent=d.message;}catch(e){out.textContent=e.message;$('#dhcpMessage').textContent=e.message;}loadNotifications();});

async function rbac(){try{const d=await api('/api/rbac');$('#users').innerHTML=d.users.slice(0,40).map(x=>`<div class="listrow"><span>${esc(x.name)}</span><b>UID ${Number(x.uid)||0} · ${esc(x.type)}</b></div>`).join('');$('#groups').innerHTML=d.groups.slice(0,40).map(x=>`<div class="listrow"><span>${esc(x.name)}</span><b>GID ${Number(x.gid)||0}</b></div>`).join('');}catch(e){console.error(e);}}

async function settings(){
  try{
    const [u,o,l]=await Promise.all([api('/api/settings/update'),api('/api/settings/os-update'),api('/api/license')]);
    $('#autoUpdates').checked=u.settings.automatic_updates;$('#updateInterval').value=u.settings.interval_minutes;$('#autoOsUpdates').checked=o.settings.automatic_updates;$('#osUpdateInterval').value=o.settings.interval_minutes;
    const lic=l.license;$('#licenseEdition').textContent=lic.edition;$('#sidebarEdition').textContent=lic.edition;$('#deviceId').textContent=lic.device_id;$('#licenseId').textContent=lic.license_id||'Не активирована';$('#editionBadge').textContent=lic.edition.toUpperCase()+' · '+l.version;$('#topVersion').textContent='Control Center '+l.version+' '+lic.edition;
    if(l.status?.message)$('#licenseMessage').textContent=l.status.message;if(o.status?.message)$('#osUpdateMessage').textContent=o.status.message+(o.status.reboot_required?' · требуется перезагрузка':'');if(u.status?.message)$('#settingsMessage').textContent=u.status.message;
  }catch(e){console.error(e);}
}
$('#saveSettings')?.addEventListener('click',async()=>{try{await api('/api/settings/update',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({automatic_updates:$('#autoUpdates').checked,interval_minutes:+$('#updateInterval').value,channel:'production'})});$('#settingsMessage').textContent='Настройки сохранены';}catch(e){$('#settingsMessage').textContent=e.message;}});
$('#checkUpdate')?.addEventListener('click',async()=>{try{const d=await api('/api/settings/update/check');$('#settingsMessage').textContent=d.remote.available?`Production: ${d.remote.release}${d.remote.build?' · '+d.remote.build:''}`:'Ошибка проверки';}catch(e){$('#settingsMessage').textContent=e.message;}});
$('#saveOsUpdates')?.addEventListener('click',async()=>{try{await api('/api/settings/os-update',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({automatic_updates:$('#autoOsUpdates').checked,interval_minutes:+$('#osUpdateInterval').value})});$('#osUpdateMessage').textContent='Настройки сохранены';}catch(e){$('#osUpdateMessage').textContent=e.message;}});
$('#runOsUpdate')?.addEventListener('click',async()=>{try{const d=await api('/api/settings/os-update/run',{method:'POST'});$('#osUpdateMessage').textContent=d.message;setTimeout(settings,2600);setTimeout(loadNotifications,2800);}catch(e){$('#osUpdateMessage').textContent=e.message;}});
$('#activateProfessional')?.addEventListener('click',async()=>{try{const d=await api('/api/license/activate',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({payload:$('#licensePayload').value,signature:$('#licenseSignature').value})});$('#licenseMessage').textContent=d.message;setTimeout(settings,1200);setTimeout(loadNotifications,1400);}catch(e){$('#licenseMessage').textContent=e.message;}});

const READ_KEY='control-center-notifications-read-v1';
let notificationItems=[];
function readSet(){try{return new Set(JSON.parse(localStorage.getItem(READ_KEY)||'[]'));}catch(_){return new Set();}}
function saveRead(set){localStorage.setItem(READ_KEY,JSON.stringify([...set].slice(-300)));}
function updateBell(){
  const read=readSet(),unread=notificationItems.filter(x=>!read.has(x.id)),bell=$('#notificationBell'),count=$('#notificationCount');
  bell.classList.remove('error','success','neutral');
  bell.classList.add(unread.some(x=>x.severity==='error')?'error':unread.length?'success':'neutral');
  count.textContent=unread.length;count.classList.toggle('hidden',!unread.length);
}
function renderNotifications(){
  const read=readSet();
  $('#notificationList').innerHTML=notificationItems.map(x=>`<button class="notification-item ${x.severity} ${read.has(x.id)?'read':'unread'}" data-notification-id="${esc(x.id)}"><div class="notification-meta"><b>${esc(x.title)}</b><span>${x.timestamp?new Date(x.timestamp*1000).toLocaleString('ru-RU'):'Текущее состояние'}</span></div><p>${esc(x.message)}</p></button>`).join('') || '<div class="empty-state">Событий пока нет.</div>';
  $$('[data-notification-id]').forEach(b=>b.addEventListener('click',()=>{const s=readSet();s.add(b.dataset.notificationId);saveRead(s);renderNotifications();updateBell();}));
}
async function loadNotifications(){try{const d=await api('/api/notifications');notificationItems=d.items||[];renderNotifications();updateBell();}catch(e){console.error(e);}}
function openNotifications(){const d=$('#notificationDrawer');d.classList.add('open');d.setAttribute('aria-hidden','false');$('#notificationBell').setAttribute('aria-expanded','true');}
function closeNotifications(){const d=$('#notificationDrawer');d?.classList.remove('open');d?.setAttribute('aria-hidden','true');$('#notificationBell')?.setAttribute('aria-expanded','false');}
$('#notificationBell')?.addEventListener('click',()=>$('#notificationDrawer').classList.contains('open')?closeNotifications():openNotifications());
$('#closeNotifications')?.addEventListener('click',closeNotifications);
$('#markNotificationsRead')?.addEventListener('click',()=>{const s=readSet();notificationItems.forEach(x=>s.add(x.id));saveRead(s);renderNotifications();updateBell();});

function load(t){({system,networks,market,dhcp,rbac,settings}[t]||(()=>{}))();}
market();system();settings();loadNotifications();
setInterval(()=>{if($('#system')?.classList.contains('active'))system();},3000);
setInterval(refreshDhcpRuntime,6000);
setInterval(loadNotifications,5000);
