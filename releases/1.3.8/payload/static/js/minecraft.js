(() => {
    "use strict";

    const $ = (id) => document.getElementById(id);
    const BASE = "/api/v1/minecraft/legacy";
    const state = {csrf: "", canWrite: false, fullAdmin: false, busy: false, overview: null};

    function esc(value) {
        return String(value ?? "")
            .replaceAll("&", "&amp;").replaceAll("<", "&lt;").replaceAll(">", "&gt;")
            .replaceAll('"', "&quot;").replaceAll("'", "&#39;");
    }
    function message(text, error = false) {
        const box = $("minecraftMessage");
        box.textContent = text || "";
        box.classList.toggle("error", error);
    }
    function setBusy(value) {
        state.busy = Boolean(value);
        document.querySelectorAll("button").forEach((button) => {
            if (button.classList.contains("mc132-tab")) return;
            button.disabled = state.busy || (!state.canWrite && button.dataset.write === "1");
        });
    }
    async function api(url, options = {}) {
        const response = await fetch(url, {cache: "no-store", ...options});
        if (response.status === 401) {
            window.top.location.replace("/login");
            throw new Error("Требуется вход в систему");
        }
        let payload = null;
        try { payload = await response.json(); } catch (_) {}
        if (!response.ok || !payload || payload.ok === false) {
            const detail = payload?.detail || payload?.error || `HTTP ${response.status}`;
            throw new Error(String(detail));
        }
        return payload.data ?? payload;
    }
    function writeOptions(method, body) {
        const options = {method, headers: {"X-CSRF-Token": state.csrf}};
        if (body !== undefined) {
            options.headers["Content-Type"] = "application/json";
            options.body = JSON.stringify(body);
        }
        return options;
    }
    async function write(url, method = "POST", body) {
        return api(url, writeOptions(method, body));
    }
    function text(id, value, fallback = "—") { $(id).textContent = value === undefined || value === null || value === "" ? fallback : String(value); }
    function badge(id, label, kind = "") {
        const node = $(id); node.textContent = label; node.className = `mc-badge ${kind}`.trim();
    }
    function details(id, rows) {
        $(id).innerHTML = rows.map(([k,v]) => `<dt>${esc(k)}</dt><dd>${esc(v ?? "—")}</dd>`).join("");
    }
    function humanBytes(bytes) {
        const n = Number(bytes || 0); if (!Number.isFinite(n) || n <= 0) return "—";
        const units = ["B","KB","MB","GB","TB"]; let value=n, i=0;
        while (value >= 1024 && i < units.length-1) { value /= 1024; i += 1; }
        return `${value.toFixed(i > 1 ? 1 : 0)} ${units[i]}`;
    }
    function firstArray(obj, ...keys) {
        for (const key of keys) if (Array.isArray(obj?.[key])) return obj[key];
        return [];
    }

    async function loadAuth() {
        const auth = await api("/api/v1/auth/status");
        state.csrf = auth.csrf_token || "";
    }

    async function loadOverview() {
        const data = await api(`${BASE}/overview`);
        state.overview = data;
        state.canWrite = Boolean(data.can_write);
        state.fullAdmin = Boolean(data.full_admin);
        const s = data.status || {};
        const u = data.updater || {};
        const p = data.players || {};
        const b = data.backups || {};
        const live = data.live || {};

        const active = Boolean(s.active);
        badge("serviceBadge", active ? "Сервер работает" : "Сервер остановлен", active ? "ok" : "warn");
        text("summaryState", active ? "ONLINE" : "OFFLINE");
        text("summaryName", s.server_name);
        text("summaryVersion", s.version);
        text("summaryStarted", s.started);
        text("summaryWorld", s.level_name);
        text("summaryMode", [s.gamemode, s.difficulty].filter(Boolean).join(" · "));
        text("summaryPlayers", p.online_count ?? 0);
        text("summaryMaxPlayers", s.max_players ? `из ${s.max_players}` : "онлайн");
        text("summaryUpdate", u.installed_version || s.version);
        text("summarySchedule", u.schedule || (u.timer_enabled ? "автообновление включено" : "ручной режим"));

        details("serviceDetails", [
            ["Служба", s.service || "minecraft.service"], ["PID", s.main_pid], ["Память", s.memory_human],
            ["Порт", s.port], ["Мир", s.level_name], ["Версия", s.version]
        ]);
        details("updaterDetails", [
            ["Установлено", u.installed_version || s.version], ["Timer enabled", u.timer_enabled],
            ["Timer active", u.timer_active], ["Расписание", u.schedule]
        ]);
        const backups = firstArray(b, "backups");
        text("backupSummary", backups.length ? `Доступно копий: ${backups.length}` : "Резервные копии не найдены");
        text("liveSummary", `Командный канал: ${live.ready ? "READY" : "OFFLINE"}`);

        const errs = data.errors || {};
        const errorBox = $("overviewErrors");
        if (Object.keys(errs).length) {
            errorBox.classList.remove("hidden");
            errorBox.textContent = Object.entries(errs).map(([k,v]) => `${k}: ${v}`).join(" · ");
        } else { errorBox.classList.add("hidden"); errorBox.textContent = ""; }
        setBusy(false);
    }

    async function serviceAction(action) {
        if (action !== "start" && !window.confirm(`${action === "stop" ? "Остановить" : "Перезапустить"} Minecraft сервер?`)) return;
        setBusy(true); message("Выполняется команда управления сервером…");
        try { const d = await write(`${BASE}/service/${action}`); message(d.message || "Команда выполнена."); await loadOverview(); }
        catch (e) { message(`Ошибка управления: ${e.message}`, true); setBusy(false); }
    }

    async function updateNow() {
        if (!window.confirm("Проверить актуальную версию Minecraft Bedrock и при необходимости обновить сервер сейчас? Перед обновлением прежний updater сам выполняет предусмотренную им процедуру.")) return;
        setBusy(true); message("Проверка и обновление Minecraft выполняются. Это может занять несколько минут…");
        try { const d = await write(`${BASE}/update`); message(d.message || "Проверка обновления завершена."); await Promise.all([loadOverview(), loadBackups(), loadLogs()]); }
        catch (e) { message(`Ошибка обновления: ${e.message}`, true); setBusy(false); }
    }

    async function backupNow() {
        setBusy(true); message("Создаётся резервная копия Minecraft…");
        try { const d = await write(`${BASE}/backup`); message(d.message || "Резервная копия создана."); await loadBackups(); await loadOverview(); }
        catch (e) { message(`Ошибка backup: ${e.message}`, true); setBusy(false); }
    }

    async function broadcast() {
        const value = $("broadcastMessage").value.trim(); if (!value) return message("Введите сообщение для игроков.", true);
        setBusy(true);
        try { const d = await write(`${BASE}/live/say`, "POST", {message:value}); $("broadcastMessage").value=""; message(d.message || "Сообщение отправлено."); }
        catch(e){ message(`Ошибка live-консоли: ${e.message}`, true); }
        finally { setBusy(false); }
    }

    const settingIds = ["server-name","level-name","gamemode","difficulty","max-players","server-port","server-portv6","view-distance","tick-distance","player-idle-timeout","default-player-permission-level","online-mode","allow-list","allow-cheats"];
    async function loadSettings() {
        const [data, worlds] = await Promise.all([api(`${BASE}/properties`), api(`${BASE}/worlds`)]);
        state.canWrite = Boolean(data.can_write ?? state.canWrite);
        const props = data.properties || data.values || {};
        const worldSelect = $("level-name");
        worldSelect.replaceChildren();
        const worldItems = firstArray(worlds, "worlds");
        for (const world of worldItems) {
            const option=document.createElement("option"); option.value=world.name; option.textContent=`${world.name}${world.size_human ? ` · ${world.size_human}` : ""}`; worldSelect.appendChild(option);
        }
        if (!worldItems.length && props["level-name"]) { const option=document.createElement("option"); option.value=props["level-name"]; option.textContent=props["level-name"]; worldSelect.appendChild(option); }
        for (const id of settingIds) if ($(id) && props[id] !== undefined) $(id).value = String(props[id]);
        document.querySelectorAll("#settingsForm input,#settingsForm select,#settingsForm button").forEach((el)=>{el.disabled=!state.canWrite;});
    }
    async function saveSettings(event) {
        event.preventDefault();
        const changes = {}; for (const id of settingIds) changes[id] = $(id).value;
        setBusy(true); message("Сохраняю server.properties…");
        try { const d=await write(`${BASE}/properties`, "PUT", {changes}); message(d.message || "Параметры сохранены."); await Promise.all([loadSettings(), loadOverview()]); }
        catch(e){ message(`Ошибка сохранения: ${e.message}`, true); setBusy(false); }
    }

    function rowButton(label, cls, handler, disabled=false) {
        const b=document.createElement("button"); b.type="button"; b.textContent=label; b.className=cls || "secondary-button"; b.disabled=disabled || !state.canWrite; b.addEventListener("click",handler); return b;
    }
    async function loadPlayers() {
        const d=await api(`${BASE}/players`); state.canWrite=Boolean(d.can_write ?? state.canWrite);
        const body=$("playersBody"); body.replaceChildren(); const players=firstArray(d,"players");
        $("playerSettings").innerHTML = `<span class="mc-badge ${d.allow_list_enabled ? "ok" : "warn"}">Allow-list: ${d.allow_list_enabled ? "включён" : "выключен"}</span><span class="mc-badge">По умолчанию: ${esc(d.default_permission || "member")}</span><span class="mc-badge ok">Онлайн: ${esc(d.online_count ?? 0)}</span>`;
        if (!players.length) { body.innerHTML='<tr><td colspan="5" class="mc132-dim">Игроки ещё не обнаружены.</td></tr>'; return; }
        for (const player of players) {
            const tr=document.createElement("tr");
            const name=document.createElement("td"); name.innerHTML=`<div class="player-name"><strong>${esc(player.name || "—")}</strong><span>${esc(player.xuid || "XUID неизвестен")}</span></div>`;
            const online=document.createElement("td"); online.innerHTML=player.online?'<span class="mc-badge ok">ONLINE</span>':'<span class="mc-badge">offline</span>';
            const allow=document.createElement("td"); allow.innerHTML=player.allowlisted?'<span class="mc-badge ok">Разрешён</span>':'<span class="mc-badge warn">Нет</span>';
            const perm=document.createElement("td"); const select=document.createElement("select"); select.className="player-permission"; ["","visitor","member","operator"].forEach((v)=>{const o=document.createElement("option");o.value=v;o.textContent=v||`по умолчанию (${d.default_permission || "member"})`;select.appendChild(o);}); select.value=player.permission||""; select.disabled=!state.canWrite||!player.xuid; perm.appendChild(select);
            const actions=document.createElement("td"); actions.className="mc132-row-actions";
            if (player.allowlisted) actions.appendChild(rowButton("Убрать", "danger-button", ()=>removeAllow(player.name || player.xuid)));
            else if (player.name) actions.appendChild(rowButton("В Allow-list", "secondary-button", ()=>quickAllow(player)));
            if (player.xuid) actions.appendChild(rowButton("Права", "secondary-button", ()=>savePermission(player.xuid,select.value)));
            if (player.online && player.name) { actions.appendChild(rowButton("Kick","danger-button",()=>livePlayer("kick",player.name))); actions.appendChild(rowButton("OP","secondary-button",()=>livePlayer("op",player.name))); actions.appendChild(rowButton("DeOP","secondary-button",()=>livePlayer("deop",player.name))); }
            tr.append(name,online,allow,perm,actions); body.appendChild(tr);
        }
    }
    async function addAllow() {
        const name=$("newPlayerName").value.trim(), xuid=$("newPlayerXuid").value.trim(), permission=$("newPlayerPermission").value;
        if(!name) return message("Введите имя игрока.",true); setBusy(true);
        try { await write(`${BASE}/players/allowlist`,"POST",{name,xuid,ignores_player_limit:false}); if(xuid&&permission) await write(`${BASE}/players/${encodeURIComponent(xuid)}/permission`,"PUT",{permission}); $("newPlayerName").value=""; $("newPlayerXuid").value=""; message("Игрок добавлен."); await loadPlayers(); }
        catch(e){message(`Ошибка игрока: ${e.message}`,true);} finally{setBusy(false);}
    }
    async function quickAllow(player){setBusy(true);try{await write(`${BASE}/players/allowlist`,"POST",{name:player.name,xuid:player.xuid||"",ignores_player_limit:false});message("Игрок добавлен в Allow-list.");await loadPlayers();}catch(e){message(e.message,true);}finally{setBusy(false);}}
    async function removeAllow(key){if(!confirm(`Убрать ${key} из Allow-list?`))return;setBusy(true);try{await write(`${BASE}/players/allowlist/${encodeURIComponent(key)}`,"DELETE");message("Игрок удалён из Allow-list.");await loadPlayers();}catch(e){message(e.message,true);}finally{setBusy(false);}}
    async function savePermission(xuid,permission){setBusy(true);try{if(permission)await write(`${BASE}/players/${encodeURIComponent(xuid)}/permission`,"PUT",{permission});else await write(`${BASE}/players/${encodeURIComponent(xuid)}/permission`,"DELETE");message("Права игрока обновлены.");await loadPlayers();}catch(e){message(e.message,true);}finally{setBusy(false);}}
    async function livePlayer(action,username){if(action==="kick"&&!confirm(`Отключить игрока ${username}?`))return;setBusy(true);try{const body={username};if(action==="kick")body.reason="Отключён администратором";await write(`${BASE}/live/${action}`,"POST",body);message(`${action.toUpperCase()} выполнен для ${username}.`);setTimeout(()=>loadPlayers().catch(()=>{}),1000);}catch(e){message(e.message,true);}finally{setBusy(false);}}

    async function loadWorlds(){const d=await api(`${BASE}/worlds`);state.canWrite=Boolean(d.can_write??state.canWrite);const body=$("worldsBody");body.replaceChildren();const worlds=firstArray(d,"worlds");if(!worlds.length){body.innerHTML='<tr><td colspan="5" class="mc132-dim">Миры не найдены.</td></tr>';return;}for(const world of worlds){const tr=document.createElement("tr");tr.innerHTML=`<td><strong>${esc(world.name)}</strong></td><td>${esc(world.size_human||humanBytes(world.size))}</td><td>${esc(world.modified||"—")}</td><td>${world.active?'<span class="mc-badge ok">Активный</span>':'<span class="mc-badge">—</span>'}</td><td></td>`;const a=tr.lastElementChild;a.className="mc132-row-actions";a.append(rowButton("Активировать","secondary-button",()=>worldAction("activate",world.name),world.active),rowButton("Клонировать","secondary-button",()=>worldAction("clone",world.name)),rowButton("Переименовать","secondary-button",()=>worldAction("rename",world.name,world.active)),rowButton("Удалить","danger-button",()=>worldAction("delete",world.name),world.active));body.appendChild(tr);}}
    async function worldAction(action,name,active=false){let body,method="POST",url=`${BASE}/worlds/${encodeURIComponent(name)}/${action}`;if(action==="activate"&&!confirm(`Активировать мир «${name}»? Minecraft будет перезапущен.`))return;if(action==="clone"||action==="rename"){if(action==="rename"&&active&&!confirm("Это активный мир. Продолжить переименование?"))return;const nn=prompt(`${action==="clone"?"Имя копии":"Новое имя"} мира «${name}»:`,action==="clone"?`${name} - копия`:name);if(nn===null||!nn.trim())return;body={new_name:nn.trim()};}if(action==="delete"){if(!confirm(`Удалить мир «${name}»? Это необратимая операция.`))return;method="DELETE";url=`${BASE}/worlds/${encodeURIComponent(name)}`;body={confirm:name};}setBusy(true);try{const d=await write(url,method,body);message(d.message||"Операция с миром выполнена.");await Promise.all([loadWorlds(),loadSettings(),loadOverview()]);}catch(e){message(`Ошибка мира: ${e.message}`,true);}finally{setBusy(false);}}

    async function loadBackups(){const d=await api(`${BASE}/backups`);state.canWrite=Boolean(d.can_write??state.canWrite);const body=$("backupsBody");body.replaceChildren();const backups=firstArray(d,"backups");if(!backups.length){body.innerHTML='<tr><td colspan="6" class="mc132-dim">Резервные копии не найдены.</td></tr>';return;}for(const b of backups){const tr=document.createElement("tr");const valid=b.valid!==false;tr.innerHTML=`<td><strong>${esc(b.name||b.id||"—")}</strong></td><td>${esc(b.size_human||humanBytes(b.size))}</td><td>${esc(b.mtime||b.created_at||"—")}</td><td>${esc((b.contents||[]).join(", "))}</td><td>${valid?'<span class="mc-badge ok">OK</span>':'<span class="mc-badge error">Ошибка</span>'}</td><td></td>`;const a=tr.lastElementChild;a.className="mc132-row-actions";const name=b.name||b.id;if(valid)a.appendChild(rowButton("Восстановить","secondary-button",()=>restoreBackup(name)));a.appendChild(rowButton("Удалить","danger-button",()=>deleteBackup(name)));body.appendChild(tr);}}
    async function restoreBackup(name){if(!confirm(`Восстановить Minecraft из backup «${name}»? Текущий сервер будет остановлен на время восстановления.`))return;setBusy(true);message("Восстановление Minecraft…");try{const d=await write(`${BASE}/backups/${encodeURIComponent(name)}/restore`);message(d.message||"Восстановление завершено.");await Promise.all([loadOverview(),loadBackups(),loadWorlds(),loadSettings()]);}catch(e){message(`Ошибка восстановления: ${e.message}`,true);}finally{setBusy(false);}}
    async function deleteBackup(name){if(!confirm(`Удалить backup «${name}»?`))return;setBusy(true);try{const d=await write(`${BASE}/backups/${encodeURIComponent(name)}`,"DELETE",{confirm:name});message(d.message||"Backup удалён.");await loadBackups();}catch(e){message(e.message,true);}finally{setBusy(false);}}

    async function loadLogs(){const d=await api(`${BASE}/logs?limit=250`);const lines=firstArray(d,"lines");$("logText").textContent=lines.length?lines.join("\n"):(d.log||d.text||"Журнал пуст.");}

    async function loadAll(){message("Обновление данных…");try{await loadOverview();const active=document.querySelector(".mc132-tab.active")?.dataset.tab||"overview";if(active==="settings")await loadSettings();if(active==="players")await loadPlayers();if(active==="worlds")await loadWorlds();if(active==="backups")await loadBackups();if(active==="logs")await loadLogs();message("");}catch(e){message(`Ошибка загрузки Minecraft: ${e.message}`,true);setBusy(false);}}
    async function openTab(name){document.querySelectorAll(".mc132-tab").forEach((b)=>b.classList.toggle("active",b.dataset.tab===name));document.querySelectorAll(".mc132-tab-panel").forEach((p)=>p.classList.toggle("active",p.dataset.panel===name));try{if(name==="settings")await loadSettings();else if(name==="players")await loadPlayers();else if(name==="worlds")await loadWorlds();else if(name==="backups")await loadBackups();else if(name==="logs")await loadLogs();else await loadOverview();}catch(e){message(`Ошибка раздела: ${e.message}`,true);}}

    document.querySelectorAll(".mc132-tab").forEach((b)=>b.addEventListener("click",()=>openTab(b.dataset.tab)));
    $("refreshAll").addEventListener("click",loadAll); $("serverStart").addEventListener("click",()=>serviceAction("start")); $("serverRestart").addEventListener("click",()=>serviceAction("restart")); $("serverStop").addEventListener("click",()=>serviceAction("stop"));
    $("updateNow").addEventListener("click",updateNow); $("backupNow").addEventListener("click",backupNow); $("broadcastSend").addEventListener("click",broadcast); $("settingsForm").addEventListener("submit",saveSettings); $("reloadSettings").addEventListener("click",loadSettings);
    $("reloadPlayers").addEventListener("click",loadPlayers); $("addPlayer").addEventListener("click",addAllow); $("reloadWorlds").addEventListener("click",loadWorlds); $("reloadBackups").addEventListener("click",loadBackups); $("reloadLogs").addEventListener("click",loadLogs);
    ["serverStart","serverRestart","serverStop","updateNow","backupNow","broadcastSend","addPlayer"].forEach((id)=>$(id).dataset.write="1");

    (async()=>{try{await loadAuth();await loadOverview();message("");window.setInterval(()=>{if(!state.busy&&document.visibilityState==="visible")loadOverview().catch(()=>{});},15000);}catch(e){message(`Minecraft недоступен: ${e.message}`,true);}})();
})();
