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
    for (const selector of ['#fleet-nodes','#fleet-form','#rbac-users','#rbac-create-form','#system-details','#network-interfaces','#operations-list','#diagnostics-export']) {
      const element = document.querySelector(selector); if (element) element.hidden = true;
    }
    await loadNetworkPreviewPage();
  });

  document.querySelector('#network-preview-form').addEventListener('submit', previewNetworkAddressChange);
}

function renderNetworkInventory(container, inventory) {
  container.textContent = '';
  const heading = document.createElement('h3');
  heading.textContent = `Actual state · ${inventory.count} интерф.`;
  container.appendChild(heading);

  const list = document.createElement('ul');
  list.className = 'compact-list';
  for (const iface of inventory.interfaces) {
    const item = document.createElement('li');
    const name = document.createElement('strong');
    name.textContent = iface.name;
    item.appendChild(name);
    item.appendChild(document.createTextNode(` · ${iface.flags.includes('up') ? 'UP' : 'DOWN'} · MTU ${iface.mtu}`));
    item.appendChild(document.createElement('br'));
    const addresses = document.createElement('span');
    addresses.className = 'muted';
    addresses.textContent = iface.addresses.join(', ') || 'без адресов';
    item.appendChild(addresses);
    list.appendChild(item);
  }
  container.appendChild(list);
}

function appendPlanLine(container, label, value) {
  const paragraph = document.createElement('p');
  paragraph.appendChild(document.createTextNode(`${label}: `));
  const strong = document.createElement('strong');
  strong.textContent = value;
  paragraph.appendChild(strong);
  container.appendChild(paragraph);
}

function renderNetworkPlan(container, plan) {
  container.textContent = '';
  const heading = document.createElement('h3');
  heading.textContent = 'План проверен';
  container.appendChild(heading);

  appendPlanLine(container, 'Интерфейс', plan.interface);
  appendPlanLine(container, 'Desired', plan.desired_cidr);

  const status = document.createElement('p');
  status.textContent = plan.no_op ? 'Изменение не требуется.' : 'Потребуется изменение.';
  container.appendChild(status);

  appendPlanLine(container, 'Actual', plan.actual_addresses.join(', ') || 'без адресов');
  appendPlanLine(container, 'Rollback', plan.rollback_addresses.join(', ') || 'вернуть пустой набор адресов');

  const warnings = document.createElement('p');
  warnings.className = 'muted';
  warnings.textContent = plan.warnings.join(' ');
  container.appendChild(warnings);

  const apply = document.createElement('p');
  const applyLabel = document.createElement('strong');
  applyLabel.textContent = 'Apply отключён: ';
  apply.appendChild(applyLabel);
  apply.appendChild(document.createTextNode('операция только валидирует изменение и recovery path; конфигурация сервера не меняется.'));
  container.appendChild(apply);
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
    renderNetworkInventory(inventoryBox, inventory);
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
    renderNetworkPlan(result, data.plan);
    result.hidden = false;
  } catch (error) { errorBox.textContent = error.message; }
}

installNetworkPage();
