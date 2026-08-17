(() => {
    "use strict";

    const identityBadge = document.getElementById("identityBadge");
    const form = document.getElementById("grantForm");
    const source = document.getElementById("grantSource");
    const group = document.getElementById("grantGroup");
    const groupList = document.getElementById("availableGroups");
    const moduleSelect = document.getElementById("grantModule");
    const access = document.getElementById("grantAccess");
    const rows = document.getElementById("grantRows");
    const userRows = document.getElementById("userRows");
    const message = document.getElementById("grantMessage");
    const pamState = document.getElementById("pamState");
    const domainState = document.getElementById("domainState");
    const ssoState = document.getElementById("ssoState");
    const localUserCount = document.getElementById("localUserCount");
    const domainUserCount = document.getElementById("domainUserCount");
    const groupCount = document.getElementById("groupCount");

    let csrfToken = "";
    let modules = {};
    let directoryGroups = [];

    function text(value) {
        return value == null ? "—" : String(value);
    }

    function setMessage(value, error = false) {
        message.textContent = value || "";
        message.classList.toggle("error", error);
    }

    function sourceLabel(value) {
        if (value === "domain") return "Домен";
        if (value === "local") return "Локально";
        return "Любой";
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

    function renderGrantRows(grants) {
        rows.textContent = "";
        for (const grant of grants) {
            const tr = document.createElement("tr");
            const values = [
                sourceLabel(grant.source),
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

    function renderUsers(users) {
        userRows.textContent = "";
        for (const user of users) {
            const tr = document.createElement("tr");
            for (const value of [
                user.username,
                sourceLabel(user.source),
                user.uid,
                user.is_admin ? "Полный доступ" : "По ролям групп",
            ]) {
                const td = document.createElement("td");
                td.textContent = text(value);
                tr.appendChild(td);
            }
            userRows.appendChild(tr);
        }
    }

    function renderDirectory(directory) {
        const authentication = directory.authentication || {};
        const users = directory.users || [];
        directoryGroups = directory.groups || [];
        pamState.textContent = authentication.pam ? "Активна" : "Нет";
        domainState.textContent = authentication.domain ? "Подключён" : "Нет";
        ssoState.textContent = authentication.sso ? "Активно" : "Нет";
        localUserCount.textContent = users.filter((item) => item.source === "local").length;
        domainUserCount.textContent = users.filter((item) => item.source === "domain").length;
        groupCount.textContent = directoryGroups.length;
        renderUsers(users);
        renderGroupOptions();
    }

    function renderGroupOptions() {
        groupList.textContent = "";
        const selectedSource = source.value;
        for (const item of directoryGroups) {
            if (selectedSource !== "any" && item.source !== selectedSource) continue;
            const option = document.createElement("option");
            option.value = item.name;
            option.label = sourceLabel(item.source);
            groupList.appendChild(option);
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

        const [grantResponse, directoryResponse] = await Promise.all([
            fetch("/api/v1/access/grants", {cache: "no-store"}),
            fetch("/api/v1/access/directory", {cache: "no-store"}),
        ]);
        if (grantResponse.status === 403 || directoryResponse.status === 403) {
            form.hidden = true;
            setMessage("Управление правами доступно администратору сервера.", true);
            return;
        }
        if (!grantResponse.ok || !directoryResponse.ok) {
            throw new Error("failed to load access data");
        }
        const grants = await grantResponse.json();
        const directory = await directoryResponse.json();
        modules = grants.data.modules || {};
        renderModules();
        renderGrantRows(grants.data.grants || []);
        renderDirectory(directory.data || {});
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

    source.addEventListener("change", renderGroupOptions);

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
