/* Control Center 1.0.11 — Samba AD-DC production */
const VERSION111='1.0.11';
let samba111State=null,samba111Poll=null;

function ensureSamba111(){
  if(!$('#sambaNav')){
    const settingsNav=$('.nav-item[data-tab="settings"]');
    const b=document.createElement('button');
    b.id='sambaNav';b.className='nav-item';b.dataset.tab='samba';b.dataset.title='Samba AD-DC';
    b.innerHTML='<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M4 5h16v14H4z"/><path d="M8 9h8M8 13h5M8 17h8"/></svg><span>Samba AD-DC</span>';
    settingsNav?.parentElement?.insertBefore(b,settingsNav);
    b.addEventListener('click',()=>{tab('samba');loadSamba111();});
  }
  if(!$('#samba')){
    const panel=document.createElement('section');panel.id='samba';panel.className='panel';
    panel.innerHTML=`
      <div class="page-head"><div><h1>Samba AD-DC</h1><p>Active Directory Domain Controller: Kerberos, LDAP, DNS, SYSVOL/NETLOGON и signed NTP</p></div><span class="status-pill neutral-status" id="sambaState111">—</span></div>
      <div class="samba-overview-111">
        <article class="section-card"><h3>Состояние домена</h3><div class="detail-list" id="sambaDomainDetails111"><div><span>Статус</span><b>Не настроен</b></div></div><div class="button-row"><button class="secondary" id="sambaHealth111">Проверить состояние</button></div><span class="inline-message" id="sambaHealthMessage111"></span></article>
        <article class="section-card"><h3>Безопасность provisioning</h3><p class="section-description">Создание AD-DC меняет DNS, Kerberos, Samba database и resolver. Поэтому операция требует одноразового локального подтверждения.</p><pre class="samba-command-111">sudo control-center-samba-approve</pre><p class="section-description">Код действует 10 минут и используется один раз. Пароль Administrator не сохраняется в PostgreSQL и постоянных файлах.</p></article>
      </div>
      <article class="section-card samba-provision-card-111" id="sambaProvisionCard111">
        <div class="card-title-row"><div><h3>Создание нового домена</h3><p>Первичный Samba Active Directory Domain Controller</p></div><span class="status-pill compact neutral-status" id="sambaReadinessState111">—</span></div>
        <div class="form-grid samba-form-grid-111">
          <label>DNS Realm<input id="sambaRealm111" autocomplete="off" placeholder="home.example.com"></label>
          <label>NetBIOS Domain<input id="sambaNetbios111" maxlength="15" autocomplete="off" placeholder="HOME"></label>
          <label>Сетевая роль<select id="sambaRole111"></select></label>
          <label>DNS Forwarder<input id="sambaForwarder111" autocomplete="off" placeholder="1.1.1.1"></label>
          <label>Пароль Domain Administrator<input id="sambaPassword111" type="password" autocomplete="new-password" placeholder="Минимум 12 символов"></label>
          <label>Повтор пароля<input id="sambaPassword2_111" type="password" autocomplete="new-password" placeholder="Повторите пароль"></label>
          <label>Одноразовый код<input id="sambaApproval111" maxlength="8" autocomplete="off" placeholder="8 символов"></label>
        </div>
        <div class="samba-safety-111">
          <label class="switch-row hidden" id="sambaWanConfirmRow111">Разрешить AD-DC на WAN <input id="sambaAllowWan111" type="checkbox"></label>
          <label class="switch-row hidden" id="sambaReplaceRow111">Разрешить backup и замену существующей Samba-конфигурации <input id="sambaReplace111" type="checkbox"></label>
          <label class="switch-row">Подтверждаю создание нового домена и изменение DNS/Kerberos <input id="sambaConfirm111" type="checkbox"></label>
        </div>
        <div class="button-row"><button class="secondary" id="sambaReadiness111">Проверить готовность</button><button class="primary" id="sambaProvision111">Создать домен</button></div>
        <span class="inline-message" id="sambaMessage111"></span>
        <div id="sambaChecks111" class="preflight-list samba-checks-111"></div>
      </article>
      <article class="section-card"><div class="card-title-row"><div><h3>Последняя операция</h3><p>Статус root worker и rollback</p></div><span id="sambaJobState111" class="status-pill compact neutral-status">—</span></div><div class="detail-list" id="sambaJobDetails111"></div></article>`;
    const settings=$('#settings');settings?.parentElement?.insertBefore(panel,settings);
    $('#sambaHealth111')?.addEventListener('click',checkSambaHealth111);
    $('#sambaReadiness111')?.addEventListener('click',checkSambaReadiness111);
    $('#sambaProvision111')?.addEventListener('click',provisionSamba111);
    $('#sambaRole111')?.addEventListener('change',updateSambaRoleWarnings111);
    $('#sambaRealm111')?.addEventListener('input',()=>{const n=$('#sambaNetbios111');if(n&&!n.dataset.manual){n.value=($('#sambaRealm111').value.split('.')[0]||'').replace(/[^a-z0-9-]/gi,'').slice(0,15).toUpperCase();}});
    $('#sambaNetbios111')?.addEventListener('input',()=>{$('#sambaNetbios111').dataset.manual='1';});
  }
  $('.samba-preflight-card')?.classList.add('hidden');
}

function sambaPayload111(secret=false){
  const p={realm:$('#sambaRealm111').value.trim(),netbios_domain:$('#sambaNetbios111').value.trim(),network_role:$('#sambaRole111').value,dns_forwarder:$('#sambaForwarder111').value.trim(),allow_wan:$('#sambaAllowWan111').checked,replace_existing:$('#sambaReplace111').checked};
  if(secret){p.administrator_password=$('#sambaPassword111').value;p.confirm_password=$('#sambaPassword2_111').value;p.approval_code=$('#sambaApproval111').value.trim();p.confirmation=$('#sambaConfirm111').checked;}
  return p;
}
function sambaTone111(state){state=String(state||'').toLowerCase();return ['active','healthy','running','applied'].includes(state)?'ok':['error','rollback','failed','degraded','rejected'].includes(state)?'bad':'neutral-status';}
function sambaCheckRows111(checks){return Object.entries(checks||{}).map(([key,x])=>`<div class="preflight-row"><span class="status-dot ${x.ok?'ok':x.severity==='blocker'?'bad':'neutral-status'}">${x.ok?'✓':x.severity==='blocker'?'×':'!'}</span><div><b>${esc(x.message||key)}</b><small>${esc(typeof x.value==='object'?JSON.stringify(x.value):x.value||'')}</small></div></div>`).join('');}

function updateSambaRoleWarnings111(){const role=$('#sambaRole111')?.value;$('#sambaWanConfirmRow111')?.classList.toggle('hidden',role!=='wan');if(role!=='wan')$('#sambaAllowWan111').checked=false;}

function renderSambaStatus111(d){
  samba111State=d;const module=d.module||{},status=d.status||{},provisioned=!!d.provisioned;
  const state=provisioned?(d.service?.active?'active':'error'):(status.state||'not-provisioned');
  const pill=$('#sambaState111');pill.textContent=provisioned?(d.service?.active?'● РАБОТАЕТ':'● ОШИБКА'):(status.state==='provisioning'?'● СОЗДАНИЕ…':'● НЕ НАСТРОЕН');pill.className='status-pill '+sambaTone111(state);
  $('#sambaDomainDetails111').innerHTML=provisioned?`<div><span>Realm</span><b>${esc(module.realm||'—')}</b></div><div><span>DC</span><b>${esc(module.fqdn||'—')}</b></div><div><span>NetBIOS</span><b>${esc(module.netbios_domain||'—')}</b></div><div><span>IPv4</span><b>${esc(module.ipv4||'—')}</b></div><div><span>Интерфейс</span><b>${esc(module.interface||'—')}</b></div><div><span>DNS backend</span><b>${esc(module.dns_backend||'—')}</b></div><div><span>DNS forwarder</span><b>${esc(module.dns_forwarder||'—')}</b></div><div><span>Health</span><b>${esc(module.health_state||'—')}</b></div>`:'<div><span>Статус</span><b>Домен ещё не создан</b></div>';
  const roles=(d.network_roles||[]).filter(x=>x.eligible),select=$('#sambaRole111');const old=select.value;select.innerHTML='<option value="">Выберите роль</option>'+roles.map(x=>`<option value="${esc(x.role)}">${x.role.toUpperCase()} · ${esc(x.interface)} · ${esc(x.ipv4)}/${esc(x.prefix)}</option>`).join('');select.value=old&&roles.some(x=>x.role===old)?old:(d.suggested_role||'');
  const chosen=roles.find(x=>x.role===select.value);if(chosen&&!$('#sambaForwarder111').value){const dns=(chosen.dns||[]).find(x=>!String(x).startsWith('127.'));if(dns)$('#sambaForwarder111').value=dns;}
  updateSambaRoleWarnings111();
  const replaceNeeded=!provisioned&&String(status.detail||'').toLowerCase().includes('samba');$('#sambaReplaceRow111')?.classList.toggle('hidden',!replaceNeeded);
  $('#sambaProvisionCard111')?.classList.toggle('provisioned',provisioned);$$('#sambaProvisionCard111 input,#sambaProvisionCard111 select').forEach(x=>{if(provisioned)x.disabled=true;});$('#sambaProvision111').disabled=provisioned||status.state==='provisioning';$('#sambaReadiness111').disabled=provisioned||status.state==='provisioning';
  const jobPill=$('#sambaJobState111');jobPill.textContent=status.state?stateLabel(status.state):'—';jobPill.className='status-pill compact '+sambaTone111(status.state);$('#sambaJobDetails111').innerHTML=`<div><span>Сообщение</span><b>${esc(status.message||'—')}</b></div><div><span>Детали</span><b>${esc(status.detail||'—')}</b></div><div><span>Job ID</span><b>${esc(status.job_id||'—')}</b></div><div><span>Backup</span><b>${esc(status.backup_path||module.backup_path||'—')}</b></div>`;
  if(status.state==='provisioning')startSambaPoll111();else stopSambaPoll111();
}
async function loadSamba111(){ensureSamba111();try{renderSambaStatus111(await api('/api/samba/status'));}catch(e){flash110('#sambaMessage111',e.message,6000);}}
function startSambaPoll111(){if(samba111Poll)return;samba111Poll=setInterval(async()=>{await loadSamba111();await loadNotifications();await market111();},2000);}
function stopSambaPoll111(){if(samba111Poll){clearInterval(samba111Poll);samba111Poll=null;}}

async function checkSambaReadiness111(){try{const d=await api('/api/samba/readiness',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(sambaPayload111(false))});$('#sambaChecks111').innerHTML=sambaCheckRows111(d.checks);const pill=$('#sambaReadinessState111');pill.textContent=d.ready?'● ГОТОВО':'● ЕСТЬ БЛОКЕРЫ';pill.className='status-pill compact '+(d.ready?'ok':'bad');flash110('#sambaMessage111',d.ready?'Readiness пройден. Получите одноразовый локальный код и создайте домен.':`Блокеры: ${(d.blockers||[]).join(', ')}`,7000);$('#sambaReplaceRow111')?.classList.toggle('hidden',!d.checks?.existing_samba||d.checks.existing_samba.ok||d.checks.existing_samba.value==='none');return d;}catch(e){flash110('#sambaMessage111',e.message,7000);throw e;}}
async function provisionSamba111(){
  $('#sambaProvision111').disabled=true;
  try{
    const readiness=await checkSambaReadiness111();if(!readiness.ready){$('#sambaProvision111').disabled=false;return;}
    const d=await api('/api/samba/provision',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(sambaPayload111(true))});
    $('#sambaPassword111').value='';$('#sambaPassword2_111').value='';$('#sambaApproval111').value='';flash110('#sambaMessage111',d.message||'Provisioning передан root worker',9000);startSambaPoll111();setTimeout(loadSamba111,600);setTimeout(loadNotifications,800);
  }catch(e){flash110('#sambaMessage111',e.message,9000);$('#sambaProvision111').disabled=false;}
}
async function checkSambaHealth111(){try{const d=await api('/api/samba/health',{method:'POST'});$('#sambaHealthMessage111').textContent=d.healthy?'Все базовые проверки AD-DC пройдены.':`Обнаружена деградация: ${Object.entries(d.checks||{}).filter(([,x])=>!x.ok).map(([k])=>k).join(', ')}`;await loadSamba111();await loadNotifications();}catch(e){flash110('#sambaHealthMessage111',e.message,7000);}}

async function market111(){try{const d=await api('/api/market');marketItems109=d.items||[];$('#dhcpNav')?.classList.toggle('hidden',!d.dhcp_installed);filterNav();paginate109('market',marketItems109,8,'#marketPager',(slice)=>{$('#marketList').innerHTML=slice.map(x=>{let action;if(x.id==='samba'){const busy=x.status?.code==='installing';action=`<button class="${x.state==='installed'?'secondary':'primary'}" data-samba-open="1" ${busy?'disabled':''}>${busy?'Создание…':x.state==='installed'?'Открыть':'Настроить'}</button>`;}else action=marketAction108(x);return `<article class="service-card service-card-108" data-service="${esc(x.id)}"><div><div class="service-card-head-108"><small>SERVICE</small>${marketStatusBadge108(x)}</div><h3>${esc(x.name)}</h3><p>${esc(x.description)}</p></div>${action}</article>`;}).join('');$$('[data-samba-open]').forEach(b=>b.addEventListener('click',()=>{tab('samba');loadSamba111();}));$$('[data-service-action]').forEach(b=>b.addEventListener('click',async()=>{if(b.dataset.serviceId!=='dhcp')return;b.disabled=true;try{await api('/api/market/dhcp',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({action:b.dataset.serviceAction})});await market111();setTimeout(loadNotifications,500);}catch(e){flash110('#marketMessage',e.message,6000);await market111();}}));});$('#marketMessage').textContent='';}catch(e){flash110('#marketMessage',e.message,6000);}}
market=market111;

ensureSamba111();loadSamba111();market111();
setInterval(()=>{if($('#samba')?.classList.contains('active'))loadSamba111();},10000);
