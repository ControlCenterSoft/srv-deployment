/* Control Center 1.0.11 final UI refinements */

serviceActionButtons111=function(x){
  const busy=['installing','removing'].includes(x.status?.code);
  if(x.id==='domain'){
    if(x.state==='installed')return `<div class="service-actions-111"><button class="secondary" data-open-service="domain">Открыть</button><button class="danger" data-domain-remove-open="1" ${busy?'disabled':''}>Удалить</button></div>`;
    return `<button class="primary" data-open-domain-setup="1" ${busy?'disabled':''}>${busy?'Установка…':'Установить'}</button>`;
  }
  if(['dns','storage'].includes(x.id)){
    if(x.state==='installed')return `<div class="service-actions-111"><button class="secondary" data-open-service="${x.id}">Открыть</button><button class="danger" data-remove-service="${x.id}" ${x.required_by?.length?'disabled title="Обязательная зависимость Домена"':''}>Удалить</button></div>`;
    return `<button class="primary" data-install-service="${x.id}" ${busy?'disabled':''}>${busy?'Установка…':'Установить'}</button>`;
  }
  return marketAction108(x);
};

const marketServicesBeforeUiFix111=marketServices111;
marketServices111=async function(){
  await marketServicesBeforeUiFix111();
  $$('[data-domain-remove-open]').forEach(b=>b.addEventListener('click',()=>{
    tab('domain111');
    loadDomain111();
    setTimeout(()=>{$('#domainDanger111')?.scrollIntoView({behavior:'smooth',block:'start'});$('#domainRemoveApproval111')?.focus();},120);
  }));
};
market=marketServices111;

function ensureDhcpPager111(){
  ensureDhcpClients111();
  const card=$('#dhcpClients111');
  if(card&&!$('#dhcpClientsPager111')){
    const p=document.createElement('div');p.id='dhcpClientsPager111';p.className='pager hidden';card.appendChild(p);
  }
}

loadDhcpClients111=async function(){
  ensureDhcpPager111();
  if($('#dhcpNav')?.classList.contains('hidden'))return;
  try{
    const d=await api('/api/dhcp/clients');
    const items=d.items||[];
    paginate109('dhcp-clients',items,10,'#dhcpClientsPager111',(slice)=>{
      $('#dhcpClientsBody111').innerHTML=slice.map(x=>`<tr><td><span class="status-dot ${x.online?'ok':'neutral-status'}">${x.online?'ONLINE':'OFFLINE'}</span></td><td>${esc(x.hostname||x.reservation_hostname||'—')}</td><td class="mono">${esc(x.mac)}</td><td><b>${esc(x.ip||'—')}</b>${x.reserved?'<small class="reserved-label-111">зарезервирован</small>':''}</td><td>${x.expiry?new Date(x.expiry*1000).toLocaleString('ru-RU'):'—'}</td><td><input class="dhcp-reserve-input-111" data-reserve-ip="${esc(x.mac)}" value="${esc(x.reserved_ip||x.ip||'')}"></td><td><div class="service-actions-111"><button class="secondary compact-button" data-reserve-mac="${esc(x.mac)}" data-host="${esc(x.hostname||x.reservation_hostname||'')}">${x.reserved?'Изменить':'Забронировать'}</button>${x.reserved?`<button class="danger compact-button" data-release-mac="${esc(x.mac)}">Снять бронь</button>`:''}</div></td></tr>`).join('')||'<tr><td colspan="7">Активных клиентов и броней пока нет.</td></tr>';
      $$('[data-reserve-mac]').forEach(b=>b.addEventListener('click',()=>reserveDhcp111(b.dataset.reserveMac,b.dataset.host)));
      $$('[data-release-mac]').forEach(b=>b.addEventListener('click',()=>releaseDhcp111(b.dataset.releaseMac)));
    });
    const online=items.filter(x=>x.online).length,reserved=items.filter(x=>x.reserved).length;
    $('#dhcpClientsMessage111').textContent=`Клиентов: ${items.length} · online: ${online} · броней: ${reserved}`;
  }catch(e){flash110('#dhcpClientsMessage111',e.message,7000);}
};

ensureDhcpPager111();
marketServices111();
