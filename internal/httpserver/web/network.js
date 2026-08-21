function installNetworkPage() {
  const nav = document.querySelector('.sidebar nav');
  if (!nav || document.querySelector('[data-page="network"]')) return;

  const button = document.createElement('button');
  button.className = 'nav-item';
  button.dataset.page = 'network';
  button.textContent = 'Сеть';
  const market = document.querySelector('[data-page="market"]');
  nav.insertBefore(button, market || null);

  const card = document.querySelector('.card');
  const users = document.querySelector('#rbac-users');
  const page = document.createElement('div');
  page.id = 'network-page';
  page.hidden = true;
  page.innerHTML = `
    <div id="network-inventory"></div>
    <form id="network-preview-form" hidden>
      <h3>Предпросмотр изменения IP-адреса</h3>
      <label>Интерфейс<select id="network-interface" required></select></label>
      <label>Новый адрес<input id="network-cidr" placeholder="192.168.10.20/24" required></label>
      <button class="primary" type="submit">Проверить изменение</button>
      <p id="network-preview-error" class="error"></p>
    </form>
    <div id="network-preview-result" hidden></div>`;
  card.insertBefore(page, users);

  document.querySelectorAll('.nav-item').forEach((item) => {
    if (item !== button) item.addEventListener('click', () => { page.hidden = true; });
  });

  button.addEventListener('click', async () => {
    document.querySelectorAll('.nav-item').forEach((item) => item.classList.remove('active'));
    button.classList.add('active');
    document.querySelector('#page-title').textContent = 'Сеть';
    document.querySelector('#card-title').textContent = 'Сетевые интерфейсы';
    document.querySelector('#card-text').textContent = 'Actual state и безопасный предпросмотр изменения IP с заранее сформированным rollback-состоянием.';
    for (const selector of ['#fleet-nodes','#fleet-form','#rbac-users','#system-details','#network-interfaces','#operations-list','#diagnostics-export']) {
      const element = document.querySelector(selector); if (element) element.hidden = true;
    }
    await loadNetworkPreviewPage();
  });

  document.querySelector('#network-preview-form').addEventListener('submit', previewNetworkAddressChange);
}

async function loadNetworkPreviewPage() {
  const page = document.querySelector('#network-page');
  const inventoryBox = document.querySelector('#network-inventory');
  const form = document.querySelector('#network-preview-form');
  const select = document.querySelector('#network-interface');
  const result = document.querySelector('#network-preview-result');
  result.hidden = true; result.textContent = '';
  try {
    const inventory = await api('/api/v1/network/interfaces');
    inventoryBox.innerHTML = `<h3>Actual state · ${inventory.count} интерф.</h3><ul class="compact-list">${inventory.interfaces.map((iface) => `<li><strong>${iface.name}</strong> · ${iface.flags.includes('up') ? 'UP' : 'DOWN'} · MTU ${iface.mtu}<br><span class="muted">${iface.addresses.join(', ') || 'без адресов'}</span></li>`).join('')}</ul>`;
    select.textContent = '';
    for (const iface of inventory.interfaces.filter((iface) => !iface.flags.includes('loopback'))) {
      const option = document.createElement('option'); option.value = iface.name; option.textContent = iface.name; select.appendChild(option);
    }
    form.hidden = currentUser?.role !== 'admin' || select.options.length === 0;
    page.hidden = false;
  } catch (error) {
    inventoryBox.textContent = error.message; form.hidden = true; page.hidden = false;
  }
}

async function previewNetworkAddressChange(event) {
  event.preventDefault();
  const errorBox = document.querySelector('#network-preview-error');
  const result = document.querySelector('#network-preview-result');
  errorBox.textContent = ''; result.hidden = true; result.textContent = '';
  try {
    const data = await api('/api/v1/network/address-change/preview', {method:'POST', body:JSON.stringify({interface:document.querySelector('#network-interface').value, cidr:document.querySelector('#network-cidr').value})});
    const plan = data.plan;
    result.innerHTML = `<h3>План проверен</h3><p>Интерфейс: <strong>${plan.interface}</strong> · Desired: <strong>${plan.desired_cidr}</strong> · ${plan.no_op ? 'изменение не требуется' : 'потребуется изменение'}</p><p>Actual: ${plan.actual_addresses.join(', ') || 'без адресов'}</p><p>Rollback: ${plan.rollback_addresses.join(', ') || 'вернуть пустой набор адресов'}</p><p class="muted">${plan.warnings.join(' ')}</p><p><strong>Apply отключён:</strong> операция только валидирует изменение и recovery path; конфигурация сервера не меняется.</p>`;
    result.hidden = false;
  } catch (error) { errorBox.textContent = error.message; }
}

installNetworkPage();
