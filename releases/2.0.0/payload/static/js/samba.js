(() => {
    "use strict";

    const byId = (id) => document.getElementById(id);
    const state = {
        csrf: "",
        data: null,
        selectedUser: null,
        selectedGroup: null,
        userSearch: "",
        groupSearch: "",
        busy: false,
    };

    const message = byId("sambaMessage");

    function setMessage(text, error = false) {
        message.textContent = text || "";
        message.classList.toggle("error", error);
        message.setAttribute("role", error ? "alert" : "status");
        message.setAttribute("aria-live", error ? "assertive" : "polite");
    }

    function toast(text, kind = "info") {
        window.ControlCenterUI?.toast?.(text, kind);
    }

    async function confirmAction(text, options = {}) {
        if (window.ControlCenterUI?.confirm) return window.ControlCenterUI.confirm(text, options);
        return window.confirm(text);
    }

    function setBusy(value) {
        state.busy = Boolean(value);
        document.body.setAttribute("aria-busy", state.busy ? "true" : "false");
    }

    function esc(value) {
        return String(value ?? "")
            .replaceAll("&", "&amp;")
            .replaceAll("<", "&lt;")
            .replaceAll(">", "&gt;")
            .replaceAll('"', "&quot;")
            .replaceAll("'", "&#39;");
    }

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

    function badge(text, kind = "") {
        const item = document.createElement("span");
        item.className = `badge ${kind}`.trim();
        item.textContent = text;
        return item;
    }

    function formatBytes(value) {
        const size = Number(value || 0);
        if (!Number.isFinite(size) || size <= 0) return "—";
        const units = ["Б", "КБ", "МБ", "ГБ", "ТБ"];
        let number = size;
        let index = 0;
        while (number >= 1024 && index < units.length - 1) {
            number /= 1024;
            index += 1;
        }
        return `${number.toFixed(index > 1 ? 1 : 0)} ${units[index]}`;
    }

    async function api(url, options = {}) {
        const response = await fetch(url, {cache: "no-store", ...options});
        if (response.status === 401) {
            window.top.location.replace("/login");
            throw new Error("authentication required");
        }
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

    async function postJson(url, body = {}) {
        return api(url, {
            method: "POST",
            headers: {"Content-Type": "application/json", "X-CSRF-Token": state.csrf},
            body: JSON.stringify(body),
        });
    }

    function queueNotice(text) {
        const notice = text || "Операция поставлена в очередь.";
        setMessage(notice);
        toast(notice, "success");
        window.setTimeout(() => load().catch(() => {}), 1800);
    }

    function renderOverview() {
        const data = state.data || {};
        const domain = data.domain || {};
        const levels = domain.functional_levels || {};
        byId("sambaOverview").replaceChildren(
            field("Домен", domain.netbios_domain),
            field("Realm", domain.realm),
            field("Контроллер", domain.dc_name),
            field("Domain SID", domain.sid),
            field("Samba", data.version),
            field("Служба", data.service),
            field("Состояние", data.state),
            field("Domain level", levels.domain),
        );
        const health = byId("sambaHealth");
        health.replaceChildren();
        health.appendChild(badge(data.installed ? "Samba установлена" : "Samba не установлена", data.installed ? "ok" : "error"));
        health.appendChild(badge(data.state === "active" ? "AD DC работает" : `AD DC: ${data.state || "unknown"}`, data.state === "active" ? "ok" : "warn"));
        const replication = data.replication || {};
        if (replication.available) health.appendChild(badge(replication.healthy ? "Репликация без ошибок" : "Есть ошибки репликации", replication.healthy ? "ok" : "error"));
        health.appendChild(badge(`Пользователей: ${(data.users || []).length}`));
        health.appendChild(badge(`Групп: ${(data.groups || []).length}`));
    }

    function setInput(id, value) {
        const node = byId(id);
        if (node) node.value = value == null ? "" : String(value);
    }

    function renderPolicy() {
        const policy = (state.data && state.data.password_policy) || {};
        setInput("policyComplexity", String(Boolean(policy.complexity)));
        setInput("policyHistory", policy.history_length);
        setInput("policyMinLength", policy.min_length);
        setInput("policyMinAge", policy.min_age_days);
        setInput("policyMaxAge", policy.max_age_days);
        setInput("policyLockThreshold", policy.lockout_threshold);
        setInput("policyLockDuration", policy.lockout_duration_minutes);
        setInput("policyLockReset", policy.lockout_reset_minutes);
        const canWrite = Boolean(state.data && state.data.can_write);
        for (const node of byId("passwordPolicyForm").querySelectorAll("input,select,button")) node.disabled = !canWrite || state.busy;
    }

    function userMatches(user, query) {
        if (!query) return true;
        const haystack = [user.username, user.display_name, user.given_name, user.surname, user.email, user.phone].join(" ").toLocaleLowerCase("ru");
        return haystack.includes(query.toLocaleLowerCase("ru"));
    }

    function renderUsers() {
        const list = byId("userList");
        list.replaceChildren();
        const users = (state.data && state.data.users) || [];
        const filtered = users.filter((user) => userMatches(user, state.userSearch));
        for (const user of filtered) {
            const row = document.createElement("button");
            row.type = "button";
            row.disabled = state.busy;
            row.className = `object-row ${state.selectedUser === user.username ? "active" : ""}`.trim();
            const title = document.createElement("strong");
            title.textContent = user.display_name || user.username;
            const meta = document.createElement("span");
            const flags = [user.username];
            if (!user.enabled) flags.push("отключён");
            if (user.locked) flags.push("заблокирован");
            meta.textContent = flags.join(" · ");
            row.append(title, meta);
            row.addEventListener("click", () => {
                state.selectedUser = user.username;
                renderUsers();
                renderUserEditor(user);
            });
            list.appendChild(row);
        }
        if (!filtered.length) {
            const empty = document.createElement("div");
            empty.className = "empty-state";
            empty.textContent = "Пользователи не найдены.";
            list.appendChild(empty);
        }
        if (state.selectedUser) {
            const selected = users.find((user) => user.username === state.selectedUser);
            if (selected) renderUserEditor(selected);
        }
    }

    function groupOptions(selectedNames = []) {
        const selected = new Set(selectedNames || []);
        return ((state.data && state.data.groups) || []).map((group) => `<option value="${esc(group.name)}" ${selected.has(group.name) ? "selected" : ""}>${esc(group.name)}</option>`).join("");
    }

    function renderUserEditor(user = null, creating = false) {
        const editor = byId("userEditor");
        const canWrite = Boolean(state.data && state.data.can_write);
        const value = user || {};
        editor.innerHTML = `
            <form id="userForm"><div class="field-grid three"><label><span>Логин</span><input id="uLogin" required maxlength="64" value="${esc(value.username || "")}" ${creating ? "" : "readonly"}></label><label><span>Имя</span><input id="uGiven" maxlength="256" value="${esc(value.given_name || "")}"></label><label><span>Фамилия</span><input id="uSurname" maxlength="256" value="${esc(value.surname || "")}"></label><label><span>ФИО / отображаемое имя</span><input id="uDisplay" maxlength="256" value="${esc(value.display_name || "")}"></label><label><span>E-mail</span><input id="uEmail" type="email" maxlength="256" value="${esc(value.email || "")}"></label><label><span>Телефон</span><input id="uPhone" maxlength="128" value="${esc(value.phone || "")}"></label><label><span>Подключаемый диск</span><input id="uHomeDrive" maxlength="16" placeholder="H:" value="${esc(value.home_drive || "")}"></label><label><span>Сетевая домашняя папка</span><input id="uHomeDirectory" maxlength="2048" placeholder="\\\\SRV\\Users\\login" value="${esc(value.home_directory || "")}"></label><label><span>Перемещаемый профиль</span><input id="uProfilePath" maxlength="2048" placeholder="\\\\SRV\\Profiles\\login" value="${esc(value.profile_path || "")}"></label><label><span>Доменный скрипт</span><input id="uScriptPath" maxlength="2048" placeholder="logon.cmd" value="${esc(value.script_path || "")}"></label><label><span>Primary group</span><select id="uPrimaryGroup"><option value="">Не менять</option>${groupOptions([])}</select></label>${creating ? '<label><span>Начальный пароль</span><input id="uPassword" type="password" autocomplete="new-password" required maxlength="4096"></label>' : ""}</div><label class="stack-field"><span>Описание</span><textarea id="uDescription" maxlength="2048">${esc(value.description || "")}</textarea></label><label class="stack-field"><span>Группы домена</span><select id="uGroups" class="multi-select" multiple>${groupOptions(value.groups || [])}</select></label>${creating ? '<div class="checkbox-row"><label><input id="uMustChange" type="checkbox"> Сменить пароль при первом входе</label></div>' : ""}<div class="config-actions"><button class="action-button" type="submit">${creating ? "Создать пользователя" : "Сохранить"}</button>${!creating && !value.protected ? '<button class="secondary-button" id="uToggle" type="button"></button><button class="secondary-button" id="uUnlock" type="button">Разблокировать</button><button class="danger-button" id="uDelete" type="button">Удалить</button>' : ""}</div></form>
            ${!creating ? `<div class="panel-title">Смена пароля</div><form id="userPasswordForm"><div class="field-grid"><label><span>Новый пароль</span><input id="uNewPassword" type="password" autocomplete="new-password" maxlength="4096" required></label></div><div class="checkbox-row"><label><input id="uPasswordMustChange" type="checkbox"> Потребовать смену при следующем входе</label></div><div class="config-actions"><button class="secondary-button" type="submit">Сменить пароль</button></div></form>` : ""}`;
        const primary = byId("uPrimaryGroup");
        if (value.groups && value.groups.length && primary) primary.value = value.groups.includes("Domain Users") ? "Domain Users" : "";
        for (const control of editor.querySelectorAll("input,select,textarea,button")) control.disabled = !canWrite || state.busy;
        const form = byId("userForm");
        form.addEventListener("submit", async (event) => {
            event.preventDefault();
            if (state.busy) return;
            const groups = Array.from(byId("uGroups").selectedOptions).map((option) => option.value);
            const payload = {username: byId("uLogin").value.trim(), given_name: byId("uGiven").value.trim(), surname: byId("uSurname").value.trim(), display_name: byId("uDisplay").value.trim(), email: byId("uEmail").value.trim(), phone: byId("uPhone").value.trim(), home_drive: byId("uHomeDrive").value.trim(), home_directory: byId("uHomeDirectory").value.trim(), profile_path: byId("uProfilePath").value.trim(), script_path: byId("uScriptPath").value.trim(), description: byId("uDescription").value.trim(), groups};
            const primaryGroup = byId("uPrimaryGroup").value;
            if (primaryGroup) payload.primary_group = primaryGroup;
            setBusy(true);
            try {
                if (creating) { payload.password = byId("uPassword").value; payload.must_change_password = byId("uMustChange").checked; await postJson("/api/v1/samba/users", payload); queueNotice("Создание пользователя поставлено в очередь."); }
                else { await postJson(`/api/v1/samba/users/${encodeURIComponent(value.username)}/update`, payload); queueNotice("Изменение пользователя поставлено в очередь."); }
            } catch (error) { setMessage(error.message, true); toast(error.message, "error"); }
            finally { setBusy(false); }
        });
        if (!creating && !value.protected) {
            const toggle = byId("uToggle");
            toggle.textContent = value.enabled ? "Отключить" : "Включить";
            toggle.addEventListener("click", () => runUserOperation(value.username, value.enabled ? "disable" : "enable"));
            byId("uUnlock").disabled = !canWrite || !value.locked;
            byId("uUnlock").addEventListener("click", () => runUserOperation(value.username, "unlock"));
            byId("uDelete").addEventListener("click", async () => {
                const approved = await confirmAction(`Удалить доменного пользователя «${value.username}»? Учётная запись будет удалена из Active Directory.`, {title: "Удаление доменного пользователя", confirmLabel: "Удалить пользователя", danger: true, requireText: value.username});
                if (!approved) return;
                await runUserOperation(value.username, "delete");
            });
        }
        if (!creating) {
            byId("userPasswordForm").addEventListener("submit", async (event) => {
                event.preventDefault();
                if (state.busy) return;
                setBusy(true);
                try {
                    await postJson(`/api/v1/samba/users/${encodeURIComponent(value.username)}/password`, {password: byId("uNewPassword").value, must_change_password: byId("uPasswordMustChange").checked});
                    byId("uNewPassword").value = "";
                    queueNotice("Смена пароля поставлена в очередь.");
                } catch (error) { setMessage(error.message, true); toast(error.message, "error"); }
                finally { setBusy(false); }
            });
        }
    }

    async function runUserOperation(username, operation) {
        if (state.busy) return;
        setBusy(true);
        try { await postJson(`/api/v1/samba/users/${encodeURIComponent(username)}/${operation}`); queueNotice(`Операция ${operation} поставлена в очередь.`); }
        catch (error) { setMessage(error.message, true); toast(error.message, "error"); }
        finally { setBusy(false); }
    }

    function renderGroups() {
        const list = byId("groupList");
        list.replaceChildren();
        const query = state.groupSearch.toLocaleLowerCase("ru");
        const groups = ((state.data && state.data.groups) || []).filter((group) => !query || group.name.toLocaleLowerCase("ru").includes(query));
        for (const group of groups) {
            const row = document.createElement("button");
            row.type = "button";
            row.disabled = state.busy;
            row.className = `object-row ${state.selectedGroup === group.name ? "active" : ""}`.trim();
            const title = document.createElement("strong"); title.textContent = group.name;
            const meta = document.createElement("span"); meta.textContent = `${(group.members || []).length} участников${group.protected ? " · системная" : ""}`;
            row.append(title, meta);
            row.addEventListener("click", () => { state.selectedGroup = group.name; renderGroups(); renderGroupEditor(group); });
            list.appendChild(row);
        }
        if (!groups.length) { const empty = document.createElement("div"); empty.className = "empty-state"; empty.textContent = "Группы не найдены."; list.appendChild(empty); }
        if (state.selectedGroup) { const selected = ((state.data && state.data.groups) || []).find((group) => group.name === state.selectedGroup); if (selected) renderGroupEditor(selected); }
    }

    function userOptions(selectedNames = []) {
        const selected = new Set(selectedNames || []);
        return ((state.data && state.data.users) || []).map((user) => `<option value="${esc(user.username)}" ${selected.has(user.username) ? "selected" : ""}>${esc(user.display_name || user.username)} (${esc(user.username)})</option>`).join("");
    }

    function renderGroupEditor(group = null, creating = false) {
        const editor = byId("groupEditor");
        const canWrite = Boolean(state.data && state.data.can_write);
        const value = group || {};
        editor.innerHTML = `<form id="groupForm"><div class="field-grid"><label><span>Имя группы</span><input id="gName" maxlength="128" required value="${esc(value.name || "")}" ${creating ? "" : "readonly"}></label><label><span>Описание</span><input id="gDescription" maxlength="1024"></label></div><label class="stack-field"><span>Пользователи в группе</span><select id="gMembers" class="multi-select" multiple>${userOptions(value.members || [])}</select></label><div class="config-actions"><button class="action-button" type="submit">${creating ? "Создать группу" : "Сохранить состав"}</button>${!creating && !value.protected ? '<button class="danger-button" id="gDelete" type="button">Удалить группу</button>' : ""}</div></form>`;
        for (const control of editor.querySelectorAll("input,select,button")) control.disabled = !canWrite || state.busy;
        byId("groupForm").addEventListener("submit", async (event) => {
            event.preventDefault();
            if (state.busy) return;
            const members = Array.from(byId("gMembers").selectedOptions).map((option) => option.value);
            setBusy(true);
            try {
                if (creating) { await postJson("/api/v1/samba/groups", {name: byId("gName").value.trim(), description: byId("gDescription").value.trim(), members}); queueNotice("Создание группы поставлено в очередь."); return; }
                const old = new Set(value.members || []); const next = new Set(members); const add = members.filter((name) => !old.has(name)); const remove = Array.from(old).filter((name) => !next.has(name)); const description = byId("gDescription").value.trim();
                if (description) await postJson(`/api/v1/samba/groups/${encodeURIComponent(value.name)}/update`, {description});
                if (add.length) await postJson(`/api/v1/samba/groups/${encodeURIComponent(value.name)}/members`, {operation: "add", members: add});
                if (remove.length) await postJson(`/api/v1/samba/groups/${encodeURIComponent(value.name)}/members`, {operation: "remove", members: remove});
                queueNotice("Изменение группы поставлено в очередь.");
            } catch (error) { setMessage(error.message, true); toast(error.message, "error"); }
            finally { setBusy(false); }
        });
        if (!creating && !value.protected) {
            byId("gDelete").addEventListener("click", async () => {
                const approved = await confirmAction(`Удалить доменную группу «${value.name}»? Это изменит членство и права, зависящие от этой группы.`, {title: "Удаление доменной группы", confirmLabel: "Удалить группу", danger: true, requireText: value.name});
                if (!approved) return;
                setBusy(true);
                try { await postJson(`/api/v1/samba/groups/${encodeURIComponent(value.name)}/delete`); state.selectedGroup = null; queueNotice("Удаление группы поставлено в очередь."); }
                catch (error) { setMessage(error.message, true); toast(error.message, "error"); }
                finally { setBusy(false); }
            });
        }
    }

    function renderBackups() {
        const body = byId("domainBackupRows");
        body.replaceChildren();
        const backups = (state.data && state.data.backups) || [];
        for (const item of backups) {
            const row = document.createElement("tr");
            const sid = item.domain && item.domain.sid ? item.domain.sid : "—";
            row.innerHTML = `<td>${esc(item.created_at || "—")}</td><td>${esc(item.mode || "—")}</td><td>${esc(formatBytes(item.size))}</td><td>${esc(sid)}</td><td></td>`;
            const link = document.createElement("a"); link.className = "secondary-button"; link.href = item.download_url; link.textContent = "Скачать"; row.lastElementChild.appendChild(link); body.appendChild(row);
        }
        if (!backups.length) { const row = document.createElement("tr"); row.innerHTML = '<td colspan="5" class="muted">Миграционных резервных копий пока нет.</td>'; body.appendChild(row); }
        byId("domainBackupCreate").disabled = !(state.data && state.data.can_write) || state.busy;
        byId("domainRestoreOpen").disabled = !(state.data && state.data.full_admin) || state.busy;
        window.ControlCenterUI?.enhanceTables?.(document);
    }

    async function load() {
        if (state.busy) return;
        const auth = await api("/api/v1/auth/status");
        state.csrf = (auth.data && auth.data.csrf_token) || "";
        const payload = await api("/api/v1/samba");
        state.data = payload.data || {};
        renderOverview(); renderPolicy(); renderBackups(); renderUsers(); renderGroups();
    }

    byId("passwordPolicyForm").addEventListener("submit", async (event) => {
        event.preventDefault(); if (state.busy) return; setBusy(true);
        try {
            await postJson("/api/v1/samba/password-policy", {complexity: byId("policyComplexity").value === "true", history_length: Number(byId("policyHistory").value), min_length: Number(byId("policyMinLength").value), min_age_days: Number(byId("policyMinAge").value), max_age_days: Number(byId("policyMaxAge").value), lockout_threshold: Number(byId("policyLockThreshold").value), lockout_duration_minutes: Number(byId("policyLockDuration").value), lockout_reset_minutes: Number(byId("policyLockReset").value)});
            queueNotice("Парольная политика поставлена в очередь на применение.");
        } catch (error) { setMessage(error.message, true); toast(error.message, "error"); }
        finally { setBusy(false); }
    });

    byId("userSearch").addEventListener("input", (event) => { state.userSearch = event.target.value || ""; renderUsers(); });
    byId("groupSearch").addEventListener("input", (event) => { state.groupSearch = event.target.value || ""; renderGroups(); });
    byId("userNew").addEventListener("click", () => { if (state.busy) return; state.selectedUser = null; renderUsers(); renderUserEditor(null, true); });
    byId("groupNew").addEventListener("click", () => { if (state.busy) return; state.selectedGroup = null; renderGroups(); renderGroupEditor(null, true); });

    byId("domainBackupCreate").addEventListener("click", async () => {
        if (state.busy) return; setBusy(true); byId("domainBackupCreate").setAttribute("aria-busy", "true");
        try { await postJson("/api/v1/samba/backups", {mode: byId("domainBackupMode").value}); queueNotice("Создание резервной копии домена поставлено в очередь."); }
        catch (error) { setMessage(error.message, true); toast(error.message, "error"); }
        finally { setBusy(false); byId("domainBackupCreate").removeAttribute("aria-busy"); }
    });

    byId("domainRestoreOpen").addEventListener("click", () => { if (!state.busy) byId("domainRestoreBox").classList.toggle("hidden"); });

    byId("domainRestoreStart").addEventListener("click", async () => {
        if (state.busy) return;
        const file = byId("domainRestoreFile").files[0];
        if (!file) { setMessage("Выберите файл резервной копии домена.", true); return; }
        const approved = await confirmAction(
            "Запустить восстановление домена из выбранной копии? Операция предназначена только для нового, ещё не provisioned контроллера домена и может заменить его конфигурацию.",
            {title: "Восстановление Active Directory", confirmLabel: "Восстановить домен", danger: true, requireText: "RESTORE"}
        );
        if (!approved) return;
        const form = new FormData(); form.append("backup", file, file.name);
        setBusy(true); byId("domainRestoreStart").setAttribute("aria-busy", "true");
        try {
            await api("/api/v1/samba/backups/import", {method: "POST", headers: {"X-CSRF-Token": state.csrf}, body: form});
            queueNotice("Резервная копия загружена. Восстановление поставлено в очередь.");
        } catch (error) { setMessage(error.message, true); toast(error.message, "error"); }
        finally { setBusy(false); byId("domainRestoreStart").removeAttribute("aria-busy"); }
    });

    setMessage("");
    load().catch((error) => setMessage(error.message || "Не удалось загрузить состояние Samba.", true));
    window.setInterval(() => { if (!state.busy && document.visibilityState === "visible") load().catch(() => {}); }, 30000);
})();
