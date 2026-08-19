/* Control Center 1.0.11 documentation-compliance fixes. */
let dhcpClientsPageCompliance111 = 1;
const DHCP_CLIENTS_PAGE_SIZE_COMPLIANCE111 = 10;

function ensureDhcpClientsPagerCompliance111(){
  ensureDhcpClients111();
  const card = $('#dhcpClients111');
  if(!card || $('#dhcpClientsPager111')) return;
  const pager = document.createElement('div');
  pager.id = 'dhcpClientsPager111';
  pager.className = 'pager';
  const message = $('#dhcpClientsMessage111');
  card.insertBefore(pager, message || null);
}

function bindDhcpClientActionsCompliance111(){
  $$('[data-reserve-mac]').forEach(b=>b.addEventListener('click',()=>reserveDhcp111(b.dataset.reserveMac,b.dataset.host)));
  $$('[data-release-mac]').forEach(b=>b.addEventListener('click',()=>releaseDhcp111(b.dataset.releaseMac)));
}

function renderDhcpClientsCompliance111(items){
  ensureDhcpClientsPagerCompliance111();
  const all = Array.isArray(items) ? items : [];
  const pages = Math.max(1, Math.ceil(all.length / DHCP_CLIENTS_PAGE_SIZE_COMPLIANCE111));
  dhcpClientsPageCompliance111 = Math.min(Math.max(1, dhcpClientsPageCompliance111), pages);
  const start = (dhcpClientsPageCompliance111 - 1) * DHCP_CLIENTS_PAGE_SIZE_COMPLIANCE111;
  const slice = all.slice(start, start + DHCP_CLIENTS_PAGE_SIZE_COMPLIANCE111);
  const body = $('#dhcpClientsBody111');
  body.innerHTML = slice.map(x=>`<tr><td><span class="status-dot ${x.online?'ok':'neutral-status'}">${x.online?'ONLINE':'OFFLINE'}</span></td><td>${esc(x.hostname||x.reservation_hostname||'—')}</td><td class="mono">${esc(x.mac)}</td><td><b>${esc(x.ip||'—')}</b>${x.reserved?'<small class="reserved-label-111">зарезервирован</small>':''}</td><td>${x.expiry?new Date(x.expiry*1000).toLocaleString('ru-RU'):'—'}</td><td><input class="dhcp-reserve-input-111" data-reserve-ip="${esc(x.mac)}" value="${esc(x.reserved_ip||x.ip||'')}"></td><td><div class="service-actions-111"><button class="secondary compact-button" data-reserve-mac="${esc(x.mac)}" data-host="${esc(x.hostname||'')}">${x.reserved?'Изменить':'Забронировать'}</button>${x.reserved?`<button class="danger compact-button" data-release-mac="${esc(x.mac)}">Снять бронь</button>`:''}</div></td></tr>`).join('') || '<tr><td colspan="7">Активных клиентов и броней пока нет.</td></tr>';
  bindDhcpClientActionsCompliance111();

  const pager = $('#dhcpClientsPager111');
  if(!pager) return;
  if(all.length <= DHCP_CLIENTS_PAGE_SIZE_COMPLIANCE111){ pager.innerHTML=''; return; }
  pager.innerHTML = `<button class="secondary compact-button" data-dhcp-page-prev ${dhcpClientsPageCompliance111===1?'disabled':''}>Назад</button><span>Страница ${dhcpClientsPageCompliance111} из ${pages} · ${all.length} записей</span><button class="secondary compact-button" data-dhcp-page-next ${dhcpClientsPageCompliance111===pages?'disabled':''}>Далее</button>`;
  $('[data-dhcp-page-prev]')?.addEventListener('click',()=>{ if(dhcpClientsPageCompliance111>1){dhcpClientsPageCompliance111--;renderDhcpClientsCompliance111(all);} });
  $('[data-dhcp-page-next]')?.addEventListener('click',()=>{ if(dhcpClientsPageCompliance111<pages){dhcpClientsPageCompliance111++;renderDhcpClientsCompliance111(all);} });
}

async function loadDhcpClients111(){
  ensureDhcpClientsPagerCompliance111();
  if($('#dhcpNav')?.classList.contains('hidden')) return;
  try{
    const d = await api('/api/dhcp/clients');
    renderDhcpClientsCompliance111(d.items || []);
  }catch(e){
    flash110('#dhcpClientsMessage111', e.message, 7000);
  }
}

(function rewireDhcpRefreshCompliance111(){
  ensureDhcpClientsPagerCompliance111();
  const old = $('#refreshDhcpClients111');
  if(!old) return;
  const fresh = old.cloneNode(true);
  old.replaceWith(fresh);
  fresh.addEventListener('click',()=>{dhcpClientsPageCompliance111=1;loadDhcpClients111();});
})();
