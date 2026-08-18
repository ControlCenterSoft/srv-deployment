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
    let busyOperation = "";

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
        message.setAttribute("role", error ? "alert" : "status");
        message.setAttribute("aria-live", error ? "assertive" : "polite");
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
        if (busyOperation) return;
        setMessage("");
        busyOperation = operation;
        renderActions({installed: true, can_write: true});
        try {
            await post(`/api/v1/adguard/${operation}`);
            setMessage("Операция поставлена в очередь. Состояние обновится автоматически.");
            window.setTimeout(() => load().catch(() => {}), 1400);
        } catch (error) {
            setMessage(error.message || "Операция не выполнена.", true);
        } finally {
            busyOperation = "";
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
            const busy = busyOperation === operation;
            button.type = "button";
            button.textContent = busy ? "Выполняется…" : label;
            button.className = className;
            button.disabled = Boolean(busyOperation);
            button.setAttribute("aria-busy", busy ? "true" : "false");
            button.addEventListener("click", () => run(operation));
            actionsBox.appendChild(button);
        }
    }

    async function load() {
        statusBox.setAttribute("aria-busy", "true");
        try {
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
                setMessage("Нет прав на просмотр настроек AdGuard VPN.", true);
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
                mode.value = "SOCKS";
                socksHost.value = status.socks_host || "127.0.0.1";
                socksPort.value = Number(status.socks_port || 1080);
            }
        } finally {
            statusBox.setAttribute("aria-busy", "false");
        }
    }

    for (const control of [mode, socksHost, socksPort]) {
        control.addEventListener("input", () => { dirty = true; });
        control.addEventListener("change", () => { dirty = true; });
    }

    configForm.addEventListener("submit", async (event) => {
        event.preventDefault();
        setMessage("");
        save.disabled = true;
        save.setAttribute("aria-busy", "true");
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
        } finally {
            save.disabled = false;
            save.removeAttribute("aria-busy");
        }
    });

    message.setAttribute("aria-live", "polite");
    load().catch((error) => setMessage(error.message || "Не удалось получить состояние.", true));
    window.setInterval(() => load().catch(() => {}), 15000);
})();
