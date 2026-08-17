(() => {
    "use strict";

    const byId = (id) => document.getElementById(id);
    const identityBadge = byId("identityBadge");
    const rows = byId("grantRows");
    const message = byId("grantMessage");
    const pamState = byId("pamState");
    const domainState = byId("domainState");
    const ssoState = byId("ssoState");
    const localUserCount = byId("localUserCount");
    const domainUserCount = byId("domainUserCount");
    const groupCount = byId("groupCount");
    const groupSubjectCount = byId("groupSubjectCount");
    const userSubjectCount = byId("userSubjectCount");
    const subjectGrid = document.querySelector(".subject-grid");

    const controls = {
        group: {
            form: byId("groupGrantForm"), source: byId("groupGrantSource"),
            subject: byId("groupGrantSubject"), module: byId("groupGrantModule"),
            access: byId("groupGrantAccess"),
        },
        user: {
            form: byId("userGrantForm"), source: byId("userGrantSource"),
            subject: byId("userGrantSubject"), module: byId("userGrantModule"),
            access: byId("userGrantAccess"),
        },
    };

    let csrfToken = "";
    let modules = {};
    let directoryGroups = [];
    let directoryUsers = [];

    function text(value) {
        return value == null || value === "" ? "—" : String(value);
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

    function subjectTypeLabel(value) {
        return value === "user" ? "Пользователь" : "Группа";
    }

    function accessLabel(value) {
        if (value === "admin") return "Полный администратор";
        return value === "write" ? "Запись" : "Чтение";
    }

    function addBadge(cell, label, className) {
        const badge = document.createElement("span");
        badge.className = className;
        badge.textContent = label;
        cell.appendChild(badge);
    }

    function renderModuleOptions() {
        for (const control of Object.values(controls)) {
            control.module.replaceChildren();
            for (const [key, label] of Object.entries(modules)) {
                const option = document.createElement("option");
                option.value = key;
                option.textContent = label;
                control.module.appendChild(option);
            }
            syncAccessMode(control);
        }
    }

    function syncAccessMode(control) {
        const fullAdmin = control.access.value === "admin";
        control.module.disabled = fullAdmin;
        control.module.title = fullAdmin
            ? "Для полного администратора право действует на весь Control Center."
            : "";
    }

    function renderGrantRows(grants) {
        rows.replaceChildren();
        if (!grants.length) {
            const tr = document.createElement("tr");
            const td = document.createElement("td");
            td.colSpan = 7;
            td.className = "empty-row";
            td.textContent = "Назначенных прав пока нет.";
            tr.appendChild(td);
            rows.appendChild(tr);
            return;
        }

        for (const grant of grants) {
            const tr = document.createElement("tr");
            const subjectType = grant.subject_type || "group";
            const subjectName = grant.subject_name || grant.group_name;

            const typeCell = document.createElement("td");
            addBadge(typeCell, subjectTypeLabel(subjectType), `subject-type-badge ${subjectType}`);
            tr.appendChild(typeCell);

            const sourceCell = document.createElement("td");
            addBadge(sourceCell, sourceLabel(grant.source), "source-badge");
            tr.appendChild(sourceCell);

            const subjectCell = document.createElement("td");
            subjectCell.textContent = text(subjectName);
            tr.appendChild(subjectCell);

            const moduleCell = document.createElement("td");
            moduleCell.textContent = grant.access === "admin"
                ? "Все модули"
                : (modules[grant.module] || grant.module || "—");
            tr.appendChild(moduleCell);

            const accessCell = document.createElement("td");
            addBadge(
                accessCell,
                accessLabel(grant.access),
                `access-badge ${grant.access === "admin" ? "write" : grant.access}`,
            );
            tr.appendChild(accessCell);

            const updatedCell = document.createElement("td");
            updatedCell.textContent = text(grant.updated_by);
            tr.appendChild(updatedCell);

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

    function subjectsFor(type, source) {
        const values = type === "group" ? directoryGroups : directoryUsers;
        return values.filter((item) => source === "any" || item.source === source);
    }

    function renderSubjectOptions(type) {
        const control = controls[type];
        const selectedSource = control.source.value;
        const values = subjectsFor(type, selectedSource);
        const previous = control.subject.value;
        control.subject.replaceChildren();

        const placeholder = document.createElement("option");
        placeholder.value = "";
        placeholder.textContent = type === "group" ? "Выберите группу" : "Выберите пользователя";
        placeholder.disabled = true;
        placeholder.selected = true;
        control.subject.appendChild(placeholder);

        for (const item of values) {
            const option = document.createElement("option");
            option.value = type === "group" ? item.name : item.username;
            option.textContent = selectedSource === "any"
                ? `${option.value} · ${sourceLabel(item.source)}`
                : option.value;
            if (option.value === previous) {
                option.selected = true;
                placeholder.selected = false;
            }
            control.subject.appendChild(option);
        }
        control.subject.disabled = values.length === 0;
        control.form.querySelector("button[type='submit']").disabled = values.length === 0;
        if (type === "group") groupSubjectCount.textContent = String(values.length);
        else userSubjectCount.textContent = String(values.length);
    }

    function renderDirectory(directory) {
        const authentication = directory.authentication || {};
        directoryUsers = Array.isArray(directory.users) ? directory.users : [];
        directoryGroups = Array.isArray(directory.groups) ? directory.groups : [];
        pamState.textContent = authentication.pam ? "Активна" : "Нет";
        domainState.textContent = authentication.domain ? "Подключён" : "Нет";
        ssoState.textContent = authentication.sso ? "Активно" : "Нет";
        localUserCount.textContent = directoryUsers.filter((item) => item.source === "local").length;
        domainUserCount.textContent = directoryUsers.filter((item) => item.source === "domain").length;
        groupCount.textContent = directoryGroups.length;
        renderSubjectOptions("group");
        renderSubjectOptions("user");
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
            subjectGrid.hidden = true;
            setMessage("Управление правами доступно полному администратору.", true);
            return;
        }
        if (!grantResponse.ok || !directoryResponse.ok) throw new Error("failed to load access data");

        const grants = await grantResponse.json();
        const directory = await directoryResponse.json();
        modules = (grants.data && grants.data.modules) || {};
        renderModuleOptions();
        renderGrantRows((grants.data && grants.data.grants) || []);
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

    async function submitGrant(type, event) {
        event.preventDefault();
        setMessage("");
        const control = controls[type];
        const subjectName = control.subject.value.trim();
        if (!subjectName) {
            setMessage(type === "group" ? "Выберите группу." : "Выберите пользователя.", true);
            return;
        }
        const response = await fetch("/api/v1/access/grants", {
            method: "POST",
            headers: {"Content-Type": "application/json", "X-CSRF-Token": csrfToken},
            body: JSON.stringify({
                subject_type: type,
                subject_name: subjectName,
                source: control.source.value,
                module: control.access.value === "admin" ? "*" : control.module.value,
                access: control.access.value,
            }),
        });
        if (!response.ok) {
            let detail = "";
            try {
                const payload = await response.json();
                detail = payload.detail || payload.error || "";
            } catch (_) {}
            setMessage(`Не удалось сохранить назначение.${detail ? ` ${detail}` : ""}`, true);
            return;
        }
        await load();
        setMessage(control.access.value === "admin"
            ? "Роль полного администратора сохранена."
            : (type === "group" ? "Права группы сохранены." : "Права пользователя сохранены."));
    }

    for (const type of ["group", "user"]) {
        const control = controls[type];
        control.source.addEventListener("change", () => renderSubjectOptions(type));
        control.access.addEventListener("change", () => syncAccessMode(control));
        control.form.addEventListener("submit", (event) => submitGrant(type, event));
    }

    load().catch(() => setMessage("Не удалось загрузить права пользователей.", true));
})();
