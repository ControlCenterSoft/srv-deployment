let csrfToken = "";
let currentUser = null;

const pages = {
  overview: ["Обзор", "Состояние платформы", "Runtime, health/readiness, audit и трассируемые операции."],
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

document.querySelectorAll(".nav-item").forEach((button) => {
  button.addEventListener("click", async () => {
    document.querySelectorAll(".nav-item").forEach((item) => item.classList.remove("active")); button.classList.add("active");
    const [title, cardTitle, text] = pages[button.dataset.page];
    document.querySelector("#page-title").textContent = title; document.querySelector("#card-title").textContent = cardTitle; document.querySelector("#card-text").textContent = text;
    const users = document.querySelector("#rbac-users"); users.hidden = true; users.textContent = "";
    const systemDetails = document.querySelector("#system-details"); systemDetails.hidden = true; systemDetails.textContent = "";
    const operations = document.querySelector("#operations-list"); operations.hidden = true; operations.textContent = "";
    const exportLink = document.querySelector("#diagnostics-export"); exportLink.hidden = true;
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
