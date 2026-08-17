(() => {
    "use strict";

    const byId = (id) => document.getElementById(id);
    let adminState = {authenticated: false, username: null, must_change: false, csrf_token: null};

    const ACTION_LABELS = {
        reboot: "Перезагрузка сервера",
        "os-update": "Обновление ОС и пакетов",
        "auto-updates-enable": "Включение автообновлений",
        "auto-updates-disable": "Отключение автообновлений",
        "service-install-adguard-vpn": "Установка AdGuard VPN",
        "service-remove-adguard-vpn": "Удаление AdGuard VPN",
        "service-refresh-adguard-vpn": "Обновление статуса AdGuard VPN",
        "service-connect-adguard-vpn-socks": "Подключение AdGuard VPN (SOCKS)",
        "service-disconnect-adguard-vpn": "Отключение AdGuard VPN",
        "service-update-adguard-vpn": "Обновление AdGuard VPN CLI",
    };

    function setText(id, value) { const el = byId(id); if (el) el.textContent = value; }
    function setMessage(id, value, kind = "") {
        const el = byId(id); if (!el) return;
        el.textContent = value || ""; el.classList.remove("ok", "error"); if (kind) el.classList.add(kind);
    }
    function formatBytes(value) {
        const amount = Number(value || 0); if (!Number.isFinite(amount) || amount <= 0) return "0 Б";
        const units = ["Б", "КБ", "МБ", "ГБ", "ТБ"]; let number = amount; let index = 0;
        while (number >= 1024 && index < units.length - 1) { number /= 1024; index += 1; }
        return `${number.toFixed(index >= 3 ? 1 : 0)} ${units[index]}`;
    }
    function formatUptime(seconds) {
        let v = Math.max(0, Number(seconds || 0)); const d = Math.floor(v / 86400); v %= 86400;
        const h = Math.floor(v / 3600); v %= 3600; const m = Math.floor(v / 60); const parts = [];
        if (d) parts.push(`${d} д`); if (h || d) parts.push(`${h} ч`); parts.push(`${m} мин`); return parts.join(" ");
    }
    function formatTime(value) {
        if (!value) return "—"; const date = new Date(value); if (Number.isNaN(date.getTime())) return String(value);
        return date.toLocaleString("ru-RU", {day:"2-digit",month:"2-digit",year:"numeric",hour:"2-digit",minute:"2-digit",second:"2-digit"});
    }
    function formatDeploymentResult(value) { return value === "success" ? "Успешно" : value === "failed" ? "Ошибка" : value === "skipped" ? "Пропущено" : (value || "—"); }
    function formatActionResult(value) { return value === "success" ? "Успешно" : value === "failed" ? "Ошибка" : value === "running" ? "Выполняется" : (value || "Неизвестно"); }
    function shortSha(value) { return value ? String(value).slice(0, 12) : "—"; }

    function updateStorage(storage) {
        const container = byId("systemStorage"); if (!container) return; container.replaceChildren();
        for (const item of storage || []) {
            const row = document.createElement("div"); row.className = "storage-row";
            const heading = document.createElement("div"); heading.className = "storage-heading";
            const label = document.createElement("span"); label.textContent = item.path || "—";
            const value = document.createElement("strong"); value.textContent = `${formatBytes(item.used)} / ${formatBytes(item.total)}`;
            heading.append(label, value); const track = document.createElement("div"); track.className = "storage-track";
            const bar = document.createElement("div"); bar.className = "storage-bar";
            const percent = Math.max(0, Math.min(100, Number(item.percent || 0))); if (percent >= 90) bar.classList.add("danger"); else if (percent >= 80) bar.classList.add("warning");
            bar.style.width = `${percent}%`; track.append(bar); row.append(heading, track); container.append(row);
        }
    }

    function updateServices(services) {
        const container = byId("systemServices"); if (!container) return; container.replaceChildren();
        for (const [name, state] of Object.entries(services || {})) {
            const item = document.createElement("div"); item.className = "service-item";
            const dot = document.createElement("span"); dot.className = "service-dot"; dot.classList.add(state === "active" ? "active" : "inactive");
            const nameBox = document.createElement("div"); nameBox.className = "service-name";
            const strong = document.createElement("strong"); strong.textContent = name;
            const status = document.createElement("span"); status.textContent = state || "unknown";
            nameBox.append(strong, status); item.append(dot, nameBox); container.append(item);
        }
    }

    function applyAdminState(auth) {
        adminState = {authenticated:Boolean(auth && auth.authenticated), username:auth && auth.username, must_change:Boolean(auth && auth.must_change), csrf_token:auth && auth.csrf_token};
        byId("adminLoggedOut").hidden = adminState.authenticated; byId("adminLoggedIn").hidden = !adminState.authenticated;
        byId("systemActionPanel").hidden = !adminState.authenticated;
        setText("adminCurrentUser", adminState.username || "—");
        setText("adminPasswordState", adminState.must_change ? "Требуется смена пароля" : "Защищённая сессия активна");
        byId("adminPasswordForm").hidden = !adminState.must_change;
        for (const button of document.querySelectorAll(".privileged-action")) button.disabled = !adminState.authenticated || adminState.must_change;
    }

    function adguardStatusText(service) {
        const status = service.status || {}; const parts = [];
        if (status.version) parts.push(status.version); if (status.state) parts.push(`состояние: ${status.state}`); if (status.mode) parts.push(`режим: ${String(status.mode).toUpperCase()}`);
        if (status.socks_host || status.socks_port) parts.push(`SOCKS: ${status.socks_host || "127.0.0.1"}:${status.socks_port || 1080}`);
        if (status.checked_at) parts.push(`проверено ${formatTime(status.checked_at)}`); return parts.join(" · ") || "Статус ещё не получен";
    }

    function makeActionButton(text, className, action, body = {}, confirmText = null) {
        const button = document.createElement("button"); button.className = `${className} privileged-action`; button.type = "button"; button.textContent = text;
        button.disabled = !adminState.authenticated || adminState.must_change;
        button.addEventListener("click", async () => { if (confirmText && !window.confirm(confirmText)) return; await runAction(action, body, "serviceMessage"); });
        return button;
    }

    function renderManagedServices(services) {
        const container = byId("managedServices"); if (!container) return; container.replaceChildren();
        for (const service of services || []) {
            const card = document.createElement("div"); card.className = "managed-service-card";
            const info = document.createElement("div"); const title = document.createElement("strong"); title.textContent = service.name || service.id || "Сервис";
            const detail = document.createElement("span"); detail.textContent = service.installed ? adguardStatusText(service) : "Не установлен"; info.append(title, detail);
            if (service.status && service.status.detail) { const small = document.createElement("small"); small.textContent = String(service.status.detail).slice(-500); info.append(small); }
            const actions = document.createElement("div"); actions.className = "service-actions";
            if (!service.installed) {
                actions.append(makeActionButton("Установить", "action-button", "service-install-adguard-vpn", {}, "Установить официальный AdGuard VPN CLI на сервер?"));
            } else {
                actions.append(
                    makeActionButton("Статус", "secondary-button", "service-refresh-adguard-vpn"),
                    makeActionButton("Подключить SOCKS", "action-button", "service-connect-adguard-vpn-socks"),
                    makeActionButton("Отключить", "secondary-button", "service-disconnect-adguard-vpn"),
                    makeActionButton("Обновить клиент", "secondary-button", "service-update-adguard-vpn"),
                    makeActionButton("Удалить", "danger-button", "service-remove-adguard-vpn", {confirm:"REMOVE"}, "Удалить AdGuard VPN с сервера?")
                );
            }
            card.append(info, actions); container.append(card);
        }
    }

    function renderActionHistory(actions) {
        const container = byId("systemActionHistory"); if (!container) return; container.replaceChildren();
        if (!adminState.authenticated || !actions || actions.visible !== true) { setText("systemActionQueueCount", "0"); return; }
        const queued = Array.isArray(actions.queued) ? actions.queued : []; const history = Array.isArray(actions.history) ? actions.history : [];
        setText("systemActionQueueCount", String(actions.queued_count || queued.length || 0));
        for (const item of queued) {
            const row = document.createElement("div"); row.className = "action-history-row queued"; const main = document.createElement("div"); main.className = "action-history-main";
            const title = document.createElement("strong"); title.textContent = ACTION_LABELS[item.action] || item.action || "Системное действие";
            const meta = document.createElement("span"); meta.textContent = `${item.actor || "—"} · ${String(item.request_id || "").slice(0,12)}`; main.append(title, meta);
            const badge = document.createElement("span"); badge.className = "action-badge queued"; badge.textContent = "В очереди"; row.append(main,badge); container.append(row);
        }
        for (const item of history) {
            const row = document.createElement("div"); row.className = `action-history-row ${item.result || "unknown"}`; const main = document.createElement("div"); main.className = "action-history-main";
            const title = document.createElement("strong"); title.textContent = ACTION_LABELS[item.action] || item.action || "Системное действие";
            const meta = document.createElement("span"); meta.textContent = `${item.actor || "—"} · ${formatTime(item.finished_at || item.started_at)} · ${String(item.request_id || "").slice(0,12)}`; main.append(title,meta);
            if (item.detail) { const detail = document.createElement("span"); detail.className = "action-history-detail"; detail.textContent = String(item.detail).slice(-800); main.append(detail); }
            const badge = document.createElement("span"); badge.className = `action-badge ${item.result || "unknown"}`; badge.textContent = formatActionResult(item.result); row.append(main,badge); container.append(row);
        }
        if (!queued.length && !history.length) { const empty = document.createElement("div"); empty.className = "action-history-empty"; empty.textContent = "Системных заданий пока нет."; container.append(empty); }
    }

    function updateAdminStatus(data) {
        applyAdminState(data.auth || {}); const automatic = data.automatic_updates || {}; setText("autoUpdatesState", automatic.enabled ? "Включены" : "Выключены");
        const manual = data.manual_update || {}; setText("manualUpdateState", manual.unit_state || "—"); const updateStatus = manual.status || {};
        let result = updateStatus.result || updateStatus.stage || "—"; if (updateStatus.finished_at) result += ` · ${formatTime(updateStatus.finished_at)}`; setText("manualUpdateResult", result);
        renderManagedServices(data.services || []); renderActionHistory(data.actions || {});
    }

    function updateLive(ok) { const dot = byId("systemLiveDot"), text = byId("systemLiveText"); if (!dot || !text) return; dot.classList.remove("ok","error"); dot.classList.add(ok ? "ok" : "error"); text.textContent = ok ? "Данные актуальны" : "Ошибка обновления"; }

    async function refresh() {
        try {
            const [metricsResponse, healthResponse, adminResponse] = await Promise.all([fetch("/api/v1/dashboard/metrics",{cache:"no-store"}),fetch("/api/v1/health",{cache:"no-store"}),fetch("/api/v1/system/admin",{cache:"no-store"})]);
            const metricsPayload = await metricsResponse.json(), healthPayload = await healthResponse.json(), adminPayload = await adminResponse.json();
            if (!metricsResponse.ok || !healthResponse.ok || !adminResponse.ok || !metricsPayload.ok || !healthPayload.ok || !adminPayload.ok) throw new Error("system status request failed");
            const data = metricsPayload.data || {}, system = data.system || {}, cpu = data.cpu || {}, memory = data.memory || {}, uptime = data.uptime || {}, healthData = healthPayload.data || {}, release = healthData.release || {}, deployment = healthData.deployment || {};
            setText("systemHostname",system.hostname||"—"); setText("systemOs",system.os||"—"); setText("systemKernel",system.kernel||"—"); setText("systemArchitecture",system.architecture||"—"); setText("systemUptime",formatUptime(uptime.seconds));
            setText("systemCpu",`${Number(cpu.percent||0).toFixed(1)}% · ${cpu.logical_count||0} потоков`); setText("systemLoad",[cpu.load1??0,cpu.load5??0,cpu.load15??0].join(" / ")); setText("systemMemory",`${Number(memory.percent||0).toFixed(1)}% · ${formatBytes(memory.used)} / ${formatBytes(memory.total)}`);
            setText("systemRelease",release.version?`v${release.version}`:"—"); setText("systemGitHubSync",formatTime(release.synced_at)); setText("deploymentResult",formatDeploymentResult(deployment.result)); setText("deploymentStage",deployment.stage||"—"); setText("deploymentCommit",shortSha(deployment.remote_sha||release.git_sha)); setText("deploymentFinished",formatTime(deployment.deployment_finished_at||release.synced_at)); setText("deploymentHealthchecked",formatTime(deployment.healthchecked_at));
            updateStorage(data.storage); updateServices(data.services); updateAdminStatus(adminPayload.data||{}); updateLive(true);
        } catch (error) { updateLive(false); }
    }

    async function runAction(action, body, messageId) {
        if (!adminState.authenticated || !adminState.csrf_token) { setMessage(messageId,"Сначала войдите как администратор.","error"); return; }
        setMessage(messageId,"Запрос отправляется...");
        try {
            const response = await fetch(`/api/v1/system/actions/${action}`,{method:"POST",headers:{"Content-Type":"application/json","X-CSRF-Token":adminState.csrf_token},body:JSON.stringify(body||{})});
            const payload = await response.json(); if (!response.ok || payload.ok !== true) throw new Error(payload.detail || payload.error || "операция не принята");
            setMessage(messageId,`Операция поставлена в очередь: ${payload.data.request_id}`,"ok"); window.setTimeout(refresh,1200); window.setTimeout(refresh,4000);
        } catch (error) { setMessage(messageId,String(error.message||error),"error"); }
    }

    byId("adminLoginForm")?.addEventListener("submit", async (event) => {
        event.preventDefault(); setMessage("adminMessage","Выполняется вход...");
        try {
            const response = await fetch("/api/v1/auth/login",{method:"POST",headers:{"Content-Type":"application/json"},body:JSON.stringify({username:byId("adminUsername")?.value||"",password:byId("adminPassword")?.value||""})});
            const payload = await response.json(); if (!response.ok || payload.ok !== true) { if (response.status===429) throw new Error("Слишком много попыток входа. Повторите позже"); throw new Error(payload.detail||"неверный логин или пароль"); }
            applyAdminState(payload.data||{}); setMessage("adminMessage",payload.data.must_change?"Вход выполнен. Перед системными действиями смените первичный пароль.":"Вход выполнен.","ok"); if (byId("adminPassword")) byId("adminPassword").value=""; await refresh();
        } catch (error) { setMessage("adminMessage",String(error.message||error),"error"); }
    });

    byId("adminPasswordForm")?.addEventListener("submit", async (event) => {
        event.preventDefault(); setMessage("adminMessage","Меняем пароль...");
        try {
            const response = await fetch("/api/v1/auth/change-password",{method:"POST",headers:{"Content-Type":"application/json","X-CSRF-Token":adminState.csrf_token||""},body:JSON.stringify({current_password:byId("adminCurrentPassword")?.value||"",new_password:byId("adminNewPassword")?.value||""})});
            const payload = await response.json(); if (!response.ok || payload.ok !== true) throw new Error(payload.detail||"пароль не изменён"); applyAdminState(payload.data||{}); setMessage("adminMessage","Пароль изменён; старые сессии отозваны.","ok"); byId("adminCurrentPassword").value=""; byId("adminNewPassword").value=""; await refresh();
        } catch (error) { setMessage("adminMessage",String(error.message||error),"error"); }
    });

    byId("adminLogoutButton")?.addEventListener("click", async () => { try { await fetch("/api/v1/auth/logout",{method:"POST",headers:{"X-CSRF-Token":adminState.csrf_token||""}}); } finally { applyAdminState({}); await refresh(); } });
    byId("rebootButton")?.addEventListener("click", async () => { if (window.confirm("Перезагрузить сервер SRV? Веб-интерфейс временно станет недоступен.")) await runAction("reboot",{confirm:"REBOOT"},"adminMessage"); });
    byId("enableAutoUpdatesButton")?.addEventListener("click",()=>runAction("auto-updates-enable",{},"updateMessage"));
    byId("disableAutoUpdatesButton")?.addEventListener("click",()=>runAction("auto-updates-disable",{},"updateMessage"));
    byId("manualUpdateButton")?.addEventListener("click",async()=>{ if (window.confirm("Запустить обновление индексов и установленных пакетов ОС сейчас?")) await runAction("os-update",{},"updateMessage"); });

    refresh(); window.setInterval(refresh,5000);
})();
