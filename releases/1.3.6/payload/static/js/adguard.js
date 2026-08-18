(() => {
    "use strict";

    const byId = (id) => document.getElementById(id);
    const statusBox = byId("adguardStatus");
    const actionsBox = byId("adguardActions");
    const message = byId("adguardMessage");
    const configPanel = byId("adguardConfigPanel");
    const configForm = byId("adguardConfigForm");
    const mode = byId("adguardMode");
    const socksHost = byId("adguardSocksHost");
    const socksPort = byId("adguardSocksPort");
    const save = byId("adguardSave");
    let csrfToken = "";
    let dirty = false;

    function field(label, value) {
        const item = document.createElement("div");
        item.className = "status-item";
        const caption = document.createElement("span");
        caption.textContent = label;
        const strong = document.createElement("strong");
        strong.textContent = value == null || value === "" ? "—" : String(value);
        item.append(caption, strong);
        return item;
    }

    function setMessage(value, error = false) {
        message.textContent = value || "";
        message.classList.toggle("error", error);
    }

    async function post(url, body = null) {
        const headers = {"X-CSRF-Token": csrfToken};
        const options = {method: "POST", headers};
        if (body !== null) {
            headers["Content-Type"] = "application/json";
            options.body = JSON.stringify(body);
        }
        const response = await fetch(url, options);
        if (!response.ok) {
            let detail = "";
            try {
                const payload = await response.json();
                detail = payload.detail || payload.error || "";
            } catch (_) {}
            throw new Error(detail || `HTTP ${response.status}`);
        }
        return response.json();
    }

    async function run(operation) {
        setMessage("");
        try {
            await post(`/api/v1/adguard/${operation}`);
            setMessage("Операция поставлена в очередь.");
            window.setTimeout(() => load().catch(() => {}), 1400);
        } catch (error) {
            setMessage(error.message || "Операция не выполнена.", true);
        }
    }

    function renderActions(data) {
        actionsBox.replaceChildren();
        if (!data.installed || !data.can_write) return;
        const buttons = [
            ["Подключить", "connect", "action-button"],
            ["Отключить", "disconnect", "secondary-button"],
            ["Обновить", "update", "secondary-button"],
            ["Обновить состояние", "refresh", "secondary-button"],
        ];
        for (const [label, operation, className] of buttons) {
            const button = document.createElement("button");
            button.type = "button";
            button.textContent = label;
            button.className = className;
            button.addEventListener("click", () => run(operation));
            actionsBox.appendChild(button);
        }
    }

    async function load() {
        const auth = await fetch("/api/v1/auth/status", {cache: "no-store"});
        if (!auth.ok) {
            window.top.location.replace("/login");
            return;
        }
        const authPayload = await auth.json();
        csrfToken = (authPayload.data && authPayload.data.csrf_token) || "";

        const response = await fetch("/api/v1/adguard", {cache: "no-store"});
        if (response.status === 403) {
            statusBox.replaceChildren();
            actionsBox.replaceChildren();
            configPanel.hidden = true;
            return;
        }
        if (!response.ok) throw new Error(`HTTP ${response.status}`);

        const payload = await response.json();
        const data = payload.data || {};
        const status = data.status || {};
        statusBox.replaceChildren(
            field("Установлен", data.installed ? "Да" : "Нет"),
            field("Состояние", status.state),
            field("Версия", status.version),
            field("Режим", status.mode),
            field("SOCKS", status.socks_host && status.socks_port ? `${status.socks_host}:${status.socks_port}` : null),
            field("Проверено", status.checked_at),
        );
        renderActions(data);

        configPanel.hidden = !data.installed;
        save.disabled = !data.can_write;
        mode.disabled = !data.can_write;
        socksHost.disabled = !data.can_write;
        socksPort.disabled = !data.can_write;
        if (!dirty) {
            mode.value = String(status.mode || "SOCKS").toUpperCase() === "SOCKS" ? "SOCKS" : "SOCKS";
            socksHost.value = status.socks_host || "127.0.0.1";
            socksPort.value = Number(status.socks_port || 1080);
        }
    }

    for (const control of [mode, socksHost, socksPort]) {
        control.addEventListener("input", () => { dirty = true; });
        control.addEventListener("change", () => { dirty = true; });
    }

    configForm.addEventListener("submit", async (event) => {
        event.preventDefault();
        setMessage("");
        try {
            await post("/api/v1/adguard/config", {
                mode: mode.value,
                socks_host: socksHost.value.trim(),
                socks_port: Number(socksPort.value),
            });
            dirty = false;
            setMessage("Настройки поставлены в очередь на применение.");
            window.setTimeout(() => load().catch(() => {}), 1400);
        } catch (error) {
            setMessage(error.message || "Не удалось сохранить настройки.", true);
        }
    });

    load().catch((error) => setMessage(error.message || "Не удалось получить состояние.", true));
    window.setInterval(() => load().catch(() => {}), 15000);
})();
