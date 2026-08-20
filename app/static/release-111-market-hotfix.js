/* Control Center 1.0.11 Market lifecycle hotfix.
 *
 * release-108.js owns a legacy 2-second Market refresh interval which calls
 * market108() directly. After 1.0.11 rendered the new Domain/DNS/Storage
 * actions, that legacy interval could repaint the cards with generic
 * data-service-action buttons whose handler intentionally ignores every
 * service except DHCP. The result is a visible "Установить" button that does
 * nothing.
 *
 * Rebind every legacy Market entry point to the 1.0.11 renderer and keep a
 * delegated fallback for already-rendered legacy buttons. This makes the fix
 * resilient to an in-flight legacy repaint while the page is open.
 */
(function marketLifecycleHotfix111(){
  if(typeof marketServices111 !== 'function') return;

  // The old interval resolves this identifier on every tick, so rebinding it
  // retires the stale renderer without needing access to its interval id.
  if(typeof market108 === 'function') market108 = marketServices111;
  if(typeof market109 === 'function') market109 = marketServices111;
  market = marketServices111;

  const list = $('#marketList');
  if(list && !list.dataset.lifecycleHotfix111){
    list.dataset.lifecycleHotfix111 = '1';
    list.addEventListener('click', async (event)=>{
      const legacy = event.target.closest('[data-service-action][data-service-id]');
      if(!legacy || legacy.dataset.serviceId === 'dhcp') return;

      // Intercept before a stale per-button listener can consume the click.
      event.preventDefault();
      event.stopImmediatePropagation();

      const service = legacy.dataset.serviceId;
      const action = legacy.dataset.serviceAction;

      if(service === 'domain'){
        tab('domain111');
        await loadDomain111();
        if(action === 'remove'){
          setTimeout(()=>{
            $('#domainDanger111')?.scrollIntoView({behavior:'smooth',block:'start'});
            $('#domainRemoveApproval111')?.focus();
          },120);
        }else{
          setDomainStep111(1);
          setTimeout(()=>$('#domainRole111')?.focus(),80);
        }
        return;
      }

      if(!['dns','storage'].includes(service)) return;
      legacy.disabled = true;
      try{
        if(action === 'remove'){
          await removeService111(service);
        }else{
          const result = await api(`/api/market/${service}`,{
            method:'POST',
            headers:{'Content-Type':'application/json'},
            body:JSON.stringify({action:'install'})
          });
          flash110('#marketMessage',result.message||'Установка запущена',5000);
          setTimeout(marketServices111,900);
        }
      }catch(error){
        flash110('#marketMessage',error.message,7000);
        legacy.disabled = false;
      }
    }, true);
  }

  marketServices111();
})();
