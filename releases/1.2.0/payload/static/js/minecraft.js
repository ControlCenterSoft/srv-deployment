(() => {
    "use strict";

    const byId = (id) => document.getElementById(id);
    const statusBox = byId("minecraftStatus");
    const actionsBox = byId("minecraftActions");
    const message = byId("minecraftMessage");
    const configPanel = byId("minecraftConfigPanel");
    const configForm = byId("minecraftConfigForm");
    const save = byId("minecraftSave");
    const configNote = byId("minecraftConfigNote");
    const controls = Array.from(configForm.querySelectorAll("input[name], select[name]"));
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
            await post(`/api/v1/minecraft/${operation}`);
            setMessage("Операция поставлена в очередь.");
            window.setTimeout(() => load().catch(() => {}), 1400);
        } catch (error) {
            setMessage(error.message || "Операция не выполнена.", true);
        }
    }

    function renderActions(data) {
        actionsBox.replaceChildren();
        if (!data.installed || !data.can_write || !data.service) return;
        const state = String(data.state || "");
        const buttons = [];
        if (state === "active") {
            buttons.push(["Перезапустить", "restart", "action-button"]);
            buttons.push(["Остановить", "stop", "secondary-button"]);
        } else {
            buttons.push(["Запустить", "start", "action-button"]);
        }
        for (const [label, operation, className] of buttons) {
            const button = document.createElement("button");
            button.type = "button";
            button.className = className;
            button.textContent = label;
            button.addEventListener("click", () => run(operation));
            actionsBox.appendChild(button);
        }
    }

    function applyProperties(properties) {
        for (const control of controls) {
            const key = control.name;
            if (!Object.prototype.hasOwnProperty.call(properties, key)) continue;
            control.value = String(properties[key]);
        }
    }

    function desiredProperties() {
        const result = {};
        for (const control of controls) {
            result[control.name] = control.value;
        }
        return result;
    }

    async function load() {
        const auth = await fetch("/api/v1/auth/status", {cache: "no-store"});
        if (!auth.ok) {
            window.top.location.replace("/login");
            return;
        }
        const authPayload = await auth.json();
        csrfToken = (authPayload.data && authPayload.data.csrf_token) || "";

        const response = await fetch("/api/v1/minecraft", {cache: "no-store"});
        if (response.status === 403) {
            statusBox.replaceChildren();
            actionsBox.replaceChildren();
            configPanel.hidden = true;
            setMessage("Нет прав на модуль Minecraft.", true);
            return;
        }
        if (!response.ok) throw new Error(`HTTP ${response.status}`);
        const payload = await response.json();
        const data = payload.data || {};
        const properties = data.properties || {};

        statusBox.replaceChildren(
            field("Установлен", data.installed ? "Да" : "Нет"),
            field("Состояние", data.state),
            field("Служба", data.service),
            field("Автозапуск", data.enabled ? "Включён" : "Выключен"),
            field("Файл настроек", data.properties_path),
            field("Мир", properties["level-name"]),
        );
        renderActions(data);

        const configurable = Boolean(data.properties_path);
        configPanel.hidden = !configurable;
        save.disabled = !data.can_write || !configurable;
        for (const control of controls) control.disabled = !data.can_write || !configurable;
        configNote.textContent = data.can_write
            ? "При сохранении активный сервер автоматически перезапускается для применения параметров."
            : "Доступно только чтение параметров Minecraft.";
        if (!dirty) applyProperties(properties);
    }

    for (const control of controls) {
        control.addEventListener("input", () => { dirty = true; });
        control.addEventListener("change", () => { dirty = true; });
    }

    configForm.addEventListener("submit", async (event) => {
        event.preventDefault();
        setMessage("");
        try {
            await post("/api/v1/minecraft/config", {properties: desiredProperties()});
            dirty = false;
            setMessage("Настройки Minecraft поставлены в очередь на применение.");
            window.setTimeout(() => load().catch(() => {}), 1600);
        } catch (error) {
            setMessage(error.message || "Не удалось сохранить настройки Minecraft.", true);
        }
    });

    load().catch((error) => setMessage(error.message || "Не удалось получить состояние Minecraft.", true));
    window.setInterval(() => load().catch(() => {}), 15000);
})();
