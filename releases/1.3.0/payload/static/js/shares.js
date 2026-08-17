(() => {
    "use strict";

    const byId = (id) => document.getElementById(id);
    const state = {
        csrf: "",
        data: null,
        directory: {users: [], groups: [], domain: null},
        selected: null,
        search: "",
    };

    function esc(value) {
        return String(value ?? "")
            .replaceAll("&", "&amp;")
            .replaceAll("<", "&lt;")
            .replaceAll(">", "&gt;")
            .replaceAll('"', "&quot;")
            .replaceAll("'", "&#39;");
    }

    function setMessage(text, error = false) {
        const box = byId("shareMessage");
        box.textContent = text || "";
        box.classList.toggle("error", error);
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
        setMessage(text || "Операция поставлена в очередь.");
        window.setTimeout(() => load().catch(() => {}), 1700);
    }

    function matches(share) {
        if (!state.search) return true;
        const text = [share.name, share.comment, share.path].join(" ").toLocaleLowerCase("ru");
        return text.includes(state.search.toLocaleLowerCase("ru"));
    }

    function renderList() {
        const list = byId("shareList");
        list.replaceChildren();
        const shares = ((state.data && state.data.shares) || []).filter(matches);
        for (const share of shares) {
            const row = document.createElement("button");
            row.type = "button";
            row.className = `object-row ${state.selected === share.name ? "active" : ""}`.trim();
            const title = document.createElement("strong");
            title.textContent = share.name;
            const meta = document.createElement("span");
            const flags = [share.browseable ? "открытая" : "скрытая"];
            flags.push(share.managed ? "управляемая" : share.system ? "системная" : "внешняя");
            if (share.quota && share.quota.limit_gib) flags.push(`квота ${share.quota.limit_gib} ГиБ`);
            meta.textContent = `${share.comment || share.path || ""} · ${flags.join(" · ")}`;
            row.append(title, meta);
            row.addEventListener("click", () => {
                state.selected = share.name;
                renderList();
                renderEditor(share, false);
            });
            list.appendChild(row);
        }
        if (!shares.length) {
            const empty = document.createElement("div");
            empty.className = "empty-state";
            empty.textContent = "Сетевые шары не найдены.";
            list.appendChild(empty);
        }
        if (state.selected) {
            const selected = ((state.data && state.data.shares) || []).find((share) => share.name === state.selected);
            if (selected) renderEditor(selected, false);
        }
    }

    function nameOptions(kind, selected) {
        if (kind === "everyone") return '<option value="Everyone" selected>Everyone</option>';
        const source = kind === "group" ? state.directory.groups : state.directory.users;
        return source.map((item) => {
            const name = item.name;
            const label = kind === "user" ? (item.display_name && item.display_name !== name ? `${item.display_name} (${name})` : name) : name;
            return `<option value="${esc(name)}" ${name === selected ? "selected" : ""}>${esc(label)}</option>`;
        }).join("");
    }

    function subjectRow(subject = {type: "group", name: "", access: "read"}) {
        const row = document.createElement("div");
        row.className = "subject-row";
        row.innerHTML = `
            <select class="subject-type">
                <option value="group" ${subject.type === "group" ? "selected" : ""}>Группа</option>
                <option value="user" ${subject.type === "user" ? "selected" : ""}>Пользователь</option>
                <option value="everyone" ${subject.type === "everyone" ? "selected" : ""}>Всем</option>
            </select>
            <select class="subject-name"></select>
            <select class="subject-access">
                <option value="read" ${subject.access === "read" ? "selected" : ""}>Чтение</option>
                <option value="write" ${subject.access === "write" ? "selected" : ""}>Запись</option>
            </select>
            <button class="danger-button subject-remove" type="button">Убрать</button>
        `;
        const type = row.querySelector(".subject-type");
        const name = row.querySelector(".subject-name");
        function refill() {
            name.innerHTML = nameOptions(type.value, subject.name);
            if (type.value === "everyone") name.value = "Everyone";
        }
        type.addEventListener("change", () => {
            subject.name = "";
            refill();
        });
        row.querySelector(".subject-remove").addEventListener("click", () => row.remove());
        refill();
        return row;
    }

    function quotaLabel(filesystem) {
        if (!filesystem) return "Квота будет проверена после создания каталога.";
        if (filesystem.quota_supported) return `Поддерживается: ${filesystem.quota_backend || "filesystem quota"}`;
        return filesystem.quota_reason || "Квоты не поддерживаются на этом томе.";
    }

    function parsePrincipal(raw, access = "read") {
        let token = String(raw || "").trim();
        if (!token) return null;
        let type = "user";
        if (token.startsWith("@")) {
            type = "group";
            token = token.slice(1).trim();
        }
        token = token.replace(/^['"]+|['"]+$/g, "");
        const slash = Math.max(token.lastIndexOf("\\"), token.lastIndexOf("/"));
        if (slash >= 0) token = token.slice(slash + 1);
        token = token.replace(/^['"]+|['"]+$/g, "").trim();
        if (!token) return null;
        if (token.toLocaleLowerCase("en") === "everyone") {
            return {type: "everyone", name: "Everyone", access};
        }
        return {type, name: token, access};
    }

    function subjectKey(subject) {
        return `${subject.type}:${String(subject.name || "").toLocaleLowerCase("en")}`;
    }

    function subjectsFromExternalShare(share) {
        const valid = Array.isArray(share.valid_users) ? share.valid_users : [];
        const read = Array.isArray(share.read_list) ? share.read_list : [];
        const write = Array.isArray(share.write_list) ? share.write_list : [];
        const access = new Map();
        for (const item of read) {
            const subject = parsePrincipal(item, "read");
            if (subject) access.set(subjectKey(subject), subject);
        }
        for (const item of write) {
            const subject = parsePrincipal(item, "write");
            if (subject) access.set(subjectKey(subject), subject);
        }
        const ordered = [];
        const source = valid.length ? valid : [...read, ...write];
        for (const item of source) {
            const base = parsePrincipal(item, share.read_only === false ? "write" : "read");
            if (!base) continue;
            const resolved = access.get(subjectKey(base)) || base;
            if (!ordered.some((subject) => subjectKey(subject) === subjectKey(resolved))) ordered.push(resolved);
        }
        for (const resolved of access.values()) {
            if (!ordered.some((subject) => subjectKey(subject) === subjectKey(resolved))) ordered.push(resolved);
        }
        if (!ordered.length) {
            ordered.push({type: "everyone", name: "Everyone", access: share.read_only === false ? "write" : "read"});
        }
        return ordered;
    }

    function renderReadOnlyShare(share) {
        const editor = byId("shareEditor");
        editor.innerHTML = `
            <div class="status-grid">
                <div class="status-item"><span>Имя</span><strong>${esc(share.name)}</strong></div>
                <div class="status-item"><span>Путь</span><strong>${esc(share.path || "—")}</strong></div>
                <div class="status-item"><span>Видимость</span><strong>${share.browseable ? "Открытая" : "Скрытая"}</strong></div>
                <div class="status-item"><span>Тип</span><strong>Системная</strong></div>
            </div>
            <div class="danger-note">Системные Samba/AD-шары защищены от редактирования в общем редакторе. Это предотвращает повреждение SYSVOL, NETLOGON и служебной конфигурации домена.</div>
        `;
    }

    function renderEditor(share = null, creating = false) {
        if (!creating && share && share.system) {
            renderReadOnlyShare(share);
            return;
        }
        const editor = byId("shareEditor");
        const external = Boolean(!creating && share && !share.managed);
        const value = share || {name: "", comment: "", path: "", browseable: true, subjects: [{type: "everyone", name: "Everyone", access: "read"}], quota: {}};
        if (external) value.subjects = subjectsFromExternalShare(value);
        const canWrite = Boolean(state.data && state.data.can_write);
        const fullAdmin = Boolean(state.data && state.data.full_admin);
        const limit = value.quota && value.quota.limit_gib ? value.quota.limit_gib : "";
        const externalNote = external
            ? '<div class="badge-row"><span class="badge warn">Внешняя шара: параметры будут изменены в существующем smb.conf/include. Каталог и данные не перемещаются. Квота и файловые ACL автоматически не меняются.</span></div>'
            : "";
        editor.innerHTML = `
            <form id="shareForm">
                <div class="field-grid">
                    <label><span>Имя шары (ASCII)</span><input id="sName" pattern="[A-Za-z0-9][A-Za-z0-9_-]{0,62}" maxlength="63" required value="${esc(value.name || "")}"></label>
                    <label><span>Комментарий</span><input id="sComment" maxlength="1024" value="${esc(value.comment || "")}"></label>
                    <label><span>Путь</span><input id="sPath" maxlength="1024" placeholder="/srv/shares/ShareName" value="${esc(value.path || "")}"></label>
                    <label><span>Квота, ГиБ</span><input id="sQuota" type="number" min="0" max="1048576" step="1" placeholder="0 = без ограничения" value="${esc(limit)}"></label>
                </div>
                <div class="checkbox-row"><label><input id="sBrowseable" type="checkbox" ${value.browseable !== false ? "checked" : ""}> Открытая / видна при просмотре сети</label></div>
                ${externalNote}
                ${external ? "" : `<div class="badge-row"><span class="badge ${value.filesystem && value.filesystem.quota_supported ? "ok" : "warn"}">${esc(quotaLabel(value.filesystem))}</span></div>`}
                <div class="panel-title">Права доступа</div>
                <div class="subject-list" id="subjectList"></div>
                <div class="config-actions"><button class="secondary-button" id="subjectAdd" type="button">Добавить пользователя / группу</button></div>
                <div class="config-actions">
                    <button class="action-button" type="submit">${creating ? "Создать шару" : "Сохранить"}</button>
                    ${!creating && !external ? '<button class="danger-button" id="shareDelete" type="button">Удалить публикацию</button>' : ""}
                </div>
                ${!creating && !external && fullAdmin ? '<div class="checkbox-row"><label><input id="deleteShareData" type="checkbox"> При удалении также удалить каталог и все данные</label></div>' : ""}
            </form>
        `;
        const subjectList = byId("subjectList");
        const subjects = Array.isArray(value.subjects) && value.subjects.length ? value.subjects : [{type: "everyone", name: "Everyone", access: "read"}];
        for (const subject of subjects) subjectList.appendChild(subjectRow(subject));
        byId("subjectAdd").addEventListener("click", () => subjectList.appendChild(subjectRow()));
        for (const control of editor.querySelectorAll("input,select,button")) control.disabled = !canWrite;
        if (external) {
            byId("sName").disabled = true;
            byId("sQuota").disabled = true;
        }

        byId("shareForm").addEventListener("submit", async (event) => {
            event.preventDefault();
            const subjectsPayload = Array.from(subjectList.querySelectorAll(".subject-row")).map((row) => ({
                type: row.querySelector(".subject-type").value,
                name: row.querySelector(".subject-name").value,
                access: row.querySelector(".subject-access").value,
            }));
            if (!subjectsPayload.length) {
                setMessage("Добавьте хотя бы одного пользователя, группу или Everyone.", true);
                return;
            }
            const quotaRaw = external ? "" : byId("sQuota").value.trim();
            const payload = {
                name: value.name || byId("sName").value.trim(),
                comment: byId("sComment").value.trim(),
                path: byId("sPath").value.trim() || null,
                browseable: byId("sBrowseable").checked,
                subjects: subjectsPayload,
                quota: {limit_gib: quotaRaw === "" || Number(quotaRaw) === 0 ? null : Number(quotaRaw)},
                external_share: external,
            };
            try {
                if (creating) {
                    await postJson("/api/v1/shares", payload);
                    queueNotice("Создание сетевой шары поставлено в очередь.");
                } else {
                    await postJson(`/api/v1/shares/${encodeURIComponent(value.name)}/update`, payload);
                    queueNotice(external ? "Изменение внешней SMB-шары поставлено в очередь." : "Изменение сетевой шары поставлено в очередь.");
                }
            } catch (error) {
                setMessage(error.message, true);
            }
        });

        if (!creating && !external) {
            byId("shareDelete").addEventListener("click", async () => {
                const deleteData = Boolean(byId("deleteShareData") && byId("deleteShareData").checked);
                const text = deleteData
                    ? `Удалить шару ${value.name} И ВСЕ ДАННЫЕ каталога ${value.path}?`
                    : `Удалить SMB-публикацию ${value.name}, сохранив каталог и данные?`;
                if (!window.confirm(text)) return;
                try {
                    await postJson(`/api/v1/shares/${encodeURIComponent(value.name)}/delete`, {delete_data: deleteData});
                    state.selected = null;
                    queueNotice(deleteData ? "Удаление публикации и данных поставлено в очередь." : "Удаление публикации поставлено в очередь. Данные будут сохранены.");
                } catch (error) {
                    setMessage(error.message, true);
                }
            });
        }
    }

    async function load() {
        const auth = await api("/api/v1/auth/status");
        state.csrf = (auth.data && auth.data.csrf_token) || "";
        const [shares, directory] = await Promise.all([
            api("/api/v1/shares"),
            api("/api/v1/shares/directory"),
        ]);
        state.data = shares.data || {};
        state.directory = directory.data || {users: [], groups: [], domain: null};
        byId("shareNew").disabled = !state.data.can_write;
        renderList();
    }

    byId("shareSearch").addEventListener("input", (event) => {
        state.search = event.target.value || "";
        renderList();
    });
    byId("shareNew").addEventListener("click", () => {
        state.selected = null;
        renderList();
        renderEditor(null, true);
    });

    load().catch((error) => setMessage(error.message || "Не удалось загрузить сетевые шары.", true));
    window.setInterval(() => load().catch(() => {}), 30000);
})();
