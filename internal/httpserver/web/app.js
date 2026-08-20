const pages = {
  overview: ["Обзор", "Состояние платформы", "Базовый runtime и API Control Center."],
  market: ["Маркет", "Маркет", "Module lifecycle будет подключён после утверждения Platform SDK acceptance."],
  rbac: ["RBAC", "RBAC", "Authentication и server-side RBAC входят в следующий этап alpha.2."],
  system: ["Система", "Система", "Системные операции будут выполняться только через ограниченный Privileged Worker."],
};

document.querySelectorAll(".nav-item").forEach((button) => {
  button.addEventListener("click", () => {
    document.querySelectorAll(".nav-item").forEach((item) => item.classList.remove("active"));
    button.classList.add("active");
    const [title, cardTitle, text] = pages[button.dataset.page];
    document.querySelector("#page-title").textContent = title;
    document.querySelector("#card-title").textContent = cardTitle;
    document.querySelector("#card-text").textContent = text;
  });
});

async function loadStatus() {
  try {
    const [health, readiness, version] = await Promise.all([
      fetch("/api/v1/health", {cache: "no-store"}).then((r) => r.json()),
      fetch("/api/v1/readiness", {cache: "no-store"}).then((r) => r.json()),
      fetch("/api/v1/version", {cache: "no-store"}).then((r) => r.json()),
    ]);
    document.querySelector("#health").textContent = health.status === "ok" ? "Healthy" : "Degraded";
    document.querySelector("#version").textContent = version.version;
    document.querySelector("#commit").textContent = version.commit;
    document.querySelector("#readiness").textContent = readiness.ready ? "Ready" : "Not ready";
  } catch {
    document.querySelector("#health").textContent = "Unavailable";
    document.querySelector("#readiness").textContent = "Unknown";
  }
}

loadStatus();
