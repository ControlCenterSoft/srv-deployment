(() => {
    "use strict";

    const grid = document.getElementById("serviceGrid");
    const message = document.getElementById("serviceMessage");
    let csrfToken = "";

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
        if (serviceId === "samba-ad-dc" && operation === "remove") {
            const approved = window.confirm(
                "Удалить пакеты Samba AD DC? Перед удалением Control Center создаст резервную копию домена, а база домена и данные сетевых ресурсов не будут очищены."
            );
            if (!approved) return;
        }
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
        setMessage("Операция запущена. Состояние будет обновлено автоматически.");
        window.setTimeout(load, 1400);
    }

    function statusText(item) {
        const status = item.status || {};
        const parts = [];
        if (status.state) parts.push(status.state);
        if (status.realm) parts.push(status.realm);
        if (status.version) parts.push(status.version);
        return parts.join(" · ");
    }

    function render(items) {
        grid.textContent = "";
        for (const item of items) {
            const style = serviceVisual(item);
            const card = document.createElement("article");
            card.className = `service-card theme-${style.theme}`;

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
                button.type = "button";
                button.textContent = item.installed ? "Удалить" : "Установить";
                button.className = item.installed ? "danger-button" : "action-button";
                button.addEventListener("click", () => action(item.id, item.installed ? "remove" : "install"));
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
