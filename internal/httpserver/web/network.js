let currentDNSPreview = null;
let dnsPreviewGeneration = 0;

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
    <div id="network-inventory" role="status" aria-live="polite"></div>
    <form id="network-preview-form" class="workflow-form" hidden>
      <h3>Предпросмотр изменения IP-адреса</h3>
      <label for="network-interface">Интерфейс</label>
      <select id="network-interface" required></select>
      <label for="network-cidr">Новый адрес</label>
      <input id="network-cidr" placeholder="192.168.10.20/24" required>
      <button class="primary" type="submit">Проверить изменение</button>
      <p id="network-preview-error" class="error" role="alert"></p>
    </form>
    <div id="network-preview-result" role="status" aria-live="polite" hidden></div>
    <section id="dns-resolver-workflow" aria-labelledby="dns-resolver-title">
      <h3 id="dns-resolver-title">DNS resolver</h3>
      <p id="dns-resolver-status" class="muted" role="status" aria-live="polite">Загрузка состояния DNS resolver…</p>
      <div id="dns-resolver-inventory"></div>
      <form id="dns-resolver-form" class="workflow-form" hidden>
        <h4>Безопасный предпросмотр DNS</h4>
        <label for="dns-nameservers">DNS-серверы</label>
        <input id="dns-nameservers" name="nameservers" autocomplete="off" placeholder="1.1.1.1, 8.8.8.8" required aria-describedby="dns-resolver-help">
        <label for="dns-search-domains">Домены поиска</label>
        <input id="dns-search-domains" name="search_domains" autocomplete="off" placeholder="corp.example, lab.example" aria-describedby="dns-resolver-help">
        <p id="dns-resolver-help" class="muted">Значения разделяются запятыми или пробелами. Сервер остаётся источником истины для нормализации и проверки.</p>
        <button class="primary" type="submit">Проверить DNS-план</button>
        <p id="dns-resolver-error" class="error" role="alert"></p>
      </form>
      <div id="dns-preview-result" role="status" aria-live="polite" hidden></div>
      <button id="dns-preflight-button" class="primary" type="button" hidden>Запустить preflight</button>
      <div id="dns-preflight-result" role="status" aria-live="polite" hidden></div>
    </section>`;
  card.insertBefore(page, users);

  document.querySelectorAll('.nav-item').forEach((item) => {
    if (item !== button) item.addEventListener('click', () => { page.hidden = true; });
  });

  button.addEventListener('click', async () => {
    document.querySelectorAll('.nav-item').forEach((item) => item.classList.remove('active'));
    button.classList.add('active');
    document.querySelector('#page-title').textContent = 'Сеть';
    document.querySelector('#card-title').textContent = 'Сетевые интерфейсы и DNS';
    document.querySelector('#card-text').textContent = 'Actual state, безопасный предпросмотр сетевых изменений и DNS preflight с server-authoritative rollback-состоянием.';
    for (const selector of ['#fleet-nodes','#fleet-form','#rbac-users','#rbac-create-form','#system-details','#network-interfaces','#operations-list','#diagnostics-export']) {
      const element = document.querySelector(selector); if (element) element.hidden = true;
    }
    await loadNetworkPreviewPage();
  });

  document.querySelector('#network-preview-form').addEventListener('submit', previewNetworkAddressChange);
  document.querySelector('#dns-resolver-form').addEventListener('submit', previewDNSResolverChange);
  document.querySelector('#dns-preflight-button').addEventListener('click', preflightDNSResolverChange);
  for (const selector of ['#dns-nameservers', '#dns-search-domains']) {
    document.querySelector(selector).addEventListener('input', resetDNSPreview);
  }
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
  if (!inventory.interfaces.length) {
    const item = document.createElement('li');
    item.textContent = 'Сетевые интерфейсы не обнаружены.';
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

function splitResolverValues(value) {
  return value.split(/[\s,]+/).map((item) => item.trim()).filter(Boolean);
}

function resolverValues(values) {
  return Array.isArray(values) && values.length ? values.join(', ') : '—';
}

function renderResolverState(container, label, state = {}) {
  const heading = document.createElement('h4');
  heading.textContent = label;
  container.appendChild(heading);
  appendPlanLine(container, 'DNS-серверы', resolverValues(state.nameservers));
  appendPlanLine(container, 'Домены поиска', resolverValues(state.search_domains));
  appendPlanLine(container, 'Options', resolverValues(state.options));
}

function renderDNSResolverInventory(container, data) {
  container.textContent = '';
  const actual = data.actual || {};
  appendPlanLine(container, 'Источник', actual.source_kind || 'не определён');
  appendPlanLine(container, 'DNS-серверы', resolverValues(actual.nameservers));
  appendPlanLine(container, 'Домены поиска', resolverValues(actual.search_domains));

  if (!Array.isArray(actual.nameservers) || actual.nameservers.length === 0) {
    const empty = document.createElement('p');
    empty.className = 'muted';
    empty.textContent = 'DNS-серверы в authoritative Actual state не обнаружены.';
    container.appendChild(empty);
  }

  const management = data.management || {};
  const capabilities = document.createElement('p');
  capabilities.className = 'muted';
  capabilities.textContent = `Preview: ${management.preview_supported ? 'доступен' : 'недоступен'} · Preflight: ${management.preflight_supported ? 'доступен' : 'недоступен'} · Apply: ${management.apply_supported ? 'доступен' : 'отключён'}.`;
  container.appendChild(capabilities);
}

function resetDNSPreview() {
  dnsPreviewGeneration += 1;
  currentDNSPreview = null;
  const preview = document.querySelector('#dns-preview-result');
  const preflight = document.querySelector('#dns-preflight-result');
  const button = document.querySelector('#dns-preflight-button');
  const errorBox = document.querySelector('#dns-resolver-error');
  if (preview) { preview.hidden = true; preview.textContent = ''; }
  if (preflight) { preflight.hidden = true; preflight.textContent = ''; }
  if (button) button.hidden = true;
  if (errorBox) errorBox.textContent = '';
}

function configureDNSResolverForm(data) {
  const form = document.querySelector('#dns-resolver-form');
  const nameservers = document.querySelector('#dns-nameservers');
  const searchDomains = document.querySelector('#dns-search-domains');
  const management = data.management || {};
  const actual = data.actual || {};
  resetDNSPreview();

  form.hidden = currentUser?.role !== 'admin' || !management.preview_supported;
  if (form.hidden) return;
  nameservers.value = Array.isArray(actual.nameservers) ? actual.nameservers.join(', ') : '';
  searchDomains.value = Array.isArray(actual.search_domains) ? actual.search_domains.join(', ') : '';
}

function renderDNSPreview(container, data) {
  container.textContent = '';
  const plan = data.plan || {};
  const heading = document.createElement('h4');
  heading.textContent = 'DNS-план проверен';
  container.appendChild(heading);

  const status = document.createElement('p');
  status.textContent = plan.no_op ? 'Desired уже совпадает с Actual; изменение не требуется.' : 'Desired отличается от Actual; перед будущим apply требуется preflight.';
  container.appendChild(status);

  renderResolverState(container, 'Desired', data.desired || plan.desired);
  renderResolverState(container, 'Actual', data.actual || plan.actual);
  renderResolverState(container, 'Rollback', data.rollback || plan.rollback);

  const note = document.createElement('p');
  note.className = 'muted';
  note.textContent = 'Источник состояния зафиксирован для preflight. Apply остаётся отключённым до появления recovery-aware executor.';
  container.appendChild(note);
}

function renderDNSPreflight(container, data) {
  container.textContent = '';
  const preflight = data.preflight || {};
  const heading = document.createElement('h4');
  heading.textContent = preflight.passed ? 'Preflight пройден' : 'Preflight заблокирован';
  container.appendChild(heading);

  const status = document.createElement('p');
  status.textContent = preflight.no_op
    ? 'Изменение не требуется: Desired совпадает с authoritative Actual.'
    : (preflight.passed ? 'Источник не изменился, rollback доступен, проверки пройдены.' : 'Одна или несколько обязательных проверок не пройдены.');
  container.appendChild(status);

  const checksHeading = document.createElement('strong');
  checksHeading.textContent = 'Проверки';
  container.appendChild(checksHeading);
  const checks = document.createElement('ul');
  checks.className = 'compact-list';
  for (const check of preflight.checks || []) {
    const item = document.createElement('li');
    item.textContent = `${check.ok ? 'OK' : 'BLOCK'} · ${check.name}${check.detail ? ` · ${check.detail}` : ''}`;
    checks.appendChild(item);
  }
  if (!checks.children.length) {
    const item = document.createElement('li');
    item.textContent = 'Проверки не возвращены сервером.';
    checks.appendChild(item);
  }
  container.appendChild(checks);

  if (Array.isArray(preflight.blockers) && preflight.blockers.length) {
    appendPlanLine(container, 'Блокеры', preflight.blockers.join(', '));
  } else {
    appendPlanLine(container, 'Блокеры', 'отсутствуют');
  }

  const executor = document.createElement('p');
  executor.className = 'muted';
  executor.textContent = `Recovery steps: ${(preflight.required_executor_steps || []).join(' → ') || 'не заявлены'}.`;
  container.appendChild(executor);

  const apply = document.createElement('p');
  apply.textContent = preflight.apply_supported
    ? 'Core сообщает о доступном apply; этот Web slice не выполняет изменение.'
    : 'Apply отключён Core contract; Web выполняет только preview/preflight и не меняет resolver.';
  container.appendChild(apply);
}

async function loadNetworkPreviewPage() {
  const page = document.querySelector('#network-page');
  const inventoryBox = document.querySelector('#network-inventory');
  const form = document.querySelector('#network-preview-form');
  const select = document.querySelector('#network-interface');
  const result = document.querySelector('#network-preview-result');
  const dnsStatus = document.querySelector('#dns-resolver-status');
  const dnsInventory = document.querySelector('#dns-resolver-inventory');
  const dnsForm = document.querySelector('#dns-resolver-form');

  page.hidden = false;
  inventoryBox.textContent = 'Загрузка сетевых интерфейсов…';
  dnsStatus.textContent = 'Загрузка состояния DNS resolver…';
  dnsInventory.textContent = '';
  form.hidden = true;
  dnsForm.hidden = true;
  result.hidden = true;
  result.textContent = '';
  resetDNSPreview();

  const [inventoryResult, resolverResult] = await Promise.allSettled([
    api('/api/v1/network/interfaces'),
    api('/api/v1/dns/resolver'),
  ]);

  if (inventoryResult.status === 'fulfilled') {
    const inventory = inventoryResult.value;
    renderNetworkInventory(inventoryBox, inventory);
    select.textContent = '';
    for (const iface of inventory.interfaces.filter((iface) => !iface.flags.includes('loopback'))) {
      const option = document.createElement('option');
      option.value = iface.name;
      option.textContent = iface.name;
      select.appendChild(option);
    }
    form.hidden = currentUser?.role !== 'admin' || select.options.length === 0;
  } else {
    inventoryBox.textContent = `Не удалось загрузить сетевые интерфейсы: ${inventoryResult.reason.message}`;
  }

  if (resolverResult.status === 'fulfilled') {
    dnsStatus.textContent = 'Authoritative Actual state загружен.';
    renderDNSResolverInventory(dnsInventory, resolverResult.value);
    configureDNSResolverForm(resolverResult.value);
  } else {
    dnsStatus.textContent = `Не удалось загрузить DNS resolver: ${resolverResult.reason.message}`;
    dnsInventory.textContent = '';
    dnsForm.hidden = true;
  }
}

async function previewNetworkAddressChange(event) {
  event.preventDefault();
  const errorBox = document.querySelector('#network-preview-error');
  const result = document.querySelector('#network-preview-result');
  errorBox.textContent = '';
  result.hidden = true;
  result.textContent = '';
  try {
    const data = await api('/api/v1/network/address-change/preview', {method:'POST', body:JSON.stringify({interface:document.querySelector('#network-interface').value, cidr:document.querySelector('#network-cidr').value})});
    renderNetworkPlan(result, data.plan);
    result.hidden = false;
  } catch (error) {
    errorBox.textContent = error.message;
  }
}

async function previewDNSResolverChange(event) {
  event.preventDefault();
  const errorBox = document.querySelector('#dns-resolver-error');
  const result = document.querySelector('#dns-preview-result');
  const preflightResult = document.querySelector('#dns-preflight-result');
  const preflightButton = document.querySelector('#dns-preflight-button');
  const nameservers = splitResolverValues(document.querySelector('#dns-nameservers').value);
  const searchDomains = splitResolverValues(document.querySelector('#dns-search-domains').value);

  resetDNSPreview();
  const previewGeneration = dnsPreviewGeneration;
  if (!nameservers.length) {
    errorBox.textContent = 'Введите минимум один DNS-сервер.';
    return;
  }

  result.hidden = false;
  result.textContent = 'Проверка DNS-плана…';
  try {
    const data = await api('/api/v1/dns/resolver/preview', {
      method: 'POST',
      body: JSON.stringify({nameservers, search_domains: searchDomains}),
    });
    if (previewGeneration !== dnsPreviewGeneration) return;
    currentDNSPreview = data;
    renderDNSPreview(result, data);
    preflightButton.hidden = currentUser?.role !== 'admin'
      || !data.management?.preflight_supported
      || !data.source_fingerprint
      || !data.desired;
  } catch (error) {
    if (previewGeneration !== dnsPreviewGeneration) return;
    result.hidden = true;
    result.textContent = '';
    preflightResult.hidden = true;
    errorBox.textContent = error.message;
  }
}

async function preflightDNSResolverChange() {
  const errorBox = document.querySelector('#dns-resolver-error');
  const result = document.querySelector('#dns-preflight-result');
  const button = document.querySelector('#dns-preflight-button');
  errorBox.textContent = '';

  if (!currentDNSPreview?.source_fingerprint || !currentDNSPreview?.desired) {
    errorBox.textContent = 'Сначала выполните свежий DNS preview.';
    button.hidden = true;
    return;
  }

  const preflightGeneration = dnsPreviewGeneration;
  const preview = currentDNSPreview;
  button.disabled = true;
  result.hidden = false;
  result.textContent = 'Выполняется authoritative preflight…';
  try {
    const data = await api('/api/v1/dns/resolver/preflight', {
      method: 'POST',
      body: JSON.stringify({
        nameservers: preview.desired.nameservers,
        search_domains: preview.desired.search_domains,
        expected_source_fingerprint: preview.source_fingerprint,
      }),
    });
    if (preflightGeneration !== dnsPreviewGeneration) return;
    renderDNSPreflight(result, data);
  } catch (error) {
    if (preflightGeneration !== dnsPreviewGeneration) return;
    result.hidden = true;
    result.textContent = '';
    errorBox.textContent = error.message;
  } finally {
    button.disabled = false;
  }
}

installNetworkPage();