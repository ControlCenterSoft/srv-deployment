(() => {
    "use strict";

    const byId = (id) => document.getElementById(id);
    let csrfToken = "";
    let canWrite = false;
    let refreshTimer = null;

    const state = {
        githubDirty: false,
        osDirty: false,
        backupDirty: false,
        githubConfigRequest: null,
        githubOperationRequest: null,
        osConfigRequest: null,
        osOperationRequest: null,
        backupConfigRequest: null,
        githubUpdateAvailable: false,
    };

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
        githubTimerState: byId("githubTimerState"),
        githubMessage: byId("githubMessage"),
        osForm: byId("osForm"),
        osMode: byId("osMode"),
        osInterval: byId("osInterval"),
        osIntervalField: byId("osIntervalField"),
        osUpdate: byId("osUpdateButton"),
        osTimerState: byId("osTimerState"),
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

    const githubSave = ui.githubForm.querySelector('button[type="submit"]');
    const osSave = ui.osForm.querySelector('button[type="submit"]');
    const backupSave = ui.backupForm.querySelector('button[type="submit"]');

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
        syncModeFields();
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

    function requestId(payload) {
        return payload && payload.data && payload.data.request_id
            ? String(payload.data.request_id)
            : null;
    }

    function actionResult(data, id) {
        if (!id) return null;
        const actions = data.actions || {};
        return (actions.history || []).find((item) => String(item.request_id || "") === id) || null;
    }

    function anyPendingRequest() {
        return Boolean(
            state.githubConfigRequest ||
            state.githubOperationRequest ||
            state.osConfigRequest ||
            state.osOperationRequest ||
            state.backupConfigRequest
        );
    }

    function githubDesiredConfig() {
        return {
            source: ui.githubSource.value.trim(),
            mode: ui.githubMode.value,
            interval_minutes: Number(ui.githubInterval.value || 5),
        };
    }

    function osDesiredConfig() {
        return {
            mode: ui.osMode.value,
            interval_hours: Number(ui.osInterval.value || 24),
        };
    }

    function githubConfigMatches(config, desired) {
        return Boolean(
            config && desired &&
            String(config.source || "") === String(desired.source || "") &&
            String(config.mode || "") === String(desired.mode || "") &&
            Number(config.interval_minutes || 0) === Number(desired.interval_minutes || 0)
        );
    }

    function osConfigMatches(config, desired) {
        return Boolean(
            config && desired &&
            String(config.mode || "") === String(desired.mode || "") &&
            Number(config.interval_hours || 0) === Number(desired.interval_hours || 0)
        );
    }

    function syncModeFields() {
        const githubAutomatic = ui.githubMode.value === "automatic";
        const githubConfigBusy = Boolean(state.githubConfigRequest);
        const githubOperationBusy = Boolean(state.githubOperationRequest);
        const githubUnsaved = state.githubDirty || githubConfigBusy;

        ui.githubIntervalField.hidden = !githubAutomatic;
        ui.githubInterval.disabled = !githubAutomatic || !canWrite || githubConfigBusy;
        ui.githubCheck.hidden = githubAutomatic;
        ui.githubCheck.disabled = !canWrite || githubUnsaved || githubOperationBusy;
        ui.githubUpdate.disabled = !canWrite || !state.githubUpdateAvailable || githubUnsaved || githubOperationBusy;
        githubSave.disabled = !canWrite || githubConfigBusy;
        ui.githubSource.disabled = !canWrite || githubConfigBusy;
        ui.githubMode.disabled = !canWrite || githubConfigBusy;

        const osAutomatic = ui.osMode.value === "automatic";
        const osConfigBusy = Boolean(state.osConfigRequest);
        const osOperationBusy = Boolean(state.osOperationRequest);
        const osUnsaved = state.osDirty || osConfigBusy;

        ui.osIntervalField.hidden = !osAutomatic;
        ui.osInterval.disabled = !osAutomatic || !canWrite || osConfigBusy;
        ui.osUpdate.hidden = osAutomatic;
        ui.osUpdate.disabled = !canWrite || osUnsaved || osOperationBusy;
        osSave.disabled = !canWrite || osConfigBusy;
        ui.osMode.disabled = !canWrite || osConfigBusy;

        const scheduled = ui.backupScheduled.checked;
        const backupBusy = Boolean(state.backupConfigRequest);
        ui.backupTimeField.hidden = !scheduled;
        ui.backupTime.disabled = !scheduled || !canWrite || backupBusy;
        ui.backupScheduled.disabled = !canWrite || backupBusy;
        ui.backupBeforeUpdate.disabled = !canWrite || backupBusy;
        backupSave.disabled = !canWrite || backupBusy;
        ui.backupCreate.disabled = !canWrite;
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

        if (state.githubConfigRequest) {
            const action = actionResult(data, state.githubConfigRequest.id);
            if (action && action.result === "failed") {
                setMessage(ui.githubMessage, action.detail || "Не удалось сохранить настройки GitHub.", true);
                state.githubConfigRequest = null;
            } else if (action && action.result === "success" && githubConfigMatches(config, state.githubConfigRequest.desired)) {
                state.githubConfigRequest = null;
                state.githubDirty = false;
                setMessage(ui.githubMessage, "Настройки GitHub сохранены.");
            }
        }

        if (!state.githubDirty && !state.githubConfigRequest) {
            ui.githubSource.value = config.source || "https://github.com/filosoff31/srv-deployment.git";
            ui.githubMode.value = config.mode === "manual" ? "manual" : "automatic";
            ui.githubInterval.value = Number(config.interval_minutes || 5);
        }

        ui.githubLastCheck.textContent = status.checked_at
            ? `Последняя проверка: ${formatDate(status.checked_at)}`
            : "Проверка ещё не выполнялась";

        state.githubUpdateAvailable = Boolean(status.update_available);
        ui.githubAvailability.textContent = state.githubUpdateAvailable
            ? `Доступен ${status.release_version || "новый релиз"}`
            : "Обновлений нет";
        ui.githubAvailability.classList.toggle("available", state.githubUpdateAvailable);

        const timerActive = Boolean(section.timer_enabled && section.timer_state === "active");
        const configuredAutomatic = config.mode === "automatic";
        if (timerActive) {
            ui.githubTimerState.textContent = `Включено · ${Number(config.interval_minutes || 5)} мин`;
        } else if (configuredAutomatic) {
            ui.githubTimerState.textContent = "Отключено — требуется сохранить настройки";
        } else {
            ui.githubTimerState.textContent = "Отключено";
        }

        if (state.githubOperationRequest) {
            const action = actionResult(data, state.githubOperationRequest.id);
            if (action && action.result === "failed") {
                setMessage(ui.githubMessage, action.detail || "Операция GitHub завершилась ошибкой.", true);
                state.githubOperationRequest = null;
            } else if (action && action.result === "success") {
                setMessage(
                    ui.githubMessage,
                    state.githubOperationRequest.kind === "update"
                        ? "Ручное обновление Control Center завершено."
                        : "Проверка обновлений завершена."
                );
                state.githubOperationRequest = null;
            }
        }
    }

    function renderOs(data) {
        const section = data.os_updates || {};
        const config = section.config || {};
        const status = section.status || {};

        if (state.osConfigRequest) {
            const action = actionResult(data, state.osConfigRequest.id);
            if (action && action.result === "failed") {
                setMessage(ui.osMessage, action.detail || "Не удалось сохранить настройки обновления ОС.", true);
                state.osConfigRequest = null;
            } else if (action && action.result === "success" && osConfigMatches(config, state.osConfigRequest.desired)) {
                state.osConfigRequest = null;
                state.osDirty = false;
                setMessage(ui.osMessage, "Настройки обновления ОС сохранены.");
            }
        }

        if (!state.osDirty && !state.osConfigRequest) {
            ui.osMode.value = config.mode === "automatic" ? "automatic" : "manual";
            ui.osInterval.value = Math.max(1, Math.min(24, Number(config.interval_hours || 24)));
        }

        const timerActive = Boolean(section.timer_enabled && section.timer_state === "active");
        ui.osTimerState.textContent = timerActive
            ? `Автоматически · ${Number(config.interval_hours || 24)} ч`
            : "Ручной режим";
        ui.osTimerState.classList.toggle("active", timerActive);
        ui.osTimerState.classList.toggle("inactive", !timerActive);

        if (status.started_at || status.finished_at) {
            const resultText = status.result === "success"
                ? "Успешно"
                : status.result === "failed"
                    ? "Ошибка"
                    : "Выполняется";
            ui.osState.textContent = `${resultText}${status.finished_at ? ` · ${formatDate(status.finished_at)}` : ""}`;
        } else {
            ui.osState.textContent = "Обновление ещё не запускалось";
        }

        if (state.osOperationRequest) {
            const action = actionResult(data, state.osOperationRequest.id);
            if (action && action.result === "failed") {
                setMessage(ui.osMessage, action.detail || "Обновление ОС завершилось ошибкой.", true);
                state.osOperationRequest = null;
            } else if (action && action.result === "success") {
                setMessage(ui.osMessage, "Обновление ОС запущено.");
                state.osOperationRequest = null;
            }
        }
    }

    function renderBackups(data) {
        const section = data.backup || {};
        const config = section.config || {};

        if (state.backupConfigRequest) {
            const action = actionResult(data, state.backupConfigRequest.id);
            if (action && action.result === "failed") {
                setMessage(ui.backupMessage, action.detail || "Не удалось сохранить настройки резервного копирования.", true);
                state.backupConfigRequest = null;
            } else if (action && action.result === "success") {
                state.backupConfigRequest = null;
                state.backupDirty = false;
                setMessage(ui.backupMessage, "Настройки резервного копирования сохранены.");
            }
        }

        if (!state.backupDirty && !state.backupConfigRequest) {
            ui.backupScheduled.checked = Boolean(config.scheduled);
            ui.backupTime.value = config.daily_time || "03:00";
            ui.backupBeforeUpdate.checked = config.backup_before_update !== false;
        }

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
        renderGithub(data);
        renderOs(data);
        renderBackups(data);
        syncModeFields();
    }

    function scheduleRefresh(delay = 700) {
        if (refreshTimer) window.clearTimeout(refreshTimer);
        refreshTimer = window.setTimeout(async () => {
            refreshTimer = null;
            try {
                await loadConfiguration();
            } finally {
                if (anyPendingRequest()) scheduleRefresh(700);
            }
        }, delay);
    }

    function markGithubDirty() {
        state.githubDirty = true;
        syncModeFields();
    }

    function markOsDirty() {
        state.osDirty = true;
        syncModeFields();
    }

    function markBackupDirty() {
        state.backupDirty = true;
        syncModeFields();
    }

    ui.githubSource.addEventListener("input", markGithubDirty);
    ui.githubMode.addEventListener("change", markGithubDirty);
    ui.githubInterval.addEventListener("input", markGithubDirty);
    ui.osMode.addEventListener("change", markOsDirty);
    ui.osInterval.addEventListener("input", markOsDirty);
    ui.backupScheduled.addEventListener("change", markBackupDirty);
    ui.backupTime.addEventListener("input", markBackupDirty);
    ui.backupBeforeUpdate.addEventListener("change", markBackupDirty);

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
        const desired = githubDesiredConfig();
        setMessage(ui.githubMessage, "Сохранение настроек...");
        try {
            const queued = await post("/api/v1/system/github/config", desired);
            state.githubConfigRequest = {id: requestId(queued), desired};
            state.githubDirty = true;
            syncModeFields();
            scheduleRefresh(350);
        } catch (error) {
            setMessage(ui.githubMessage, error.message, true);
        }
    });

    ui.githubCheck.addEventListener("click", async () => {
        setMessage(ui.githubMessage, "Проверка обновлений...");
        try {
            const queued = await post("/api/v1/system/github/check");
            state.githubOperationRequest = {id: requestId(queued), kind: "check"};
            syncModeFields();
            scheduleRefresh(350);
        } catch (error) {
            setMessage(ui.githubMessage, error.message, true);
        }
    });

    ui.githubUpdate.addEventListener("click", async () => {
        if (!window.confirm("Установить доступное обновление Control Center?")) return;
        setMessage(ui.githubMessage, "Ручное обновление поставлено в очередь...");
        try {
            const queued = await post("/api/v1/system/github/update");
            state.githubOperationRequest = {id: requestId(queued), kind: "update"};
            syncModeFields();
            scheduleRefresh(350);
        } catch (error) {
            setMessage(ui.githubMessage, error.message, true);
        }
    });

    ui.osForm.addEventListener("submit", async (event) => {
        event.preventDefault();
        const desired = osDesiredConfig();
        setMessage(ui.osMessage, "Сохранение настроек...");
        try {
            const queued = await post("/api/v1/system/os/config", desired);
            state.osConfigRequest = {id: requestId(queued), desired};
            state.osDirty = true;
            syncModeFields();
            scheduleRefresh(350);
        } catch (error) {
            setMessage(ui.osMessage, error.message, true);
        }
    });

    ui.osUpdate.addEventListener("click", async () => {
        setMessage(ui.osMessage, "Запуск обновления ОС...");
        try {
            const queued = await post("/api/v1/system/os/update");
            state.osOperationRequest = {id: requestId(queued), kind: "update"};
            syncModeFields();
            scheduleRefresh(350);
        } catch (error) {
            setMessage(ui.osMessage, error.message, true);
        }
    });

    ui.backupForm.addEventListener("submit", async (event) => {
        event.preventDefault();
        setMessage(ui.backupMessage, "Сохранение настроек...");
        try {
            const queued = await post("/api/v1/system/backups/config", {
                scheduled: ui.backupScheduled.checked,
                daily_time: ui.backupTime.value || "03:00",
                backup_before_update: ui.backupBeforeUpdate.checked,
            });
            state.backupConfigRequest = {id: requestId(queued)};
            state.backupDirty = true;
            syncModeFields();
            scheduleRefresh(350);
        } catch (error) {
            setMessage(ui.backupMessage, error.message, true);
        }
    });

    ui.backupCreate.addEventListener("click", async () => {
        setMessage(ui.backupMessage, "Создание резервной копии запущено...");
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
