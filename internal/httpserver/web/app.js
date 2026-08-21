let csrfToken = "";
let currentUser = null;

const pages = {
  overview: ["Обзор", "Состояние платформы", "Runtime, health/readiness, audit и трассируемые операции."],
  fleet: ["Серверы", "Управляемые серверы", "Единый инвентарь серверов с одноразовым безопасным enrollment."],
  market: ["Маркет", "Маркет", "Module lifecycle будет подключён после завершения foundation релиза."],
  rbac: ["RBAC", "RBAC", "Локальные пользователи и server-side роли admin/viewer."],
  system: ["Система", "Система", "Runtime diagnostics и безопасная эксплуатационная информация платформы."],
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

async function issueEnrollment(node, li) {
  const previous = li.querySelector(".enrollment-secret");
  if (previous) previous.remove();
  try {
    const data = await api(`/api/v1/fleet/nodes/${encodeURIComponent(node.id)}/enrollment`, {method:"POST", body:"{}"});
    const box = document.createElement("div");
    box.className = "enrollment-secret";
    const expires = data.enrollment.expires_at ? new Date(data.enrollment.expires_at).toLocaleString() : "через 15 минут";
    box.textContent = `Одноразовый enrollment token (показывается только сейчас, действует до ${expires}): ${data.enrollment.token}`;
    li.appendChild(box);
    await loadFleet();
  } catch (error) {
    const box = document.createElement("div"); box.className = "error enrollment-secret"; box.textContent = error.message; li.appendChild(box);
  }
}

async function loadFleet() {
  const container = document.querySelector("#fleet-nodes");
  const form = document.querySelector("#fleet-form");
  container.textContent = "";
  try {
    const data = await api("/api/v1/fleet/nodes");
    const summary = document.createElement("p");
    summary.textContent = `Всего серверов: ${data.summary.total} · Enrolled: ${data.summary.enrolled} · Ожидают enrollment: ${data.summary.pending_enrollment}`;
    container.appendChild(summary);
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

document.querySelectorAll(".nav-item").forEach((button) => {
  button.addEventListener("click", async () => {
    document.querySelectorAll(".nav-item").forEach((item) => item.classList.remove("active")); button.classList.add("active");
    const [title, cardTitle, text] = pages[button.dataset.page];
    document.querySelector("#page-title").textContent = title; document.querySelector("#card-title").textContent = cardTitle; document.querySelector("#card-text").textContent = text;
    const fleet = document.querySelector("#fleet-nodes"); fleet.hidden = true; fleet.textContent = "";
    const fleetForm = document.querySelector("#fleet-form"); fleetForm.hidden = true;
    const users = document.querySelector("#rbac-users"); users.hidden = true; users.textContent = "";
    const systemDetails = document.querySelector("#system-details"); systemDetails.hidden = true; systemDetails.textContent = "";
    const operations = document.querySelector("#operations-list"); operations.hidden = true; operations.textContent = "";
    const exportLink = document.querySelector("#diagnostics-export"); exportLink.hidden = true;
    if (button.dataset.page === "fleet") await loadFleet();
    if (button.dataset.page === "rbac" && currentUser?.role === "admin") {
      try {
        const data = await api("/api/v1/rbac/users");
        users.innerHTML = `<h3>Локальные пользователи</h3><ul>${data.users.map((u) => `<li>${u.username} — ${u.role}${u.blocked ? " — blocked" : ""}</li>`).join("")}</ul>`;
        users.hidden = false;
      } catch (error) { users.textContent = error.message; users.hidden = false; }
    }
    if (button.dataset.page === "system") {
      try {
        const summary = await api("/api/v1/diagnostics/summary");
        systemDetails.textContent = `Uptime: ${Math.round(summary.uptime_seconds)} сек. · Operations: ${summary.operation_count} · Audit: ${summary.audit_readable ? "OK" : "Unavailable"}`;
        systemDetails.hidden = false;
        if (currentUser?.role === "admin") {
          const data = await api("/api/v1/operations?limit=10");
          const title = document.createElement("h3"); title.textContent = "Последние операции"; operations.appendChild(title);
          const list = document.createElement("ul"); list.className = "compact-list";
          for (const op of data.operations) {
            const li = document.createElement("li"); li.textContent = `${op.kind} · ${op.status} · ${op.actor}`; list.appendChild(li);
          }
          operations.appendChild(list); operations.hidden = false; exportLink.hidden = false;
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
