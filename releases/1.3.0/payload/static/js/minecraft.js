(() => {
    "use strict";

    const byId = (id) => document.getElementById(id);
    const listBox = byId("minecraftInstanceList");
    const editor = byId("minecraftEditor");
    const message = byId("minecraftMessage");
    const search = byId("minecraftSearch");
    const newButton = byId("minecraftNew");

    const state = {
        csrf: "",
        data: {instances: [], available_ports: {ipv4_start: 19132, ipv6_start: 19133}},
        canWrite: false,
        fullAdmin: false,
        selectedId: null,
        creating: false,
        dirty: false,
        busy: false,
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
        message.textContent = text || "";
        message.classList.toggle("error", error);
    }

    function labelState(value) {
        const stateValue = String(value || "unknown");
        const labels = {
            active: "Работает",
            inactive: "Остановлен",
            failed: "Ошибка",
            activating: "Запускается",
            deactivating: "Останавливается",
            "not-installed": "Не установлен",
        };
        return labels[stateValue] || stateValue;
    }

    function badge(text, kind = "") {
        return `<span class="mc-badge ${esc(kind)}">${esc(text)}</span>`;
    }

    function boolValue(value) {
        return value === true || String(value).toLowerCase() === "true";
    }

    async function api(url, options = {}) {
        const response = await fetch(url, {cache: "no-store", ...options});
        if (response.status === 401) {
            window.top.location.replace("/login");
            throw new Error("Требуется вход в систему");
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

    function instanceById(id) {
        return (state.data.instances || []).find((item) => String(item.id) === String(id)) || null;
    }

    function selectedInstance() {
        return state.creating ? null : instanceById(state.selectedId);
    }

    function updateSummary(item) {
        const status = item && item.update_status;
        if (!status) return "Не проверялось";
        if (status.result === "error") return `Ошибка: ${status.error || "проверка обновления"}`;
        const installed = status.installed || item.version || "—";
        const latest = status.latest || "—";
        if (status.updated === true) return `Обновлено: ${installed || "—"} → ${latest}`;
        if (status.update_available === true) return `Доступно ${latest}; установлено ${installed}`;
        if (status.update_available === false) return `Актуально: ${latest || installed}`;
        return `Установлено ${installed}; последнее ${latest}`;
    }

    function renderList() {
        const query = String(search.value || "").trim().toLowerCase();
        const items = (state.data.instances || []).filter((item) => {
            if (!query) return true;
            return `${item.id || ""} ${item.display_name || ""} ${item.properties?.["server-name"] || ""}`.toLowerCase().includes(query);
        });
        listBox.replaceChildren();

        if (!items.length) {
            const empty = document.createElement("div");
            empty.className = "mc-empty";
            empty.textContent = query ? "Серверы не найдены." : "Minecraft-серверы ещё не зарегистрированы.";
            listBox.appendChild(empty);
            return;
        }

        for (const item of items) {
            const button = document.createElement("button");
            button.type = "button";
            button.className = "minecraft-instance-row";
            if (!state.creating && String(item.id) === String(state.selectedId)) button.classList.add("active");
            const stateKind = item.state === "active" ? "ok" : item.state === "failed" ? "error" : "warn";
            button.innerHTML = `
                <strong>${esc(item.display_name || item.id)}</strong>
                <small>${esc(item.id)} · ${esc(item.server_port || "—")}/UDP · ${esc(item.version || "версия —")}</small>
                <div class="mc-badges">
                    ${badge(labelState(item.state), stateKind)}
                    ${badge(item.published ? "Опубликован" : "Не опубликован", item.published ? "ok" : "")}
                    ${badge(item.update_mode === "automatic" ? "Автообновление" : "Ручное обновление")}
                    ${item.managed ? badge("Управляемый") : badge("Импортирован", "warn")}
                </div>`;
            button.addEventListener("click", () => {
                if (state.dirty && !window.confirm("Есть несохранённые изменения. Переключиться без сохранения?")) return;
                state.creating = false;
                state.dirty = false;
                state.selectedId = item.id;
                renderList();
                renderEditor();
            });
            listBox.appendChild(button);
        }
    }

    function controlDisabled() {
        return !state.canWrite || state.busy ? "disabled" : "";
    }

    function property(item, key, fallback = "") {
        const value = item?.properties?.[key];
        return value == null || value === "" ? fallback : value;
    }

    function renderCreateEditor() {
        const ports = state.data.available_ports || {};
        const port = Number(ports.ipv4_start || 19132);
        const port6 = Number(ports.ipv6_start || port + 1);
        const sources = (state.data.instances || []).filter((item) => item.working_directory);
        editor.innerHTML = `
            <section class="mc-section">
                <h2 class="mc-section-title">Новый Minecraft Bedrock Server</h2>
                <form id="mcCreateForm">
                    <div class="mc-grid">
                        <label>ID сервера<input name="id" required maxlength="32" pattern="[a-z0-9][a-z0-9_-]{0,31}" placeholder="survival"></label>
                        <label>Отображаемое имя<input name="display_name" required maxlength="80" placeholder="Основной сервер"></label>
                        <label>Источник Bedrock runtime
                            <select name="source_instance" ${sources.length ? "" : "disabled"}>
                                ${sources.map((item) => `<option value="${esc(item.id)}">${esc(item.display_name || item.id)}</option>`).join("")}
                            </select>
                        </label>
                        <label>IPv4 UDP порт<input name="server_port" type="number" min="1" max="65535" value="${port}" required></label>
                        <label>IPv6 UDP порт<input name="server_portv6" type="number" min="1" max="65535" value="${port6}" required></label>
                        <label>Имя мира<input name="level_name" maxlength="80" value="world-new" required></label>
                        <label>Обновления
                            <select name="update_mode"><option value="manual">Вручную</option><option value="automatic">Автоматически</option></select>
                        </label>
                    </div>
                    <div class="mc-checks">
                        <label><input name="published" type="checkbox"> Опубликован в сети</label>
                        <label><input name="start" type="checkbox"> Запустить после создания</label>
                        <label><input name="eula_accepted" type="checkbox"> Принимаю Minecraft EULA / Privacy для загрузки и автообновлений</label>
                    </div>
                    ${sources.length ? "" : '<div class="mc-warning">Для создания дополнительного экземпляра нужен уже установленный Bedrock runtime. Сначала установите/импортируйте основной сервер.</div>'}
                    <div class="mc-actions"><button class="action-button" type="submit" ${controlDisabled()} ${sources.length ? "" : "disabled"}>Создать сервер</button><button class="secondary-button" id="mcCancelCreate" type="button">Отмена</button></div>
                </form>
            </section>`;

        const form = byId("mcCreateForm");
        form.addEventListener("input", () => { state.dirty = true; });
        form.addEventListener("change", () => { state.dirty = true; });
        byId("mcCancelCreate").addEventListener("click", () => {
            state.creating = false;
            state.dirty = false;
            renderEditor();
        });
        form.addEventListener("submit", async (event) => {
            event.preventDefault();
            const data = new FormData(form);
            const id = String(data.get("id") || "").trim().toLowerCase();
            const updateMode = String(data.get("update_mode") || "manual");
            const eula = data.get("eula_accepted") === "on";
            if (updateMode === "automatic" && !eula) {
                setMessage("Для автоматического обновления необходимо подтвердить EULA / Privacy.", true);
                return;
            }
            await queueOperation(() => postJson("/api/v1/minecraft/instances", {
                id,
                display_name: String(data.get("display_name") || "").trim(),
                source_instance: String(data.get("source_instance") || ""),
                server_port: Number(data.get("server_port")),
                server_portv6: Number(data.get("server_portv6")),
                level_name: String(data.get("level_name") || "").trim(),
                update_mode: updateMode,
                published: data.get("published") === "on",
                start: data.get("start") === "on",
                eula_accepted: eula,
            }), "Создание Minecraft-сервера поставлено в очередь.", id);
        });
    }

    function playerRows(item) {
        const players = item.players?.known || [];
        const allowed = new Set((item.players?.allowlist || []).map((row) => String(row.name || "").toLowerCase()));
        if (!players.length) return '<tr><td colspan="6">Игроки пока не обнаружены.</td></tr>';
        return players.map((player, index) => {
            const name = String(player.name || "");
            const xuid = String(player.xuid || "");
            const permission = String(player.permission || "member");
            const isAllowed = allowed.has(name.toLowerCase());
            return `<tr data-player-index="${index}">
                <td><div class="player-name"><strong>${esc(name)}</strong><span>${esc(xuid || "XUID неизвестен")}</span></div></td>
                <td>${player.online ? badge("Онлайн", "ok") : badge("Оффлайн")}</td>
                <td>${isAllowed ? badge("Разрешён", "ok") : badge("Нет")}</td>
                <td><select class="player-permission" ${state.canWrite && xuid ? "" : "disabled"}><option value="visitor" ${permission === "visitor" ? "selected" : ""}>Visitor</option><option value="member" ${permission === "member" ? "selected" : ""}>Member</option><option value="operator" ${permission === "operator" ? "selected" : ""}>Operator</option></select></td>
                <td><button class="secondary-button player-save-permission" type="button" ${state.canWrite && xuid ? "" : "disabled"}>Применить</button></td>
                <td><div class="mc-actions">
                    <button class="secondary-button player-toggle-allow" type="button" ${state.canWrite ? "" : "disabled"}>${isAllowed ? "Убрать" : "Разрешить"}</button>
                    <button class="danger-button player-kick" type="button" ${state.canWrite && player.online && item.command_channel ? "" : "disabled"}>Kick</button>
                </div></td>
            </tr>`;
        }).join("");
    }

    function renderExistingEditor(item) {
        const update = item.update_status || {};
        const p = item.properties || {};
        const managedWarning = item.managed ? "" : '<div class="mc-warning">Это импортированный/legacy экземпляр. Его параметры можно менять, но удаление самого экземпляра через Control Center запрещено.</div>';
        editor.innerHTML = `
            <section class="mc-section">
                <h2 class="mc-section-title">${esc(item.display_name || item.id)}</h2>
                <div class="mc-badges">
                    ${badge(labelState(item.state), item.state === "active" ? "ok" : item.state === "failed" ? "error" : "warn")}
                    ${badge(item.published ? "Опубликован" : "Не опубликован", item.published ? "ok" : "")}
                    ${badge(item.version ? `Bedrock ${item.version}` : "Версия неизвестна")}
                    ${badge(item.command_channel ? "Командный канал" : "Без command channel", item.command_channel ? "ok" : "warn")}
                </div>
                ${managedWarning}
                <div class="mc-actions">
                    ${item.state === "active" ? `<button class="action-button" data-control="restart" type="button" ${controlDisabled()}>Перезапустить</button><button class="secondary-button" data-control="stop" type="button" ${controlDisabled()}>Остановить</button>` : `<button class="action-button" data-control="start" type="button" ${controlDisabled()}>Запустить</button>`}
                </div>
            </section>

            <section class="mc-section">
                <h2 class="mc-section-title">Параметры сервера</h2>
                <form id="mcInstanceForm">
                    <div class="mc-grid">
                        <label>Отображаемое имя<input name="display_name" maxlength="80" value="${esc(item.display_name || item.id)}" ${state.canWrite ? "" : "disabled"}></label>
                        <label>Имя Bedrock<input name="server-name" maxlength="80" value="${esc(property(item, "server-name", item.display_name || item.id))}" ${state.canWrite ? "" : "disabled"}></label>
                        <label>Обновления<select name="update_mode" ${state.canWrite ? "" : "disabled"}><option value="manual" ${item.update_mode !== "automatic" ? "selected" : ""}>Вручную</option><option value="automatic" ${item.update_mode === "automatic" ? "selected" : ""}>Автоматически</option></select></label>
                        <label>Режим игры<select name="gamemode" ${state.canWrite ? "" : "disabled"}><option value="survival" ${property(item,"gamemode","survival") === "survival" ? "selected" : ""}>Survival</option><option value="creative" ${property(item,"gamemode") === "creative" ? "selected" : ""}>Creative</option><option value="adventure" ${property(item,"gamemode") === "adventure" ? "selected" : ""}>Adventure</option></select></label>
                        <label>Сложность<select name="difficulty" ${state.canWrite ? "" : "disabled"}><option value="peaceful" ${property(item,"difficulty") === "peaceful" ? "selected" : ""}>Peaceful</option><option value="easy" ${property(item,"difficulty","easy") === "easy" ? "selected" : ""}>Easy</option><option value="normal" ${property(item,"difficulty") === "normal" ? "selected" : ""}>Normal</option><option value="hard" ${property(item,"difficulty") === "hard" ? "selected" : ""}>Hard</option></select></label>
                        <label>Максимум игроков<input name="max-players" type="number" min="1" max="1000" value="${esc(property(item,"max-players",10))}" ${state.canWrite ? "" : "disabled"}></label>
                        <label>IPv4 UDP порт<input name="server-port" type="number" min="1" max="65535" value="${esc(property(item,"server-port",item.server_port || 19132))}" ${state.canWrite ? "" : "disabled"}></label>
                        <label>IPv6 UDP порт<input name="server-portv6" type="number" min="1" max="65535" value="${esc(property(item,"server-portv6",item.server_portv6 || 19133))}" ${state.canWrite ? "" : "disabled"}></label>
                        <label>Мир<input name="level-name" maxlength="80" value="${esc(property(item,"level-name","Bedrock level"))}" ${state.canWrite ? "" : "disabled"}></label>
                        <label>View distance<input name="view-distance" type="number" min="5" max="64" value="${esc(property(item,"view-distance",32))}" ${state.canWrite ? "" : "disabled"}></label>
                        <label>Tick distance<input name="tick-distance" type="number" min="4" max="12" value="${esc(property(item,"tick-distance",4))}" ${state.canWrite ? "" : "disabled"}></label>
                        <label>Idle timeout, мин<input name="player-idle-timeout" type="number" min="0" max="100000" value="${esc(property(item,"player-idle-timeout",30))}" ${state.canWrite ? "" : "disabled"}></label>
                        <label>Online mode<select name="online-mode" ${state.canWrite ? "" : "disabled"}><option value="true" ${boolValue(property(item,"online-mode",true)) ? "selected" : ""}>Включён</option><option value="false" ${!boolValue(property(item,"online-mode",true)) ? "selected" : ""}>Выключен</option></select></label>
                        <label>Allow list<select name="allow-list" ${state.canWrite ? "" : "disabled"}><option value="false" ${!boolValue(property(item,"allow-list",false)) ? "selected" : ""}>Выключен</option><option value="true" ${boolValue(property(item,"allow-list",false)) ? "selected" : ""}>Включён</option></select></label>
                        <label>Читы<select name="allow-cheats" ${state.canWrite ? "" : "disabled"}><option value="false" ${!boolValue(property(item,"allow-cheats",false)) ? "selected" : ""}>Запрещены</option><option value="true" ${boolValue(property(item,"allow-cheats",false)) ? "selected" : ""}>Разрешены</option></select></label>
                    </div>
                    <div class="mc-checks">
                        <label><input name="published" type="checkbox" ${item.published ? "checked" : ""} ${state.canWrite ? "" : "disabled"}> Опубликован в сети</label>
                        <label><input name="eula_accepted" type="checkbox" ${item.eula_accepted ? "checked" : ""} ${state.canWrite ? "" : "disabled"}> EULA / Privacy приняты для загрузки обновлений</label>
                    </div>
                    <div class="mc-actions"><button class="action-button" type="submit" ${controlDisabled()}>Сохранить параметры</button></div>
                </form>
            </section>

            <section class="mc-section">
                <h2 class="mc-section-title">Обновление Bedrock Server</h2>
                <div class="mc-note">${esc(updateSummary(item))}</div>
                ${update.checked_at ? `<div class="mc-note">Проверено: ${esc(update.checked_at)}</div>` : ""}
                <div class="mc-actions">
                    <button class="secondary-button" id="mcCheckUpdate" type="button" ${controlDisabled()}>Проверить обновление</button>
                    <button class="action-button" id="mcApplyUpdate" type="button" ${controlDisabled()}>Обновить сервер</button>
                </div>
                <div class="mc-note">Перед установкой создаётся резервная копия мира и конфигурации. При ошибке runtime откатывается автоматически.</div>
            </section>

            <section class="mc-section">
                <h2 class="mc-section-title">Игроки</h2>
                <form class="player-toolbar" id="mcAllowPlayerForm">
                    <input name="name" maxlength="64" placeholder="Имя игрока" required ${state.canWrite ? "" : "disabled"}>
                    <input name="xuid" maxlength="64" placeholder="XUID (если известен)" ${state.canWrite ? "" : "disabled"}>
                    <select name="permission" ${state.canWrite ? "" : "disabled"}><option value="member">Member</option><option value="visitor">Visitor</option><option value="operator">Operator</option></select>
                    <button class="action-button" type="submit" ${controlDisabled()}>Разрешить</button>
                </form>
                <div class="player-table-wrap"><table class="player-table"><thead><tr><th>Игрок</th><th>Статус</th><th>Allow list</th><th>Права</th><th></th><th>Действия</th></tr></thead><tbody>${playerRows(item)}</tbody></table></div>
            </section>

            ${item.managed ? `<section class="mc-section"><h2 class="mc-section-title">Удаление экземпляра</h2><div class="mc-danger">Удаление записи сервера и удаление его файлов — разные операции. Удаление данных доступно только полному администратору.</div><div class="mc-actions"><button class="danger-button" id="mcDeleteInstance" type="button" ${controlDisabled()}>Удалить сервер</button>${state.fullAdmin ? `<button class="danger-button" id="mcDeleteInstanceData" type="button" ${controlDisabled()}>Удалить сервер и данные</button>` : ""}</div></section>` : ""}
        `;
        bindExistingEditor(item);
    }

    function renderEditor() {
        if (state.creating) {
            renderCreateEditor();
            return;
        }
        const item = selectedInstance();
        if (!item) {
            editor.innerHTML = '<div class="mc-empty">Выберите Minecraft-сервер или создайте новый.</div>';
            return;
        }
        renderExistingEditor(item);
    }

    function bindExistingEditor(item) {
        document.querySelectorAll("[data-control]").forEach((button) => {
            button.addEventListener("click", () => queueOperation(
                () => postJson(`/api/v1/minecraft/instances/${encodeURIComponent(item.id)}/control/${encodeURIComponent(button.dataset.control)}`),
                "Команда серверу поставлена в очередь.", item.id,
            ));
        });

        const form = byId("mcInstanceForm");
        form.addEventListener("input", () => { state.dirty = true; });
        form.addEventListener("change", () => { state.dirty = true; });
        form.addEventListener("submit", async (event) => {
            event.preventDefault();
            const data = new FormData(form);
            const updateMode = String(data.get("update_mode") || "manual");
            const eula = data.get("eula_accepted") === "on";
            if (updateMode === "automatic" && !eula && !item.eula_accepted) {
                setMessage("Для автоматического обновления необходимо подтвердить EULA / Privacy.", true);
                return;
            }
            const properties = {};
            for (const name of ["server-name","gamemode","difficulty","max-players","server-port","server-portv6","level-name","view-distance","tick-distance","player-idle-timeout","online-mode","allow-list","allow-cheats"]) {
                properties[name] = String(data.get(name) ?? "");
            }
            await queueOperation(() => postJson(`/api/v1/minecraft/instances/${encodeURIComponent(item.id)}/update`, {
                display_name: String(data.get("display_name") || "").trim(),
                update_mode: updateMode,
                published: data.get("published") === "on",
                eula_accepted: eula,
                properties,
            }), "Параметры Minecraft поставлены в очередь на применение.", item.id);
        });

        byId("mcCheckUpdate").addEventListener("click", () => queueOperation(
            () => postJson(`/api/v1/minecraft/instances/${encodeURIComponent(item.id)}/update/check`),
            "Проверка версии поставлена в очередь.", item.id,
        ));
        byId("mcApplyUpdate").addEventListener("click", () => {
            const eula = form.elements.eula_accepted.checked || Boolean(item.eula_accepted);
            if (!eula) {
                setMessage("Перед загрузкой обновления подтвердите EULA / Privacy и сохраните настройки.", true);
                return;
            }
            queueOperation(
                () => postJson(`/api/v1/minecraft/instances/${encodeURIComponent(item.id)}/update/apply`, {eula_accepted: true}),
                "Обновление Minecraft поставлено в очередь. Перед заменой runtime будет создан backup.", item.id,
            );
        });

        const allowForm = byId("mcAllowPlayerForm");
        allowForm.addEventListener("submit", async (event) => {
            event.preventDefault();
            const data = new FormData(allowForm);
            const name = String(data.get("name") || "").trim();
            const xuid = String(data.get("xuid") || "").trim();
            const permission = String(data.get("permission") || "member");
            await queueOperation(async () => {
                await postJson(`/api/v1/minecraft/instances/${encodeURIComponent(item.id)}/players/allow`, {name, xuid});
                if (xuid) {
                    await postJson(`/api/v1/minecraft/instances/${encodeURIComponent(item.id)}/players/permission`, {name, xuid, permission});
                }
            }, "Игрок добавлен в очередь управления allow list.", item.id);
        });

        const players = item.players?.known || [];
        document.querySelectorAll("tr[data-player-index]").forEach((row) => {
            const player = players[Number(row.dataset.playerIndex)];
            if (!player) return;
            row.querySelector(".player-save-permission")?.addEventListener("click", () => {
                const permission = row.querySelector(".player-permission")?.value || "member";
                queueOperation(() => postJson(`/api/v1/minecraft/instances/${encodeURIComponent(item.id)}/players/permission`, {
                    name: player.name, xuid: player.xuid, permission,
                }), "Права игрока поставлены в очередь на применение.", item.id);
            });
            row.querySelector(".player-toggle-allow")?.addEventListener("click", () => {
                const allowed = (item.players?.allowlist || []).some((entry) => String(entry.name || "").toLowerCase() === String(player.name || "").toLowerCase());
                const operation = allowed ? "deny" : "allow";
                queueOperation(() => postJson(`/api/v1/minecraft/instances/${encodeURIComponent(item.id)}/players/${operation}`, {
                    name: player.name, xuid: player.xuid || "",
                }), allowed ? "Удаление игрока из allow list поставлено в очередь." : "Добавление игрока в allow list поставлено в очередь.", item.id);
            });
            row.querySelector(".player-kick")?.addEventListener("click", () => {
                const reason = window.prompt("Причина отключения игрока", "Отключено администратором");
                if (reason === null) return;
                queueOperation(() => postJson(`/api/v1/minecraft/instances/${encodeURIComponent(item.id)}/players/kick`, {
                    name: player.name, reason,
                }), "Команда Kick поставлена в очередь.", item.id);
            });
        });

        byId("mcDeleteInstance")?.addEventListener("click", () => deleteInstance(item, false));
        byId("mcDeleteInstanceData")?.addEventListener("click", () => deleteInstance(item, true));
    }

    async function deleteInstance(item, deleteData) {
        const question = deleteData
            ? `Удалить сервер «${item.display_name || item.id}» и ВСЕ его данные, включая миры?`
            : `Удалить сервер «${item.display_name || item.id}» из Control Center, сохранив данные?`;
        if (!window.confirm(question)) return;
        if (deleteData && !window.confirm("Это необратимое удаление данных Minecraft. Подтвердить ещё раз?")) return;
        await queueOperation(() => postJson(`/api/v1/minecraft/instances/${encodeURIComponent(item.id)}/delete`, {delete_data: deleteData}),
            deleteData ? "Удаление сервера и данных поставлено в очередь." : "Удаление сервера поставлено в очередь.", null);
        state.selectedId = null;
    }

    async function queueOperation(callback, text, selectId = null) {
        if (state.busy) return;
        state.busy = true;
        setMessage("");
        try {
            await callback();
            state.dirty = false;
            if (selectId !== undefined) state.selectedId = selectId;
            state.creating = false;
            setMessage(text);
            window.setTimeout(() => refresh(true).catch(() => {}), 1200);
            window.setTimeout(() => refresh(true).catch(() => {}), 3500);
        } catch (error) {
            setMessage(error.message || "Операция Minecraft не выполнена.", true);
        } finally {
            state.busy = false;
            renderList();
            if (!state.dirty) renderEditor();
        }
    }

    async function refresh(forceEditor = false) {
        const response = await api("/api/v1/minecraft/instances");
        const data = response.data || {};
        state.data = {
            instances: Array.isArray(data.instances) ? data.instances : [],
            available_ports: data.available_ports || {ipv4_start: 19132, ipv6_start: 19133},
        };
        state.canWrite = Boolean(data.can_write);
        state.fullAdmin = Boolean(data.full_admin);
        newButton.disabled = !state.canWrite;

        if (!state.creating && state.selectedId && !instanceById(state.selectedId)) state.selectedId = null;
        if (!state.selectedId && !state.creating && state.data.instances.length) state.selectedId = state.data.instances[0].id;
        renderList();
        if (!state.dirty || forceEditor) renderEditor();
    }

    async function start() {
        const auth = await api("/api/v1/auth/status");
        state.csrf = auth.data?.csrf_token || "";
        await refresh(true);
    }

    search.addEventListener("input", renderList);
    newButton.addEventListener("click", () => {
        if (!state.canWrite) return;
        if (state.dirty && !window.confirm("Есть несохранённые изменения. Создать новый сервер без сохранения?")) return;
        state.creating = true;
        state.dirty = false;
        renderList();
        renderEditor();
    });

    start().catch((error) => setMessage(error.message || "Не удалось загрузить Minecraft.", true));
    window.setInterval(() => {
        if (!state.busy) refresh(false).catch(() => {});
    }, 10000);
})();
