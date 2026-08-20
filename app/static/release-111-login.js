(() => {
  const buttons=[...document.querySelectorAll('[data-auth-mode]')];
  const mode=document.getElementById('loginMode111');
  const msg=document.getElementById('loginMessage111');
  buttons.forEach(b=>b.addEventListener('click',()=>{
    if(b.disabled)return;
    buttons.forEach(x=>x.classList.remove('active'));
    b.classList.add('active');
    mode.value=b.dataset.authMode;
    msg.textContent='';
  }));
  document.getElementById('loginForm111')?.addEventListener('submit',async e=>{
    e.preventDefault();
    msg.textContent='Проверка…';
    const body={mode:mode.value,username:document.getElementById('loginUser111').value,password:document.getElementById('loginPassword111').value};
    try{
      const r=await fetch('/api/auth/login',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(body),credentials:'same-origin'});
      let d={};try{d=await r.json();}catch(_){}
      if(!r.ok)throw new Error(d.error||'Ошибка входа');
      location.href=d.next||'/';
    }catch(err){msg.textContent=err.message;}
  });
})();
