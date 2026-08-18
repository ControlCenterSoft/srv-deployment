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
            const card = document.createElement("article");
            card.className = "service-card";
            const head = document.createElement("div");
            head.className = "service-card-title";
            const title = document.createElement("strong");
            title.textContent = "Сервисы загрузки не обнаружены";
            const state = document.createElement("span");
            state.textContent = "Не установлены";
            head.append(title, state);
            const details = document.createElement("p");
            details.textContent = "Control Center не обнаружил управляемые торрент- или медиасервисы на сервере.";
            card.append(head, details);
            grid.appendChild(card);
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
            const card = document.createElement("article");
            card.className = "service-card";
            const head = document.createElement("div");
            head.className = "service-card-title";
            const title = document.createElement("strong");
            title.textContent = "Не удалось получить состояние";
            const state = document.createElement("span");
            state.className = "status-error";
            state.textContent = "Ошибка";
            head.append(title, state);
            const details = document.createElement("p");
            details.textContent = "Повторная проверка будет выполнена автоматически.";
            card.append(head, details);
            grid.appendChild(card);
        }
    }

    load();
    window.setInterval(load, 15000);
})();
