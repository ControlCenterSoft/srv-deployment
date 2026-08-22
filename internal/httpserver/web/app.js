let csrfToken = "";
let currentUser = null;
let operationDetailGeneration = 0;

const pages = {
  overview: ["Обзор", "Состояние платформы", "Runtime, health/readiness, audit и трассируемые операции."],
  fleet: ["Серверы", "Управляемые серверы", "Инвентарь, безопасный enrollment и автоматический heartbeat Fleet Agent."],
  market: ["Маркет", "Маркет", "Module lifecycle будет подключён после завершения foundation релиза."],
  rbac: ["RBAC", "RBAC", "Локальные пользователи и server-side роли admin/viewer."],
  system: ["Система", "Система", "Runtime diagnostics, сетевые интерфейсы и безопасная эксплуатационная информация платформы."],
};

async function api(path, options = {}) {
  const headers = new Headers(options.headers || {});
  if (options.body && !headers.has("Content-Type")) headers.set("Content-Type", "application/json");
  if (options.method && !["GET", "HEAD"].includes(options.method) && csrfToken) headers.set("X-CSRF-Token", csrfToken);
  const response = await fetch(path, {...options, headers, cache: "no-store", credentials: "same-origin"});
  let body = {};
  try { body = await response.json(); } catch {}
  if (!response.ok) throw new Error(body?.error?.message || `HTTP ${response.status}`);
  return body;
}

function showLogin(message = "") {
  currentUser = null; csrfToken = "";
  document.querySelector("#app-view").hidden = true;
  document.querySelector("#login-view").hidden = false;
  document.querySelector("#login-error").textContent = message;
}

function showApp(session) {
  currentUser = session.user; csrfToken = session.csrf_token;
  document.querySelector("#login-view").hidden = true;
  document.querySelector("#app-view").hidden = false;
  document.querySelector("#session-user").textContent = currentUser.username;
  document.querySelector("#session-role").textContent = currentUser.role;
  document.querySelector("#password-warning").hidden = !currentUser.must_change_password;
  const rbacNavigation = document.querySelector('[data-page="rbac"]');
  if (rbacNavigation) rbacNavigation.hidden = currentUser.role !== "admin";
}

async function restoreSession() {
  try { showApp(await api("/api/v1/auth/session")); await loadStatus(); }
  catch { showLogin(); }
}

document.querySelector("#login-form").addEventListener("submit", async (event) => {
  event.preventDefault();
  document.querySelector("#login-error").textContent = "";
  try {
    const session = await api("/api/v1/auth/login", {method:"POST", body:JSON.stringify({username:document.querySelector("#login-username").value, password:document.querySelector("#login-password").value})});
    document.querySelector("#login-password").value = "";
    showApp(session); await loadStatus();
  } catch (error) { showLogin(error.message); }
});

document.querySelector("#logout").addEventListener("click", async () => {
  try { await api("/api/v1/auth/logout", {method:"POST", body:"{}"}); } catch {}
  showLogin();
});

document.querySelector("#password-form").addEventListener("submit", async (event) => {
  event.preventDefault();
  try {
    await api("/api/v1/auth/password", {method:"POST", body:JSON.stringify({current_password:document.querySelector("#current-password").value, new_password:document.querySelector("#new-password").value})});
    showLogin("Пароль изменён. Войдите снова.");
  } catch (error) { document.querySelector("#password-error").textContent = error.message; }
});

function enrollmentStatusLabel(node) {
  if (node.status === "enrolled") return `enrolled${node.agent_version ? ` · agent ${node.agent_version}` : ""}`;
  if (node.status === "enrollment_ready") return "enrollment token issued";
  return node.status;
}

function appendTextLine(container, label, value) {
  const line = document.createElement("p");
  const name = document.createElement("strong");
  name.textContent = `${label}: `;
  line.appendChild(name);
  line.appendChild(document.createTextNode(String(value)));
  container.appendChild(line);
}

function shellQuote(value) {
  return `'${String(value).replaceAll("'", `'"'"'`)}'`;
}

function agentOriginAllowed() {
  const url = new URL(window.location.origin);
  if (url.protocol === "https:") return true;
  return url.protocol === "http:" && ["127.0.0.1", "localhost", "::1", "[::1]"].includes(url.hostname);
}

function renderFleetCapabilities(container, capabilities) {
  const panel = document.createElement("div");
  panel.className = "setup-panel";
  const heading = document.createElement("h3");
  heading.textContent = "Fleet Agent";
  panel.appendChild(heading);
  const agent = capabilities.agent || {};
  appendTextLine(panel, "Версия", agent.version || "—");
  appendTextLine(panel, "Heartbeat", `${agent.heartbeat_interval_seconds || "—"} сек.`);
  appendTextLine(panel, "Runtime user", agent.runtime_user || "—");
  appendTextLine(panel, "Transport", agent.requires_https ? "HTTPS; HTTP только для loopback testing" : "по contract");
  appendTextLine(panel, "Arbitrary shell", agent.arbitrary_shell === false ? "disabled" : "не заявлено");
  const note = document.createElement("p");
  note.className = "muted";
  note.textContent = "После enrollment агент хранит отдельный credential на managed node и автоматически обновляет health/inventory.";
  panel.appendChild(note);
  container.appendChild(panel);
}

function renderFleetAgentSetup(node, setup) {
  const box = document.createElement("div");
  box.className = "agent-setup";
  const heading = document.createElement("h4");
  heading.textContent = `Установка Fleet Agent ${setup.version || ""}`.trim();
  box.appendChild(heading);

  if (!agentOriginAllowed()) {
    const warning = document.createElement("p");
    warning.className = "error";
    warning.textContent = "Установка разрешена только из HTTPS Control Center; HTTP допустим только для loopback testing.";
    box.appendChild(warning);
    return box;
  }

  const installerPath = typeof setup.install_path === "string" ? setup.install_path : "/api/v1/fleet/agent/install.sh";
  const installerURL = new URL(installerPath, window.location.origin);
  if (installerURL.origin !== window.location.origin) {
    const warning = document.createElement("p");
    warning.className = "error";
    warning.textContent = "Installer contract rejected: источник должен быть same-origin.";
    box.appendChild(warning);
    return box;
  }

  const link = document.createElement("a");
  link.href = installerURL.href;
  link.textContent = "Скачать установщик Fleet Agent";
  box.appendChild(link);

  const instruction = document.createElement("p");
  instruction.textContent = "Скопируйте установщик на managed node и запустите команду:";
  box.appendChild(instruction);

  const command = document.createElement("code");
  command.className = "command-block";
  command.textContent = `sudo env CONTROL_CENTER_URL=${shellQuote(window.location.origin)} FLEET_NODE_ID=${shellQuote(node.id)} bash ./install-fleet-agent.sh`;
  box.appendChild(command);

  const tokenNote = document.createElement("p");
  tokenNote.className = "muted";
  tokenNote.textContent = "Установщик запросит одноразовый enrollment token интерактивно. Токен не включается в команду или URL.";
  box.appendChild(tokenNote);
  return box;
}

async function issueEnrollment(node, li) {
  li.querySelectorAll(".enrollment-secret, .agent-setup").forEach((element) => element.remove());
  try {
    const data = await api(`/api/v1/fleet/nodes/${encodeURIComponent(node.id)}/enrollment`, {method:"POST", body:"{}"});
    const box = document.createElement("div");
    box.className = "enrollment-secret";
    const expires = data.enrollment.expires_at ? new Date(data.enrollment.expires_at).toLocaleString() : "через 15 минут";
    box.textContent = `Одноразовый enrollment token (показывается только сейчас, действует до ${expires}): ${data.enrollment.token}`;
    li.appendChild(box);
    if (data.agent_setup) li.appendChild(renderFleetAgentSetup(node, data.agent_setup));
    node.status = "enrollment_ready";
    const button = li.querySelector("button");
    if (button) button.textContent = "Перевыпустить enrollment token";
  } catch (error) {
    const box = document.createElement("div"); box.className = "error enrollment-secret"; box.textContent = error.message; li.appendChild(box);
  }
}

async function loadFleet() {
  const container = document.querySelector("#fleet-nodes");
  const form = document.querySelector("#fleet-form");
  container.textContent = "";
  try {
    const [data, capabilities] = await Promise.all([api("/api/v1/fleet/nodes"), api("/api/v1/fleet/capabilities")]);
    const summary = document.createElement("p");
    summary.textContent = `Всего серверов: ${data.summary.total} · Enrolled: ${data.summary.enrolled} · Healthy: ${data.summary.healthy || 0} · Stale: ${data.summary.stale || 0} · Offline: ${data.summary.offline || 0} · Ожидают enrollment: ${data.summary.pending_enrollment}`;
    container.appendChild(summary);
    renderFleetCapabilities(container, capabilities);
    const list = document.createElement("ul");
    list.className = "compact-list";
    for (const node of data.nodes) {
      const li = document.createElement("li");
      const scope = [node.group, node.environment].filter(Boolean).join(" · ");
      const info = document.createElement("span");
      info.textContent = `${node.name} · ${node.address} · ${enrollmentStatusLabel(node)}${scope ? ` · ${scope}` : ""}`;
      li.appendChild(info);
      if (currentUser?.role === "admin" && node.status !== "enrolled") {
        const button = document.createElement("button");
        button.type = "button";
        button.className = "text-button";
        button.textContent = node.status === "enrollment_ready" ? "Перевыпустить enrollment token" : "Создать enrollment token";
        button.addEventListener("click", () => issueEnrollment(node, li));
        li.appendChild(document.createTextNode(" "));
        li.appendChild(button);
      }
      list.appendChild(li);
    }
    if (!data.nodes.length) {
      const li = document.createElement("li"); li.textContent = "Серверы ещё не добавлены."; list.appendChild(li);
    }
    container.appendChild(list);
    container.hidden = false;
    form.hidden = currentUser?.role !== "admin";
  } catch (error) {
    container.textContent = error.message;
    container.hidden = false;
    form.hidden = true;
  }
}

document.querySelector("#fleet-form").addEventListener("submit", async (event) => {
  event.preventDefault();
  const errorBox = document.querySelector("#fleet-error");
  errorBox.textContent = "";
  try {
    await api("/api/v1/fleet/nodes", {method:"POST", body:JSON.stringify({
      name: document.querySelector("#fleet-name").value,
      address: document.querySelector("#fleet-address").value,
      group: document.querySelector("#fleet-group").value,
      environment: document.querySelector("#fleet-environment").value,
    })});
    event.target.reset();
    await loadFleet();
  } catch (error) { errorBox.textContent = error.message; }
});

function userStatusLabel(user) {
  return `${user.username} · ${user.role}${user.blocked ? " · blocked" : " · active"}`;
}

async function setUserBlocked(user, blocked) {
  const action = blocked ? "заблокировать" : "разблокировать";
  if (!window.confirm(`Подтвердите: ${action} пользователя ${user.username}?`)) return;
  const errorBox = document.querySelector("#rbac-error");
  errorBox.textContent = "";
  try {
    await api(`/api/v1/rbac/users/${encodeURIComponent(user.username)}/blocked`, {method:"POST", body:JSON.stringify({blocked})});
    await loadRBAC();
  } catch (error) { errorBox.textContent = error.message; }
}

function renderRBACUsers(users) {
  const container = document.querySelector("#rbac-users");
  container.textContent = "";
  const heading = document.createElement("h3");
  heading.textContent = "Локальные пользователи";
  container.appendChild(heading);
  const list = document.createElement("ul");
  list.className = "compact-list rbac-list";
  for (const user of users) {
    const item = document.createElement("li");
    const info = document.createElement("span");
    info.textContent = userStatusLabel(user);
    item.appendChild(info);
    if (currentUser?.role === "admin" && user.username !== currentUser.username) {
      const button = document.createElement("button");
      button.type = "button";
      button.className = "text-button inline-action";
      button.textContent = user.blocked ? "Разблокировать" : "Заблокировать";
      button.setAttribute("aria-label", `${button.textContent} пользователя ${user.username}`);
      button.addEventListener("click", () => setUserBlocked(user, !user.blocked));
      item.appendChild(button);
    }
    list.appendChild(item);
  }
  if (!users.length) {
    const item = document.createElement("li");
    item.textContent = "Пользователи не найдены.";
    list.appendChild(item);
  }
  container.appendChild(list);
  container.hidden = false;
}

async function loadRBAC() {
  const container = document.querySelector("#rbac-users");
  const form = document.querySelector("#rbac-create-form");
  const errorBox = document.querySelector("#rbac-error");
  container.textContent = "";
  errorBox.textContent = "";
  try {
    const data = await api("/api/v1/rbac/users");
    renderRBACUsers(data.users);
    form.hidden = currentUser?.role !== "admin";
  } catch (error) {
    container.textContent = error.message;
    container.hidden = false;
    form.hidden = true;
  }
}

document.querySelector("#rbac-create-form").addEventListener("submit", async (event) => {
  event.preventDefault();
  const errorBox = document.querySelector("#rbac-error");
  errorBox.textContent = "";
  try {
    await api("/api/v1/rbac/users", {method:"POST", body:JSON.stringify({
      username: document.querySelector("#rbac-username").value,
      password: document.querySelector("#rbac-password").value,
      role: document.querySelector("#rbac-role").value,
    })});
    event.target.reset();
    document.querySelector("#rbac-role").value = "viewer";
    await loadRBAC();
  } catch (error) { errorBox.textContent = error.message; }
});

function formatOperationTime(value) {
  if (!value) return "—";
  const parsed = new Date(value);
  return Number.isNaN(parsed.getTime()) ? String(value) : parsed.toLocaleString();
}

function renderOperationAudit(container, detail) {
  const heading = document.createElement("h4");
  heading.textContent = "Связанный audit";
  container.appendChild(heading);

  if (detail.audit?.authorized === false) {
    const message = document.createElement("p");
    message.className = "muted";
    message.textContent = "Коррелированный audit недоступен для текущей роли.";
    container.appendChild(message);
    return;
  }

  if (detail.audit?.available === false) {
    const message = document.createElement("p");
    message.className = "error";
    message.role = "status";
    message.setAttribute("aria-live", "polite");
    message.textContent = `Core сообщил, что audit correlation временно недоступна${detail.audit?.error_code ? ` (${detail.audit.error_code})` : ""}.`;
    container.appendChild(message);
    return;
  }

  const events = detail.audit?.events || [];
  if (!events.length) {
    const message = document.createElement("p");
    message.className = "muted";
    message.textContent = "Связанных audit-событий нет.";
    container.appendChild(message);
    return;
  }

  const list = document.createElement("ul");
  list.className = "compact-list audit-list";
  for (const event of events) {
    const item = document.createElement("li");
    const actor = [event.actor, event.role].filter(Boolean).join(" / ") || "—";
    const target = event.target ? ` · ${event.target}` : "";
    const error = event.error_code ? ` · ${event.error_code}` : "";
    item.textContent = `${formatOperationTime(event.time)} · ${event.action || "—"} · ${event.result || "—"} · ${actor}${target}${error}`;
    list.appendChild(item);
  }
  container.appendChild(list);
}

function renderOperationDetail(container, detail) {
  container.querySelector("[data-operation-detail]")?.remove();
  const panel = document.createElement("section");
  panel.className = "setup-panel";
  panel.dataset.operationDetail = "true";
  panel.setAttribute("aria-labelledby", "operation-detail-title");

  const operation = detail.operation || {};
  const heading = document.createElement("h4");
  heading.id = "operation-detail-title";
  heading.textContent = "Детали операции";
  panel.appendChild(heading);
  appendTextLine(panel, "ID", operation.id || "—");
  appendTextLine(panel, "Тип", operation.kind || "—");
  appendTextLine(panel, "Статус", operation.status || "—");
  appendTextLine(panel, "Actor / role", [operation.actor, operation.role].filter(Boolean).join(" / ") || "—");
  appendTextLine(panel, "Target", operation.target || "—");
  appendTextLine(panel, "Начало", formatOperationTime(operation.started_at));
  appendTextLine(panel, "Завершение", formatOperationTime(operation.finished_at));
  appendTextLine(panel, "Error code", operation.error_code || "—");

  if (detail.health?.status === "degraded") {
    const warning = document.createElement("p");
    warning.className = "error";
    warning.role = "status";
    warning.setAttribute("aria-live", "polite");
    warning.textContent = "Core сообщает degraded health для связанной audit-проекции; сама запись операции остаётся authoritative.";
    panel.appendChild(warning);
  }

  const authority = document.createElement("p");
  authority.className = "muted";
  authority.textContent = "Данные операции и audit correlation загружаются напрямую из Core; Web не реконструирует историю и не меняет семантику операции.";
  panel.appendChild(authority);
  renderOperationAudit(panel, detail);
  container.appendChild(panel);
}

async function loadOperationDetail(operationID, container, button) {
  operationDetailGeneration += 1;
  const generation = operationDetailGeneration;
  container.querySelector("[data-operation-detail]")?.remove();

  const loading = document.createElement("section");
  loading.className = "setup-panel";
  loading.dataset.operationDetail = "true";
  loading.role = "status";
  loading.setAttribute("aria-live", "polite");
  loading.textContent = `Загрузка деталей операции ${operationID}…`;
  container.appendChild(loading);
  button.disabled = true;

  try {
    const detail = await api(`/api/v1/operations/${encodeURIComponent(operationID)}`);
    if (generation !== operationDetailGeneration) return;
    renderOperationDetail(container, detail);
  } catch (error) {
    if (generation !== operationDetailGeneration) return;
    loading.className = "error";
    loading.role = "alert";
    loading.removeAttribute("aria-live");
    loading.textContent = `Не удалось загрузить детали операции ${operationID}: ${error.message}`;
  } finally {
    if (generation === operationDetailGeneration && button.isConnected) button.disabled = false;
  }
}

async function loadRecentOperations(container) {
  container.textContent = "";
  container.hidden = false;

  const heading = document.createElement("h3");
  heading.textContent = "Последние операции";
  container.appendChild(heading);

  const status = document.createElement("p");
  status.className = "muted";
  status.role = "status";
  status.setAttribute("aria-live", "polite");
  status.textContent = "Загрузка последних операций…";
  container.appendChild(status);

  try {
    const data = await api("/api/v1/operations?limit=10");
    const records = Array.isArray(data.operations) ? data.operations : [];
    status.textContent = records.length ? `Показано операций: ${records.length}.` : "Операций пока нет.";

    const list = document.createElement("ul");
    list.className = "compact-list";
    for (const op of records) {
      const item = document.createElement("li");
      const info = document.createElement("span");
      info.textContent = `${op.kind || "—"} · ${op.status || "—"} · ${op.actor || "—"}`;
      item.appendChild(info);

      if (op.id) {
        const button = document.createElement("button");
        button.type = "button";
        button.className = "text-button inline-action";
        button.textContent = "Детали";
        button.setAttribute("aria-label", `Открыть детали операции ${op.id}`);
        button.addEventListener("click", () => loadOperationDetail(op.id, container, button));
        item.appendChild(button);
      }
      list.appendChild(item);
    }
    container.appendChild(list);
  } catch (error) {
    status.className = "error";
    status.role = "alert";
    status.removeAttribute("aria-live");
    status.textContent = `Не удалось загрузить операции: ${error.message}`;
  }
}

document.querySelectorAll(".nav-item").forEach((button) => {
  button.addEventListener("click", async () => {
    operationDetailGeneration += 1;
    document.querySelectorAll(".nav-item").forEach((item) => item.classList.remove("active")); button.classList.add("active");
    const [title, cardTitle, text] = pages[button.dataset.page];
    document.querySelector("#page-title").textContent = title; document.querySelector("#card-title").textContent = cardTitle; document.querySelector("#card-text").textContent = text;
    const fleet = document.querySelector("#fleet-nodes"); fleet.hidden = true; fleet.textContent = "";
    const fleetForm = document.querySelector("#fleet-form"); fleetForm.hidden = true;
    const users = document.querySelector("#rbac-users"); users.hidden = true; users.textContent = "";
    const rbacForm = document.querySelector("#rbac-create-form"); rbacForm.hidden = true;
    const systemDetails = document.querySelector("#system-details"); systemDetails.hidden = true; systemDetails.textContent = "";
    const networkInterfaces = document.querySelector("#network-interfaces"); networkInterfaces.hidden = true; networkInterfaces.textContent = "";
    const operations = document.querySelector("#operations-list"); operations.hidden = true; operations.textContent = "";
    const exportLink = document.querySelector("#diagnostics-export"); exportLink.hidden = true;
    if (button.dataset.page === "fleet") await loadFleet();
    if (button.dataset.page === "rbac" && currentUser?.role === "admin") await loadRBAC();
    if (button.dataset.page === "system") {
      try {
        const [summary, inventory] = await Promise.all([api("/api/v1/diagnostics/summary"), api("/api/v1/network/interfaces")]);
        systemDetails.textContent = `Uptime: ${Math.round(summary.uptime_seconds)} сек. · Operations: ${summary.operation_count} · Audit: ${summary.audit_readable ? "OK" : "Unavailable"}`;
        systemDetails.hidden = false;

        const heading = document.createElement("h3"); heading.textContent = `Сетевые интерфейсы (${inventory.count})`; networkInterfaces.appendChild(heading);
        const list = document.createElement("ul"); list.className = "compact-list";
        for (const iface of inventory.interfaces) {
          const li = document.createElement("li");
          const addresses = iface.addresses.length ? iface.addresses.join(", ") : "без адресов";
          const state = iface.flags.includes("up") ? "UP" : "DOWN";
          li.textContent = `${iface.name} · ${state} · MTU ${iface.mtu} · ${addresses}`;
          list.appendChild(li);
        }
        networkInterfaces.appendChild(list); networkInterfaces.hidden = false;

        if (currentUser?.role === "admin") {
          await loadRecentOperations(operations);
          exportLink.hidden = false;
        }
      } catch (error) { systemDetails.textContent = error.message; systemDetails.hidden = false; }
    }
  });
});

async function loadStatus() {
  try {
    const [health, readiness, version] = await Promise.all([api("/api/v1/health"), api("/api/v1/readiness"), api("/api/v1/version")]);
    document.querySelector("#health").textContent = health.status === "ok" ? "Healthy" : "Degraded";
    document.querySelector("#version").textContent = version.version; document.querySelector("#commit").textContent = version.commit; document.querySelector("#readiness").textContent = readiness.ready ? "Ready" : "Not ready";
  } catch { document.querySelector("#health").textContent = "Unavailable"; document.querySelector("#readiness").textContent = "Unknown"; }
}

restoreSession();