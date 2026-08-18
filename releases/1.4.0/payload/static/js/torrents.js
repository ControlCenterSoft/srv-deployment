(() => {
    "use strict";
    const grid = document.getElementById("torrentGrid");

    function normalizedState(value) {
        return String(value || "").trim().toLowerCase();
    }

    function stateClass(value) {
        const state = normalizedState(value);
        if (["active", "running", "ready", "online"].includes(state)) return "status-ok";
        if (["failed", "error", "inactive", "dead"].includes(state)) return "status-error";
        return "";
    }

    function render(items) {
        grid.textContent = "";
        if (!items.length) {
            const empty = document.createElement("div");
            empty.className = "empty-state";
            empty.textContent = "Сервисы загрузки не обнаружены. После установки qBittorrent, TorrServer или другого управляемого сервиса он появится здесь автоматически.";
            grid.appendChild(empty);
            return;
        }

        for (const item of items) {
            const card = document.createElement("article");
            card.className = "service-card";

            const head = document.createElement("div");
            head.className = "service-card-title";
            const name = document.createElement("strong");
            name.textContent = item.name || "Сервис";
            const state = document.createElement("span");
            state.textContent = item.state || "—";
            const cssClass = stateClass(item.state);
            if (cssClass) state.classList.add(cssClass);
            head.append(name, state);

            const details = document.createElement("p");
            details.textContent = item.unit ? `systemd: ${item.unit}` : "Системный сервис";
            card.append(head, details);
            grid.appendChild(card);
        }
    }

    async function load() {
        grid.setAttribute("aria-busy", "true");
        try {
            const response = await fetch("/api/v1/torrents", {cache: "no-store"});
            if (response.status === 401) {
                window.top.location.replace("/login");
                return;
            }
            if (!response.ok) throw new Error(`HTTP ${response.status}`);
            const payload = await response.json();
            render((payload.data && payload.data.services) || []);
        } catch (_) {
            grid.textContent = "";
            const empty = document.createElement("div");
            empty.className = "empty-state";
            empty.setAttribute("role", "alert");
            empty.textContent = "Не удалось получить состояние сервисов загрузки. Повторная проверка будет выполнена автоматически.";
            grid.appendChild(empty);
        } finally {
            grid.setAttribute("aria-busy", "false");
        }
    }

    grid.setAttribute("aria-live", "polite");
    load();
    window.setInterval(load, 15000);
})();
