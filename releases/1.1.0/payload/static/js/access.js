(() => {
    "use strict";

    const identityBadge = document.getElementById("identityBadge");
    const rows = document.getElementById("grantRows");
    const message = document.getElementById("grantMessage");
    const pamState = document.getElementById("pamState");
    const domainState = document.getElementById("domainState");
    const ssoState = document.getElementById("ssoState");
    const localUserCount = document.getElementById("localUserCount");
    const domainUserCount = document.getElementById("domainUserCount");
    const groupCount = document.getElementById("groupCount");
    const groupSubjectCount = document.getElementById("groupSubjectCount");
    const userSubjectCount = document.getElementById("userSubjectCount");
    const subjectGrid = document.querySelector(".subject-grid");

    const controls = {
        group: {
            form: document.getElementById("groupGrantForm"),
            source: document.getElementById("groupGrantSource"),
            subject: document.getElementById("groupGrantSubject"),
            module: document.getElementById("groupGrantModule"),
            access: document.getElementById("groupGrantAccess"),
        },
        user: {
            form: document.getElementById("userGrantForm"),
            source: document.getElementById("userGrantSource"),
            subject: document.getElementById("userGrantSubject"),
            module: document.getElementById("userGrantModule"),
            access: document.getElementById("userGrantAccess"),
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

    function addBadge(cell, label, className) {
        const badge = document.createElement("span");
        badge.className = className;
        badge.textContent = label;
        cell.appendChild(badge);
    }

    function renderModuleOptions() {
        for (const control of Object.values(controls)) {
            control.module.textContent = "";
            for (const [key, label] of Object.entries(modules)) {
                const option = document.createElement("option");
                option.value = key;
                option.textContent = label;
                control.module.appendChild(option);
            }
        }
    }

    function renderGrantRows(grants) {
        rows.textContent = "";
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
            addBadge(
                typeCell,
                subjectTypeLabel(subjectType),
                `subject-type-badge ${subjectType === "user" ? "user" : "group"}`,
            );
            tr.appendChild(typeCell);

            const sourceCell = document.createElement("td");
            addBadge(sourceCell, sourceLabel(grant.source), "source-badge");
            tr.appendChild(sourceCell);

            for (const value of [
                subjectName,
                modules[grant.module] || grant.module,
            ]) {
                const td = document.createElement("td");
                td.textContent = text(value);
                tr.appendChild(td);
            }

            const accessCell = document.createElement("td");
            addBadge(
                accessCell,
                grant.access === "write" ? "Запись" : "Чтение",
                `access-badge ${grant.access === "write" ? "write" : "read"}`,
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

    function subjectsFor(type, selectedSource) {
        const values = type === "group" ? directoryGroups : directoryUsers;
        return values.filter((item) => selectedSource === "any" || item.source === selectedSource);
    }

    function renderSubjectOptions(type) {
        const control = controls[type];
        const selectedSource = control.source.value;
        const values = subjectsFor(type, selectedSource);
        const previous = control.subject.value;
        control.subject.textContent = "";

        const placeholder = document.createElement("option");
        placeholder.value = "";
        placeholder.textContent = type === "group" ? "Выберите группу" : "Выберите пользователя";
        placeholder.disabled = true;
        placeholder.selected = true;
        control.subject.appendChild(placeholder);

        for (const item of values) {
            const option = document.createElement("option");
            option.value = type === "group" ? item.name : item.username;
            const name = option.value;
            option.textContent = selectedSource === "any"
                ? `${name} · ${sourceLabel(item.source)}`
                : name;
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
            setMessage("Управление правами доступно администратору сервера.", true);
            return;
        }
        if (!grantResponse.ok || !directoryResponse.ok) {
            throw new Error("failed to load access data");
        }

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
            headers: {
                "Content-Type": "application/json",
                "X-CSRF-Token": csrfToken,
            },
            body: JSON.stringify({
                subject_type: type,
                subject_name: subjectName,
                source: control.source.value,
                module: control.module.value,
                access: control.access.value,
            }),
        });

        if (!response.ok) {
            let detail = "";
            try {
                const payload = await response.json();
                detail = payload.detail || payload.error || "";
            } catch (_) {
                detail = "";
            }
            setMessage(`Не удалось сохранить назначение прав.${detail ? ` ${detail}` : ""}`, true);
            return;
        }

        await load();
        setMessage(type === "group" ? "Права группы сохранены." : "Права пользователя сохранены.");
    }

    for (const type of ["group", "user"]) {
        controls[type].source.addEventListener("change", () => renderSubjectOptions(type));
        controls[type].form.addEventListener("submit", (event) => submitGrant(type, event));
    }

    load().catch(() => setMessage("Не удалось загрузить права пользователей.", true));
})();
