function installAuditPage() {
  const nav = document.querySelector('.sidebar nav');
  const card = document.querySelector('.card');
  if (!nav || !card || document.querySelector('[data-page="audit"]')) return;

  const button = document.createElement('button');
  button.className = 'nav-item';
  button.dataset.page = 'audit';
  button.textContent = 'Аудит';
  button.hidden = true;
  const systemButton = document.querySelector('[data-page="system"]');
  nav.insertBefore(button, systemButton || null);

  const page = document.createElement('div');
  page.id = 'audit-page';
  page.hidden = true;

  const header = document.createElement('div');
  const title = document.createElement('h3');
  title.textContent = 'Последние события';
  header.appendChild(title);
  const refresh = document.createElement('button');
  refresh.type = 'button';
  refresh.className = 'text-button';
  refresh.textContent = 'Обновить';
  refresh.setAttribute('aria-label', 'Обновить журнал аудита');
  refresh.addEventListener('click', loadAuditPage);
  header.appendChild(refresh);
  page.appendChild(header);

  const status = document.createElement('div');
  status.id = 'audit-status';
  status.setAttribute('role', 'status');
  status.setAttribute('aria-live', 'polite');
  status.setAttribute('aria-atomic', 'true');
  page.appendChild(status);

  const results = document.createElement('div');
  results.id = 'audit-results';
  page.appendChild(results);

  const systemDetails = document.querySelector('#system-details');
  card.insertBefore(page, systemDetails || null);

  const syncVisibility = () => {
    button.hidden = currentUser?.role !== 'admin';
    if (button.hidden && !page.hidden) page.hidden = true;
  };
  syncVisibility();

  const role = document.querySelector('#session-role');
  if (role) {
    new MutationObserver(syncVisibility).observe(role, {childList: true, characterData: true, subtree: true});
  }

  document.querySelectorAll('.nav-item').forEach((item) => {
    if (item !== button) item.addEventListener('click', () => { page.hidden = true; });
  });

  button.addEventListener('click', async () => {
    if (currentUser?.role !== 'admin') return;
    document.querySelectorAll('.nav-item').forEach((item) => item.classList.remove('active'));
    button.classList.add('active');
    document.querySelector('#page-title').textContent = 'Аудит';
    document.querySelector('#card-title').textContent = 'Журнал аудита';
    document.querySelector('#card-text').textContent = 'Последние server-side события доступа и операций с идентификатором трассировки.';
    for (const selector of [
      '#fleet-nodes', '#fleet-form', '#rbac-users', '#rbac-create-form', '#system-details',
      '#network-interfaces', '#operations-list', '#diagnostics-export', '#network-page'
    ]) {
      const element = document.querySelector(selector);
      if (element) element.hidden = true;
    }
    page.hidden = false;
    await loadAuditPage();
  });
}

function formatAuditTime(value) {
  const parsed = new Date(value);
  if (Number.isNaN(parsed.getTime())) return String(value || '—');
  return parsed.toLocaleString();
}

function appendAuditLine(container, text, className = '') {
  const line = document.createElement('div');
  if (className) line.className = className;
  line.textContent = text;
  container.appendChild(line);
}

function renderAuditEvents(container, events) {
  container.textContent = '';

  const list = document.createElement('ul');
  list.className = 'compact-list';
  for (const event of events) {
    const item = document.createElement('li');
    const actor = event.actor || 'system';
    const role = event.role ? ` · ${event.role}` : '';
    const target = event.target ? ` → ${event.target}` : '';
    appendAuditLine(item, `${formatAuditTime(event.time)} · ${event.action || 'unknown'} · ${event.result || 'unknown'}`);
    appendAuditLine(item, `${actor}${role}${target}`, 'muted');
    const trace = [event.operation_id ? `operation ${event.operation_id}` : '', event.error_code || ''].filter(Boolean).join(' · ');
    if (trace) appendAuditLine(item, trace, 'muted');
    list.appendChild(item);
  }
  if (!events.length) {
    const item = document.createElement('li');
    item.textContent = 'Событий аудита пока нет.';
    list.appendChild(item);
  }
  container.appendChild(list);
}

async function loadAuditPage() {
  const page = document.querySelector('#audit-page');
  const status = document.querySelector('#audit-status');
  const results = document.querySelector('#audit-results');
  if (!page || !status || !results || currentUser?.role !== 'admin') return;
  page.hidden = false;
  status.textContent = 'Загрузка журнала аудита…';
  try {
    const data = await api('/api/v1/audit?limit=50');
    const events = Array.isArray(data.events) ? data.events : [];
    renderAuditEvents(results, events);
    status.textContent = events.length
      ? `Журнал аудита обновлён: ${events.length} событий.`
      : 'Журнал аудита обновлён: событий нет.';
  } catch (error) {
    status.textContent = `Не удалось загрузить журнал аудита: ${error.message}`;
  }
}

installAuditPage();
