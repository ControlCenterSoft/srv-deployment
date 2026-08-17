(() => {
    "use strict";
    const statusBox = document.getElementById("adguardStatus");
    const actionsBox = document.getElementById("adguardActions");
    const message = document.getElementById("adguardMessage");
    let csrfToken = "";

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

    async function run(operation) {
        message.textContent = "";
        const response = await fetch(`/api/v1/adguard/${operation}`, {
            method: "POST",
            headers: {"X-CSRF-Token": csrfToken},
        });
        if (!response.ok) {
            message.textContent = "Операция не выполнена.";
            message.classList.add("error");
            return;
        }
        message.classList.remove("error");
        message.textContent = "Операция запущена.";
        window.setTimeout(load, 1200);
    }

    async function load() {
        const auth = await fetch("/api/v1/auth/status", {cache: "no-store"});
        const authPayload = await auth.json();
        csrfToken = (authPayload.data && authPayload.data.csrf_token) || "";

        const response = await fetch("/api/v1/adguard", {cache: "no-store"});
        if (!response.ok) {
            statusBox.textContent = "";
            actionsBox.textContent = "";
            return;
        }
        const payload = await response.json();
        const data = payload.data || {};
        const status = data.status || {};
        statusBox.textContent = "";
        statusBox.append(
            field("Установлен", data.installed ? "Да" : "Нет"),
            field("Состояние", status.state),
            field("Версия", status.version),
            field("Режим", status.mode),
            field("SOCKS", status.socks_host && status.socks_port ? `${status.socks_host}:${status.socks_port}` : null),
            field("Проверено", status.checked_at),
        );
        actionsBox.textContent = "";
        if (data.installed && data.can_write) {
            const buttons = [
                ["Подключить", "connect", "action-button"],
                ["Отключить", "disconnect", "secondary-button"],
                ["Обновить", "update", "secondary-button"],
                ["Обновить состояние", "refresh", "secondary-button"],
            ];
            for (const [label, op, cls] of buttons) {
                const button = document.createElement("button");
                button.type = "button";
                button.textContent = label;
                button.className = cls;
                button.addEventListener("click", () => run(op));
                actionsBox.appendChild(button);
            }
        }
    }

    load();
    window.setInterval(load, 15000);
})();
