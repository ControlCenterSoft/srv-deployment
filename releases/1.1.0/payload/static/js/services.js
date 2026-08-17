(() => {
    "use strict";

    const grid = document.getElementById("serviceGrid");
    const message = document.getElementById("serviceMessage");
    let csrfToken = "";

    function setMessage(value, error = false) {
        message.textContent = value || "";
        message.classList.toggle("error", error);
    }

    async function auth() {
        const response = await fetch("/api/v1/auth/status", {cache: "no-store"});
        const payload = await response.json();
        if (!response.ok || !payload.data || !payload.data.authenticated) {
            window.top.location.replace("/login");
            return false;
        }
        csrfToken = payload.data.csrf_token || "";
        return true;
    }

    async function action(serviceId, operation) {
        setMessage("");
        const response = await fetch(`/api/v1/services/${encodeURIComponent(serviceId)}/${operation}`, {
            method: "POST",
            headers: {"X-CSRF-Token": csrfToken},
        });
        if (!response.ok) {
            setMessage("Операция не выполнена.", true);
            return;
        }
        setMessage("Операция запущена.");
        window.setTimeout(load, 1200);
    }

    function render(items) {
        grid.textContent = "";
        for (const item of items) {
            const card = document.createElement("article");
            card.className = "service-card";
            const title = document.createElement("div");
            title.className = "service-card-title";
            const name = document.createElement("strong");
            name.textContent = item.name;
            const state = document.createElement("span");
            state.textContent = item.installed ? "Установлен" : "Не установлен";
            title.append(name, state);
            const description = document.createElement("p");
            description.textContent = item.description || "";
            const actions = document.createElement("div");
            actions.className = "service-actions";
            if (item.can_write) {
                const button = document.createElement("button");
                button.type = "button";
                button.textContent = item.installed ? "Удалить" : "Установить";
                button.className = item.installed ? "danger-button" : "action-button";
                button.addEventListener("click", () => action(item.id, item.installed ? "remove" : "install"));
                actions.appendChild(button);
            }
            card.append(title, description, actions);
            grid.appendChild(card);
        }
    }

    async function load() {
        if (!(await auth())) return;
        const response = await fetch("/api/v1/services", {cache: "no-store"});
        if (!response.ok) {
            setMessage("Не удалось получить состояние сервисов.", true);
            return;
        }
        const payload = await response.json();
        render((payload.data && payload.data.items) || []);
    }

    load();
})();
