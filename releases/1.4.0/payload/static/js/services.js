(() => {
    "use strict";

    const grid = document.getElementById("serviceGrid");
    const message = document.getElementById("serviceMessage");
    const ui = window.ControlCenterUI;
    let csrfToken = "";
    const busyServices = new Set();

    const visual = {
        "samba-ad-dc": {icon: "◇", theme: "green", hint: "Directory & Access"},
        "isc-dhcp-server": {icon: "⇄", theme: "blue", hint: "DHCP Server"},
        "tftpd-hpa": {icon: "PX", theme: "purple", hint: "PXE / TFTP"},
        "adguard-vpn": {icon: "◈", theme: "cyan", hint: "VPN & Filtering"},
    };

    function serviceVisual(item) {
        const known = visual[item.id];
        if (known) return known;
        const id = String(item.id || "").toLowerCase();
        if (id.includes("pxe") || id.includes("tftp")) return {icon: "PX", theme: "purple", hint: "Network Boot"};
        if (id.includes("dhcp")) return {icon: "⇄", theme: "blue", hint: "DHCP Server"};
        if (id.includes("samba") || id.includes("domain")) return {icon: "◇", theme: "green", hint: "Directory & Access"};
        if (id.includes("vpn") || id.includes("guard")) return {icon: "◈", theme: "cyan", hint: "VPN & Filtering"};
        return {icon: "▦", theme: "blue", hint: "Managed Service"};
    }

    function setMessage(value, error = false) {
        message.textContent = value || "";
        message.classList.toggle("error", error);
        message.setAttribute("role", error ? "alert" : "status");
        message.setAttribute("aria-live", error ? "assertive" : "polite");
        if (value && ui) ui.toast(value, error ? "error" : "info", error ? 5200 : 3200);
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

    async function confirmRemoval(serviceId, serviceName) {
        const prompt = serviceId === "samba-ad-dc"
            ? "Удалить Samba AD DC? Control Center сначала создаст резервную копию домена. База домена и данные сетевых ресурсов не будут очищены автоматически."
            : `Удалить сервис «${serviceName || serviceId}»? Служба будет остановлена, а управляемые пакеты удалены.`;
        return ui
            ? ui.confirm(prompt, {title: "Удаление сервиса", confirmLabel: "Удалить", danger: true})
            : window.confirm(prompt);
    }

    async function action(serviceId, serviceName, operation) {
        if (busyServices.has(serviceId)) return;
        setMessage("");
        if (operation === "remove" && !(await confirmRemoval(serviceId, serviceName))) return;

        busyServices.add(serviceId);
        renderLastItems();
        try {
            const response = await fetch(`/api/v1/services/${encodeURIComponent(serviceId)}/${operation}`, {
                method: "POST",
                headers: {"X-CSRF-Token": csrfToken},
            });
            if (!response.ok) {
                let detail = "";
                try {
                    const payload = await response.json();
                    detail = payload.detail || payload.error || "";
                } catch (_) {}
                setMessage(detail || "Операция не выполнена.", true);
                return;
            }
            setMessage(operation === "remove"
                ? "Удаление запущено. Состояние будет обновлено автоматически."
                : "Установка запущена. Состояние будет обновлено автоматически.");
            window.setTimeout(() => load().catch(() => {}), 1400);
        } finally {
            window.setTimeout(() => {
                busyServices.delete(serviceId);
                renderLastItems();
            }, 700);
        }
    }

    function statusText(item) {
        const status = item.status || {};
        const parts = [];
        if (status.state) parts.push(status.state);
        if (status.realm) parts.push(status.realm);
        if (status.version) parts.push(status.version);
        return parts.join(" · ");
    }

    let lastItems = [];
    function renderLastItems() { render(lastItems); }

    function render(items) {
        lastItems = Array.isArray(items) ? items : [];
        grid.textContent = "";
        if (!lastItems.length) {
            const empty = document.createElement("div");
            empty.className = "empty-state";
            empty.textContent = "Управляемые сервисы пока не обнаружены.";
            grid.appendChild(empty);
            return;
        }
        for (const item of lastItems) {
            const style = serviceVisual(item);
            const card = document.createElement("article");
            card.className = `service-card theme-${style.theme}`;
            card.setAttribute("aria-busy", busyServices.has(item.id) ? "true" : "false");
            const title = document.createElement("div");
            title.className = "service-card-title";
            const icon = document.createElement("span");
            icon.className = "service-card-icon";
            icon.textContent = style.icon;
            icon.setAttribute("aria-hidden", "true");
            const titleCopy = document.createElement("div");
            titleCopy.className = "service-title-copy";
            const name = document.createElement("strong");
            name.textContent = item.name;
            const hint = document.createElement("small");
            hint.textContent = style.hint;
            titleCopy.append(name, hint);
            const state = document.createElement("span");
            state.className = `service-state-badge ${item.installed ? "status-ok" : "status-error"}`;
            state.textContent = item.installed ? "Установлен" : "Не установлен";
            title.append(icon, titleCopy, state);
            const description = document.createElement("p");
            description.textContent = item.description || "Управляемый компонент Control Center.";
            const status = document.createElement("p");
            status.className = "service-status";
            status.textContent = statusText(item);
            const actions = document.createElement("div");
            actions.className = "service-actions";
            if (item.can_write) {
                const button = document.createElement("button");
                const busy = busyServices.has(item.id);
                button.type = "button";
                button.textContent = busy ? "Выполняется…" : (item.installed ? "Удалить" : "Установить");
                button.className = item.installed ? "danger-button" : "action-button";
                button.disabled = busy;
                button.setAttribute("aria-busy", busy ? "true" : "false");
                button.addEventListener("click", () => action(item.id, item.name, item.installed ? "remove" : "install"));
                actions.appendChild(button);
            } else {
                const locked = document.createElement("span");
                locked.className = "service-status";
                locked.textContent = "Только просмотр";
                actions.appendChild(locked);
            }
            card.append(title, description);
            if (status.textContent) card.appendChild(status);
            card.appendChild(actions);
            grid.appendChild(card);
        }
    }

    async function load() {
        if (!(await auth())) return;
        grid.setAttribute("aria-busy", "true");
        try {
            const response = await fetch("/api/v1/services", {cache: "no-store"});
            if (!response.ok) {
                setMessage("Не удалось получить состояние сервисов.", true);
                return;
            }
            const payload = await response.json();
            render((payload.data && payload.data.items) || []);
        } finally {
            grid.setAttribute("aria-busy", "false");
        }
    }

    message.setAttribute("aria-live", "polite");
    load().catch(() => setMessage("Не удалось загрузить список сервисов.", true));
})();
