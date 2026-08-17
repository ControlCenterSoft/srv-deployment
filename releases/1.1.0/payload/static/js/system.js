(() => {
    "use strict";

    const byId = (id) => document.getElementById(id);
    let csrfToken = "";
    let canWrite = false;
    let refreshTimer = null;

    const ui = {
        liveDot: byId("systemLiveDot"),
        liveText: byId("systemLiveText"),
        reboot: byId("rebootButton"),
        hostname: byId("systemHostname"),
        os: byId("systemOs"),
        kernel: byId("systemKernel"),
        architecture: byId("systemArchitecture"),
        uptime: byId("systemUptime"),
        cpu: byId("systemCpu"),
        load: byId("systemLoad"),
        memory: byId("systemMemory"),
        release: byId("systemRelease"),
        githubSync: byId("systemGitHubSync"),
        storage: byId("systemStorage"),
        githubForm: byId("githubForm"),
        githubSource: byId("githubSource"),
        githubMode: byId("githubMode"),
        githubInterval: byId("githubInterval"),
        githubIntervalField: byId("githubIntervalField"),
        githubCheck: byId("githubCheckButton"),
        githubUpdate: byId("githubUpdateButton"),
        githubAvailability: byId("githubAvailability"),
        githubLastCheck: byId("githubLastCheck"),
        githubMessage: byId("githubMessage"),
        osForm: byId("osForm"),
        osMode: byId("osMode"),
        osInterval: byId("osInterval"),
        osIntervalField: byId("osIntervalField"),
        osUpdate: byId("osUpdateButton"),
        osState: byId("osUpdateState"),
        osMessage: byId("osMessage"),
        backupForm: byId("backupForm"),
        backupScheduled: byId("backupScheduled"),
        backupTime: byId("backupTime"),
        backupTimeField: byId("backupTimeField"),
        backupBeforeUpdate: byId("backupBeforeUpdate"),
        backupCreate: byId("backupCreateButton"),
        backupRows: byId("backupRows"),
        backupMessage: byId("backupMessage"),
    };

    function formatBytes(value) {
        const bytes = Number(value || 0);
        if (!Number.isFinite(bytes) || bytes <= 0) return "0 Б";
        const units = ["Б", "КБ", "МБ", "ГБ", "ТБ"];
        let size = bytes;
        let index = 0;
        while (size >= 1024 && index < units.length - 1) {
            size /= 1024;
            index += 1;
        }
        return `${size.toLocaleString("ru-RU", {maximumFractionDigits: index < 2 ? 0 : 1})} ${units[index]}`;
    }

    function formatDate(value) {
        if (!value) return "—";
        const date = new Date(value);
        return Number.isNaN(date.getTime()) ? String(value) : date.toLocaleString("ru-RU");
    }

    function formatUptime(seconds) {
        let value = Math.max(0, Number(seconds || 0));
        const days = Math.floor(value / 86400);
        value %= 86400;
        const hours = Math.floor(value / 3600);
        value %= 3600;
        const minutes = Math.floor(value / 60);
        const parts = [];
        if (days) parts.push(`${days} д`);
        if (hours || days) parts.push(`${hours} ч`);
        parts.push(`${minutes} мин`);
        return parts.join(" ");
    }

    function setMessage(element, value, error = false) {
        element.textContent = value || "";
        element.classList.toggle("error", error);
    }

    async function jsonFetch(url, options = {}) {
        const response = await fetch(url, {cache: "no-store", credentials: "same-origin", ...options});
        let payload = null;
        try {
            payload = await response.json();
        } catch (_) {
            payload = null;
        }
        if (response.status === 401) {
            window.top.location.replace("/login");
            throw new Error("authentication required");
        }
        if (!response.ok) {
            const detail = payload && (payload.detail || payload.error);
            throw new Error(detail || `HTTP ${response.status}`);
        }
        return payload;
    }

    async function loadAuth() {
        const payload = await jsonFetch("/api/v1/auth/status");
        if (!payload.data || !payload.data.authenticated) {
            window.top.location.replace("/login");
            return;
        }
        csrfToken = payload.data.csrf_token || "";
        canWrite = Boolean(payload.data.identity && payload.data.identity.is_admin);
        ui.reboot.hidden = !canWrite;
        for (const control of document.querySelectorAll(".admin-control")) {
            control.disabled = !canWrite;
        }
    }

    async function post(url, body = null) {
        const headers = {"X-CSRF-Token": csrfToken};
        const options = {method: "POST", headers};
        if (body !== null) {
            headers["Content-Type"] = "application/json";
            options.body = JSON.stringify(body);
        }
        return jsonFetch(url, options);
    }

    async function deleteRequest(url) {
        return jsonFetch(url, {
            method: "DELETE",
            headers: {"X-CSRF-Token": csrfToken},
        });
    }

    function syncModeFields() {
        const githubAutomatic = ui.githubMode.value === "automatic";
        ui.githubIntervalField.hidden = !githubAutomatic;
        ui.githubInterval.disabled = !githubAutomatic || !canWrite;
        ui.githubCheck.hidden = githubAutomatic;

        const osAutomatic = ui.osMode.value === "automatic";
        ui.osIntervalField.hidden = !osAutomatic;
        ui.osInterval.disabled = !osAutomatic || !canWrite;
        ui.osUpdate.hidden = osAutomatic;

        const scheduled = ui.backupScheduled.checked;
        ui.backupTimeField.hidden = !scheduled;
        ui.backupTime.disabled = !scheduled || !canWrite;
    }

    function renderStorage(items) {
        ui.storage.textContent = "";
        for (const item of items || []) {
            const row = document.createElement("div");
            row.className = "storage-item";
            const path = document.createElement("strong");
            path.textContent = item.path || "—";
            const bar = document.createElement("div");
            bar.className = "storage-bar";
            const fill = document.createElement("span");
            fill.style.width = `${Math.max(0, Math.min(100, Number(item.percent || 0)))}%`;
            bar.appendChild(fill);
            const text = document.createElement("span");
            text.textContent = `${formatBytes(item.used)} / ${formatBytes(item.total)} (${Number(item.percent || 0).toLocaleString("ru-RU")}%)`;
            row.append(path, bar, text);
            ui.storage.appendChild(row);
        }
    }

    async function loadMetrics() {
        const [metricsPayload, healthPayload] = await Promise.all([
            jsonFetch("/api/v1/dashboard/metrics"),
            jsonFetch("/api/v1/health"),
        ]);
        const data = metricsPayload.data || {};
        const system = data.system || {};
        const cpu = data.cpu || {};
        const memory = data.memory || {};
        const release = (healthPayload.data && healthPayload.data.release) || {};

        ui.hostname.textContent = system.hostname || "—";
        ui.os.textContent = system.os || "—";
        ui.kernel.textContent = system.kernel || "—";
        ui.architecture.textContent = system.architecture || "—";
        ui.uptime.textContent = formatUptime(data.uptime && data.uptime.seconds);
        ui.cpu.textContent = `${Number(cpu.percent || 0).toLocaleString("ru-RU")}% / ${cpu.logical_count || 0} потоков`;
        ui.load.textContent = `${cpu.load1 ?? "—"} / ${cpu.load5 ?? "—"} / ${cpu.load15 ?? "—"}`;
        ui.memory.textContent = `${formatBytes(memory.used)} / ${formatBytes(memory.total)} (${Number(memory.percent || 0).toLocaleString("ru-RU")}%)`;
        ui.release.textContent = release.version || "—";
        ui.githubSync.textContent = formatDate(release.synced_at);
        renderStorage(data.storage || []);

        ui.liveText.textContent = "Данные актуальны";
        ui.liveDot.classList.remove("error");
        ui.liveDot.classList.add("ok");
    }

    function renderGithub(data) {
        const section = data.github_updates || {};
        const config = section.config || {};
        const status = section.status || {};
        ui.githubSource.value = config.source || "https://github.com/filosoff31/srv-deployment.git";
        ui.githubMode.value = config.mode === "manual" ? "manual" : "automatic";
        ui.githubInterval.value = Number(config.interval_minutes || 5);
        ui.githubLastCheck.textContent = status.checked_at ? `Последняя проверка: ${formatDate(status.checked_at)}` : "Проверка ещё не выполнялась";
        const available = Boolean(status.update_available);
        ui.githubAvailability.textContent = available
            ? `Доступен ${status.release_version || "новый релиз"}`
            : "Обновлений нет";
        ui.githubAvailability.classList.toggle("available", available);
        ui.githubUpdate.disabled = !canWrite || !available;
    }

    function renderOs(data) {
        const section = data.os_updates || {};
        const config = section.config || {};
        const status = section.status || {};
        ui.osMode.value = config.mode === "automatic" ? "automatic" : "manual";
        ui.osInterval.value = Math.max(1, Math.min(24, Number(config.interval_hours || 24)));
        if (status.started_at || status.finished_at) {
            const state = status.result === "success" ? "Успешно" : status.result === "failed" ? "Ошибка" : "Выполняется";
            ui.osState.textContent = `${state}${status.finished_at ? ` · ${formatDate(status.finished_at)}` : ""}`;
        } else {
            ui.osState.textContent = "Обновление ещё не запускалось";
        }
    }

    function renderBackups(data) {
        const section = data.backup || {};
        const config = section.config || {};
        ui.backupScheduled.checked = Boolean(config.scheduled);
        ui.backupTime.value = config.daily_time || "03:00";
        ui.backupBeforeUpdate.checked = config.backup_before_update !== false;
        ui.backupRows.textContent = "";
        for (const item of section.items || []) {
            const tr = document.createElement("tr");
            for (const value of [formatDate(item.created_at), item.release || "—", formatBytes(item.size), item.actor || "—"]) {
                const td = document.createElement("td");
                td.textContent = value;
                tr.appendChild(td);
            }
            const actionsCell = document.createElement("td");
            const actions = document.createElement("div");
            actions.className = "backup-actions";

            const download = document.createElement("a");
            download.href = item.download_url;
            download.textContent = "Скачать";
            actions.appendChild(download);

            if (canWrite) {
                const restore = document.createElement("button");
                restore.type = "button";
                restore.textContent = "Восстановить";
                restore.addEventListener("click", async () => {
                    if (!window.confirm(`Восстановить резервную копию ${item.id}?`)) return;
                    try {
                        await post(`/api/v1/system/backups/${encodeURIComponent(item.id)}/restore`);
                        scheduleRefresh();
                    } catch (error) {
                        setMessage(ui.backupMessage, error.message, true);
                    }
                });
                actions.appendChild(restore);

                const remove = document.createElement("button");
                remove.type = "button";
                remove.className = "danger";
                remove.textContent = "Удалить";
                remove.addEventListener("click", async () => {
                    if (!window.confirm(`Удалить резервную копию ${item.id}?`)) return;
                    try {
                        await deleteRequest(`/api/v1/system/backups/${encodeURIComponent(item.id)}`);
                        scheduleRefresh();
                    } catch (error) {
                        setMessage(ui.backupMessage, error.message, true);
                    }
                });
                actions.appendChild(remove);
            }
            actionsCell.appendChild(actions);
            tr.appendChild(actionsCell);
            ui.backupRows.appendChild(tr);
        }
    }

    async function loadConfiguration() {
        const payload = await jsonFetch("/api/v1/system/configuration");
        const data = payload.data || {};
        canWrite = Boolean(data.can_write);
        ui.reboot.hidden = !canWrite;
        for (const control of document.querySelectorAll(".admin-control")) {
            if (control !== ui.githubUpdate) control.disabled = !canWrite;
        }
        renderGithub(data);
        renderOs(data);
        renderBackups(data);
        syncModeFields();
    }

    function scheduleRefresh() {
        if (refreshTimer) window.clearTimeout(refreshTimer);
        refreshTimer = window.setTimeout(async () => {
            try {
                await loadConfiguration();
            } finally {
                refreshTimer = null;
            }
        }, 1500);
    }

    ui.githubMode.addEventListener("change", syncModeFields);
    ui.osMode.addEventListener("change", syncModeFields);
    ui.backupScheduled.addEventListener("change", syncModeFields);

    ui.reboot.addEventListener("click", async () => {
        if (!window.confirm("Перезагрузить сервер SRV?")) return;
        try {
            await post("/api/v1/system/actions/reboot", {confirm: "REBOOT"});
        } catch (error) {
            ui.liveText.textContent = error.message;
            ui.liveDot.classList.add("error");
        }
    });

    ui.githubForm.addEventListener("submit", async (event) => {
        event.preventDefault();
        setMessage(ui.githubMessage, "");
        try {
            await post("/api/v1/system/github/config", {
                source: ui.githubSource.value.trim(),
                mode: ui.githubMode.value,
                interval_minutes: Number(ui.githubInterval.value || 5),
            });
            scheduleRefresh();
        } catch (error) {
            setMessage(ui.githubMessage, error.message, true);
        }
    });

    ui.githubCheck.addEventListener("click", async () => {
        setMessage(ui.githubMessage, "");
        try {
            await post("/api/v1/system/github/check");
            scheduleRefresh();
        } catch (error) {
            setMessage(ui.githubMessage, error.message, true);
        }
    });

    ui.githubUpdate.addEventListener("click", async () => {
        if (!window.confirm("Установить доступное обновление Control Center?")) return;
        setMessage(ui.githubMessage, "");
        try {
            await post("/api/v1/system/github/update");
            scheduleRefresh();
        } catch (error) {
            setMessage(ui.githubMessage, error.message, true);
        }
    });

    ui.osForm.addEventListener("submit", async (event) => {
        event.preventDefault();
        setMessage(ui.osMessage, "");
        try {
            await post("/api/v1/system/os/config", {
                mode: ui.osMode.value,
                interval_hours: Number(ui.osInterval.value || 24),
            });
            scheduleRefresh();
        } catch (error) {
            setMessage(ui.osMessage, error.message, true);
        }
    });

    ui.osUpdate.addEventListener("click", async () => {
        setMessage(ui.osMessage, "");
        try {
            await post("/api/v1/system/os/update");
            scheduleRefresh();
        } catch (error) {
            setMessage(ui.osMessage, error.message, true);
        }
    });

    ui.backupForm.addEventListener("submit", async (event) => {
        event.preventDefault();
        setMessage(ui.backupMessage, "");
        try {
            await post("/api/v1/system/backups/config", {
                scheduled: ui.backupScheduled.checked,
                daily_time: ui.backupTime.value || "03:00",
                backup_before_update: ui.backupBeforeUpdate.checked,
            });
            scheduleRefresh();
        } catch (error) {
            setMessage(ui.backupMessage, error.message, true);
        }
    });

    ui.backupCreate.addEventListener("click", async () => {
        setMessage(ui.backupMessage, "");
        try {
            await post("/api/v1/system/backups");
            scheduleRefresh();
        } catch (error) {
            setMessage(ui.backupMessage, error.message, true);
        }
    });

    async function refreshAll() {
        try {
            await loadAuth();
            await Promise.all([loadMetrics(), loadConfiguration()]);
        } catch (_) {
            ui.liveText.textContent = "Ошибка получения данных";
            ui.liveDot.classList.remove("ok");
            ui.liveDot.classList.add("error");
        }
    }

    refreshAll();
    window.setInterval(() => {
        loadMetrics().catch(() => {
            ui.liveText.textContent = "Ошибка получения данных";
            ui.liveDot.classList.remove("ok");
            ui.liveDot.classList.add("error");
        });
        loadConfiguration().catch(() => {});
    }, 10000);
})();
