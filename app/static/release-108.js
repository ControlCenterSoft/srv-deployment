function marketStatusTone108(code){
  return ({running:'running',installing:'installing',removing:'installing',error:'error',planned:'planned',available:'available'})[code]||'available';
}

function marketStatusBadge108(item){
  const s=item.status||{},tone=marketStatusTone108(s.code),detail=s.detail||s.label||'';
  return `<span class="service-runtime-status ${tone}" title="${esc(detail)}"><i></i>${esc(s.label||'—')}</span>`;
}

function marketAction108(item){
  if(!item.installable) return '<span class="planned">Запланировано</span>';
  const busy=['installing','removing'].includes(item.status?.code);
  const installed=item.state==='installed';
  const action=installed?'remove':'install';
  const text=busy?(item.status?.code==='removing'?'Удаление…':'Установка…'):(installed?'Удалить':'Установить');
  return `<button class="${installed?'danger':'primary'}" data-service-action="${action}" data-service-id="${esc(item.id)}" ${busy?'disabled':''}>${text}</button>`;
}

async function market108(){
  try{
    const d=await api('/api/market');
    $('#dhcpNav')?.classList.toggle('hidden',!d.dhcp_installed);filterNav();
    $('#marketList').innerHTML=(d.items||[]).map(x=>`<article class="service-card service-card-108" data-service="${esc(x.id)}"><div><div class="service-card-head-108"><small>SERVICE</small>${marketStatusBadge108(x)}</div><h3>${esc(x.name)}</h3><p>${esc(x.description)}</p></div>${marketAction108(x)}</article>`).join('');
    if(d.status?.message) $('#marketMessage').textContent=d.status.message;
    $$('[data-service-action]').forEach(b=>b.addEventListener('click',async()=>{
      if(b.dataset.serviceId!=='dhcp') return;
      b.disabled=true;
      const installing=b.dataset.serviceAction==='install';
      $('#marketMessage').textContent=installing?'Установка DHCP Server запущена…':'Удаление DHCP Server запущено…';
      try{
        const r=await api('/api/market/dhcp',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({action:b.dataset.serviceAction})});
        $('#marketMessage').textContent=r.message||'Операция передана на выполнение';
        await market108();
        setTimeout(loadNotifications,500);
      }catch(e){
        $('#marketMessage').textContent=e.message;
        await market108();
      }
    }));
  }catch(e){
    $('#marketMessage').textContent=e.message;
  }
}

market=market108;
market108();
setInterval(()=>{if($('#market')?.classList.contains('active'))market108();},2000);

function ensureUpdateControls108(){
  const old=$('#checkUpdate');
  if(old&&!old.dataset.v108){
    const fresh=old.cloneNode(true);
    fresh.dataset.v108='1';
    old.replaceWith(fresh);
    fresh.addEventListener('click',()=>refreshUpdate108(true));
  }
  if(!$('#installUpdate')){
    const check=$('#checkUpdate');
    const button=document.createElement('button');
    button.id='installUpdate';
    button.className='primary update-install-108';
    button.type='button';
    button.disabled=true;
    button.textContent='Установить обновление';
    check?.parentElement?.appendChild(button);
    button.addEventListener('click',installUpdate108);
  }
}

async function refreshUpdate108(announce=false){
  ensureUpdateControls108();
  const button=$('#installUpdate'),message=$('#settingsMessage');
  try{
    const d=await api('/api/settings/update/check');
    const remote=d.remote||{};
    button.disabled=!d.update_available;
    button.dataset.release=remote.release||'';
    button.textContent=d.update_available&&remote.release?`Установить ${remote.release}`:'Установить обновление';
    button.classList.toggle('update-ready-108',!!d.update_available);
    if(d.update_available){
      message.textContent=`Доступно обновление Control Center ${remote.release}${remote.build?' · '+remote.build:''}`;
    }else if(announce){
      message.textContent=remote.available?`Установлена актуальная версия ${d.current_version}${d.current_build?' · '+d.current_build:''}`:'Не удалось проверить Production-обновление';
    }
  }catch(e){
    button.disabled=true;
    if(announce) message.textContent=e.message;
  }
}

async function installUpdate108(){
  const button=$('#installUpdate'),message=$('#settingsMessage');
  button.disabled=true;
  try{
    const d=await api('/api/settings/update/install',{method:'POST',headers:{'Content-Type':'application/json'},body:'{}'});
    message.textContent=(d.message||'Установка обновления запущена')+'. Панель может кратковременно стать недоступна во время перезапуска.';
    button.textContent='Установка…';
  }catch(e){
    message.textContent=e.message;
    await refreshUpdate108(false);
  }
}

const settings107For108=settings;
settings=async function(){
  await settings107For108();
  ensureUpdateControls108();
  await refreshUpdate108(false);
};
ensureUpdateControls108();
refreshUpdate108(false);
setInterval(()=>{if($('#settings')?.classList.contains('active'))refreshUpdate108(false);},30000);
