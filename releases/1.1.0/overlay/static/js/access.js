(() => {
    "use strict";

    const identityBadge = document.getElementById("identityBadge");
    const form = document.getElementById("grantForm");
    const source = document.getElementById("grantSource");
    const group = document.getElementById("grantGroup");
    const moduleSelect = document.getElementById("grantModule");
    const access = document.getElementById("grantAccess");
    const rows = document.getElementById("grantRows");
    const message = document.getElementById("grantMessage");

    let csrfToken = "";
    let modules = {};

    function text(value) {
        return value == null ? "—" : String(value);
    }

    function setMessage(value, error = false) {
        message.textContent = value || "";
        message.classList.toggle("error", error);
    }

    function renderModules() {
        moduleSelect.textContent = "";
        for (const [key, label] of Object.entries(modules)) {
            const option = document.createElement("option");
            option.value = key;
            option.textContent = label;
            moduleSelect.appendChild(option);
        }
    }

    function renderRows(grants) {
        rows.textContent = "";
        for (const grant of grants) {
            const tr = document.createElement("tr");
            const values = [
                grant.source === "domain" ? "Домен" : grant.source === "local" ? "Локально" : "Любой",
                grant.group_name,
                modules[grant.module] || grant.module,
                grant.access === "write" ? "Запись" : "Чтение",
                grant.updated_by,
            ];
            for (const value of values) {
                const td = document.createElement("td");
                td.textContent = text(value);
                tr.appendChild(td);
            }
            const actionCell = document.createElement("td");
            const remove = document.createElement("button");
            remove.type = "button";
            remove.className = "remove-grant";
            remove.textContent = "Удалить";
            remove.addEventListener("click", () => removeGrant(grant.id));
            actionCell.appendChild(remove);
            tr.appendChild(actionCell);
            rows.appendChild(tr);
        }
    }

    async function load() {
        const statusResponse = await fetch("/api/v1/auth/status", {cache: "no-store"});
        if (!statusResponse.ok) {
            window.top.location.replace("/login");
            return;
        }
        const status = await statusResponse.json();
        const identity = status.data && status.data.identity;
        csrfToken = (status.data && status.data.csrf_token) || "";
        identityBadge.textContent = identity ? identity.username : "—";

        const response = await fetch("/api/v1/access/grants", {cache: "no-store"});
        if (response.status === 403) {
            form.hidden = true;
            setMessage("Управление правами доступно администратору сервера.", true);
            return;
        }
        if (!response.ok) {
            throw new Error("failed to load grants");
        }
        const payload = await response.json();
        modules = payload.data.modules || {};
        renderModules();
        renderRows(payload.data.grants || []);
    }

    async function removeGrant(id) {
        setMessage("");
        const response = await fetch(`/api/v1/access/grants/${encodeURIComponent(id)}`, {
            method: "DELETE",
            headers: {"X-CSRF-Token": csrfToken},
        });
        if (!response.ok) {
            setMessage("Не удалось удалить назначение.", true);
            return;
        }
        await load();
        setMessage("Назначение удалено.");
    }

    form.addEventListener("submit", async (event) => {
        event.preventDefault();
        setMessage("");
        const response = await fetch("/api/v1/access/grants", {
            method: "POST",
            headers: {
                "Content-Type": "application/json",
                "X-CSRF-Token": csrfToken,
            },
            body: JSON.stringify({
                source: source.value,
                group_name: group.value.trim(),
                module: moduleSelect.value,
                access: access.value,
            }),
        });
        if (!response.ok) {
            setMessage("Не удалось сохранить назначение прав.", true);
            return;
        }
        group.value = "";
        await load();
        setMessage("Права сохранены.");
    });

    load().catch(() => setMessage("Не удалось загрузить права пользователей.", true));
})();
