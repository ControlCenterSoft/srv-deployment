(() => {
    "use strict";

    const byId = (id) => document.getElementById(id);
    let adminState = {
        authenticated: false,
        username: null,
        must_change: false,
        csrf_token: null,
    };

    const ACTION_LABELS = {
        reboot: "Перезагрузка сервера",
        "os-update": "Обновление ОС и пакетов",
        "auto-updates-enable": "Включение автообновлений",
        "auto-updates-disable": "Отключение автообновлений",
        "service-install-adguard-vpn": "Установка AdGuard VPN",
        "service-remove-adguard-vpn": "Удаление AdGuard VPN",
    };

    function setText(id, value) {
        const element = byId(id);
        if (element) element.textContent = value;
    }

    function setMessage(id, value, kind = "") {
        const element = byId(id);
        if (!element) return;
        element.textContent = value || "";
        element.classList.remove("ok", "error");
        if (kind) element.classList.add(kind);
    }

    function formatBytes(value) {
        const amount = Number(value || 0);
        if (!Number.isFinite(amount) || amount <= 0) return "0 Б";
        const units = ["Б", "КБ", "МБ", "ГБ", "ТБ"];
        let number = amount;
        let index = 0;
        while (number >= 1024 && index < units.length - 1) {
            number /= 1024;
            index += 1;
        }
        return `${number.toFixed(index >= 3 ? 1 : 0)} ${units[index]}`;
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

    function formatTime(value) {
        if (!value) return "—";
        const date = new Date(value);
        if (Number.isNaN(date.getTime())) return String(value);
        return date.toLocaleString("ru-RU", {
            day: "2-digit",
            month: "2-digit",
            year: "numeric",
            hour: "2-digit",
            minute: "2-digit",
            second: "2-digit",
        });
    }

    function formatDeploymentResult(value) {
        if (value === "success") return "Успешно";
        if (value === "failed") return "Ошибка";
        if (value === "skipped") return "Пропущено";
        return value || "—";
    }

    function formatActionResult(value) {
        if (value === "success") return "Успешно";
        if (value === "failed") return "Ошибка";
        if (value === "running") return "Выполняется";
        return value || "Неизвестно";
    }

    function shortSha(value) {
        return value ? String(value).slice(0, 12) : "—";
    }

    function updateStorage(storage) {
        const container = byId("systemStorage");
        if (!container) return;
        container.replaceChildren();

        for (const item of storage || []) {
            const row = document.createElement("div");
            row.className = "storage-row";
            const heading = document.createElement("div");
            heading.className = "storage-heading";
            const label = document.createElement("span");
            label.textContent = item.path || "—";
            const value = document.createElement("strong");
            value.textContent = `${formatBytes(item.used)} / ${formatBytes(item.total)}`;
            heading.append(label, value);

            const track = document.createElement("div");
            track.className = "storage-track";
            const bar = document.createElement("div");
            bar.className = "storage-bar";
            const percent = Math.max(0, Math.min(100, Number(item.percent || 0)));
            if (percent >= 90) bar.classList.add("danger");
            else if (percent >= 80) bar.classList.add("warning");
            bar.style.width = `${percent}%`;
            track.append(bar);
            row.append(heading, track);
            container.append(row);
        }
    }

    function updateServices(services) {
        const container = byId("systemServices");
        if (!container) return;
        container.replaceChildren();

        for (const [name, state] of Object.entries(services || {})) {
            const item = document.createElement("div");
            item.className = "service-item";
            const dot = document.createElement("span");
            dot.className = "service-dot";
            dot.classList.add(state === "active" ? "active" : "inactive");

            const nameBox = document.createElement("div");
            nameBox.className = "service-name";
            const strong = document.createElement("strong");
            strong.textContent = name;
            const status = document.createElement("span");
            status.textContent = state || "unknown";
            nameBox.append(strong, status);
            item.append(dot, nameBox);
            container.append(item);
        }
    }

    function applyAdminState(auth) {
        adminState = {
            authenticated: Boolean(auth && auth.authenticated),
            username: auth && auth.username,
            must_change: Boolean(auth && auth.must_change),
            csrf_token: auth && auth.csrf_token,
        };

        const loggedOut = byId("adminLoggedOut");
        const loggedIn = byId("adminLoggedIn");
        if (loggedOut) loggedOut.hidden = adminState.authenticated;
        if (loggedIn) loggedIn.hidden = !adminState.authenticated;

        setText("adminCurrentUser", adminState.username || "—");
        setText(
            "adminPasswordState",
            adminState.must_change ? "Требуется смена пароля" : "Защищённая сессия активна"
        );

        const passwordForm = byId("adminPasswordForm");
        if (passwordForm) passwordForm.hidden = !adminState.must_change;

        for (const button of document.querySelectorAll(".privileged-action")) {
            button.disabled = !adminState.authenticated || adminState.must_change;
        }
    }

    function renderManagedServices(services) {
        const container = byId("managedServices");
        if (!container) return;
        container.replaceChildren();

        for (const service of services || []) {
            const card = document.createElement("div");
            card.className = "managed-service-card";

            const info = document.createElement("div");
            const title = document.createElement("strong");
            title.textContent = service.name || service.id || "Сервис";
            const detail = document.createElement("span");
            detail.textContent = service.installed
                ? `Установлен${service.binary ? ` · ${service.binary}` : ""}`
                : "Не установлен";
            info.append(title, detail);

            const actions = document.createElement("div");
            actions.className = "service-actions";

            if (service.installed) {
                const remove = document.createElement("button");
                remove.className = "danger-button privileged-action";
                remove.type = "button";
                remove.textContent = "Удалить";
                remove.disabled = !adminState.authenticated || adminState.must_change;
                remove.addEventListener("click", async () => {
                    if (!window.confirm("Удалить AdGuard VPN с сервера?")) return;
                    await runAction(
                        "service-remove-adguard-vpn",
                        {confirm: "REMOVE"},
                        "serviceMessage"
                    );
                });
                actions.append(remove);
            } else {
                const install = document.createElement("button");
                install.className = "action-button privileged-action";
                install.type = "button";
                install.textContent = "Установить";
                install.disabled = !adminState.authenticated || adminState.must_change;
                install.addEventListener("click", async () => {
                    if (!window.confirm("Установить официальный AdGuard VPN CLI на сервер?")) return;
                    await runAction("service-install-adguard-vpn", {}, "serviceMessage");
                });
                actions.append(install);
            }

            card.append(info, actions);
            container.append(card);
        }
    }

    function renderActionHistory(actions) {
        const container = byId("systemActionHistory");
        if (!container) return;
        container.replaceChildren();

        const queued = actions && Array.isArray(actions.queued) ? actions.queued : [];
        const history = actions && Array.isArray(actions.history) ? actions.history : [];
        setText("systemActionQueueCount", String(actions && actions.queued_count || queued.length || 0));

        for (const item of queued) {
            const row = document.createElement("div");
            row.className = "action-history-row queued";
            const main = document.createElement("div");
            main.className = "action-history-main";
            const title = document.createElement("strong");
            title.textContent = ACTION_LABELS[item.action] || item.action || "Системное действие";
            const meta = document.createElement("span");
            meta.textContent = `${item.actor || "—"} · ${String(item.request_id || "").slice(0, 12)}`;
            main.append(title, meta);
            const badge = document.createElement("span");
            badge.className = "action-badge queued";
            badge.textContent = "В очереди";
            row.append(main, badge);
            container.append(row);
        }

        for (const item of history) {
            const row = document.createElement("div");
            row.className = `action-history-row ${item.result || "unknown"}`;
            const main = document.createElement("div");
            main.className = "action-history-main";
            const title = document.createElement("strong");
            title.textContent = ACTION_LABELS[item.action] || item.action || "Системное действие";
            const meta = document.createElement("span");
            meta.textContent = `${item.actor || "—"} · ${formatTime(item.finished_at || item.started_at)} · ${String(item.request_id || "").slice(0, 12)}`;
            main.append(title, meta);
            if (item.detail) {
                const detail = document.createElement("span");
                detail.className = "action-history-detail";
                detail.textContent = String(item.detail).slice(0, 420);
                main.append(detail);
            }
            const badge = document.createElement("span");
            badge.className = `action-badge ${item.result || "unknown"}`;
            badge.textContent = formatActionResult(item.result);
            row.append(main, badge);
            container.append(row);
        }

        if (!queued.length && !history.length) {
            const empty = document.createElement("div");
            empty.className = "action-history-empty";
            empty.textContent = "Системных заданий пока нет.";
            container.append(empty);
        }
    }

    function updateAdminStatus(data) {
        const auth = data.auth || {};
        applyAdminState(auth);

        const automatic = data.automatic_updates || {};
        setText("autoUpdatesState", automatic.enabled ? "Включены" : "Выключены");

        const manual = data.manual_update || {};
        setText("manualUpdateState", manual.unit_state || "—");
        const updateStatus = manual.status || {};
        let result = updateStatus.result || updateStatus.stage || "—";
        if (updateStatus.finished_at) result += ` · ${formatTime(updateStatus.finished_at)}`;
        setText("manualUpdateResult", result);

        renderManagedServices(data.services || []);
        renderActionHistory(data.actions || {});
    }

    function updateLive(ok) {
        const liveDot = byId("systemLiveDot");
        const liveText = byId("systemLiveText");
        if (!liveDot || !liveText) return;
        liveDot.classList.remove("ok", "error");
        liveDot.classList.add(ok ? "ok" : "error");
        liveText.textContent = ok ? "Данные актуальны" : "Ошибка обновления";
    }

    async function refresh() {
        try {
            const [metricsResponse, healthResponse, adminResponse] = await Promise.all([
                fetch("/api/v1/dashboard/metrics", {cache: "no-store"}),
                fetch("/api/v1/health", {cache: "no-store"}),
                fetch("/api/v1/system/admin", {cache: "no-store"}),
            ]);

            const metricsPayload = await metricsResponse.json();
            const healthPayload = await healthResponse.json();
            const adminPayload = await adminResponse.json();

            if (
                !metricsResponse.ok || !healthResponse.ok || !adminResponse.ok
                || !metricsPayload.ok || !healthPayload.ok || !adminPayload.ok
            ) throw new Error("system status request failed");

            const data = metricsPayload.data || {};
            const system = data.system || {};
            const cpu = data.cpu || {};
            const memory = data.memory || {};
            const uptime = data.uptime || {};
            const healthData = healthPayload.data || {};
            const release = healthData.release || {};
            const deployment = healthData.deployment || {};

            setText("systemHostname", system.hostname || "—");
            setText("systemOs", system.os || "—");
            setText("systemKernel", system.kernel || "—");
            setText("systemArchitecture", system.architecture || "—");
            setText("systemUptime", formatUptime(uptime.seconds));
            setText("systemCpu", `${Number(cpu.percent || 0).toFixed(1)}% · ${cpu.logical_count || 0} потоков`);
            setText("systemLoad", [cpu.load1 ?? 0, cpu.load5 ?? 0, cpu.load15 ?? 0].join(" / "));
            setText("systemMemory", `${Number(memory.percent || 0).toFixed(1)}% · ${formatBytes(memory.used)} / ${formatBytes(memory.total)}`);
            setText("systemRelease", release.version ? `v${release.version}` : "—");
            setText("systemGitHubSync", formatTime(release.synced_at));

            setText("deploymentResult", formatDeploymentResult(deployment.result));
            setText("deploymentStage", deployment.stage || "—");
            setText("deploymentCommit", shortSha(deployment.remote_sha || release.git_sha));
            setText("deploymentFinished", formatTime(deployment.deployment_finished_at || release.synced_at));
            setText("deploymentHealthchecked", formatTime(deployment.healthchecked_at));

            updateStorage(data.storage);
            updateServices(data.services);
            updateAdminStatus(adminPayload.data || {});
            updateLive(true);
        } catch (error) {
            updateLive(false);
        }
    }

    async function runAction(action, body, messageId) {
        if (!adminState.authenticated || !adminState.csrf_token) {
            setMessage(messageId, "Сначала войдите как администратор.", "error");
            return;
        }

        setMessage(messageId, "Запрос отправляется...");
        try {
            const response = await fetch(`/api/v1/system/actions/${action}`, {
                method: "POST",
                headers: {
                    "Content-Type": "application/json",
                    "X-CSRF-Token": adminState.csrf_token,
                },
                body: JSON.stringify(body || {}),
            });
            const payload = await response.json();
            if (!response.ok || payload.ok !== true) {
                throw new Error(payload.detail || payload.error || "операция не принята");
            }
            setMessage(
                messageId,
                `Операция поставлена в очередь: ${payload.data.request_id}`,
                "ok"
            );
            window.setTimeout(refresh, 1200);
        } catch (error) {
            setMessage(messageId, String(error.message || error), "error");
        }
    }

    byId("adminLoginForm")?.addEventListener("submit", async (event) => {
        event.preventDefault();
        setMessage("adminMessage", "Выполняется вход...");
        try {
            const response = await fetch("/api/v1/auth/login", {
                method: "POST",
                headers: {"Content-Type": "application/json"},
                body: JSON.stringify({
                    username: byId("adminUsername")?.value || "",
                    password: byId("adminPassword")?.value || "",
                }),
            });
            const payload = await response.json();
            if (!response.ok || payload.ok !== true) {
                throw new Error(payload.detail || "неверный логин или пароль");
            }
            applyAdminState(payload.data || {});
            setMessage(
                "adminMessage",
                payload.data.must_change
                    ? "Вход выполнен. Перед системными действиями смените первичный пароль."
                    : "Вход выполнен.",
                "ok"
            );
            if (byId("adminPassword")) byId("adminPassword").value = "";
            await refresh();
        } catch (error) {
            setMessage(
                "adminMessage",
                `${error.message || error}. Для первичного входа пароль хранится на SRV: sudo cat /var/lib/srv-control/admin-bootstrap.txt`,
                "error"
            );
        }
    });

    byId("adminPasswordForm")?.addEventListener("submit", async (event) => {
        event.preventDefault();
        setMessage("adminMessage", "Меняем пароль...");
        try {
            const response = await fetch("/api/v1/auth/change-password", {
                method: "POST",
                headers: {
                    "Content-Type": "application/json",
                    "X-CSRF-Token": adminState.csrf_token || "",
                },
                body: JSON.stringify({
                    current_password: byId("adminCurrentPassword")?.value || "",
                    new_password: byId("adminNewPassword")?.value || "",
                }),
            });
            const payload = await response.json();
            if (!response.ok || payload.ok !== true) {
                throw new Error(payload.detail || "пароль не изменён");
            }
            applyAdminState(payload.data || {});
            setMessage("adminMessage", "Пароль администратора изменён.", "ok");
            byId("adminCurrentPassword").value = "";
            byId("adminNewPassword").value = "";
            await refresh();
        } catch (error) {
            setMessage("adminMessage", String(error.message || error), "error");
        }
    });

    byId("adminLogoutButton")?.addEventListener("click", async () => {
        try {
            await fetch("/api/v1/auth/logout", {
                method: "POST",
                headers: {"X-CSRF-Token": adminState.csrf_token || ""},
            });
        } finally {
            applyAdminState({});
            await refresh();
        }
    });

    byId("rebootButton")?.addEventListener("click", async () => {
        if (!window.confirm("Перезагрузить сервер SRV? Веб-интерфейс временно станет недоступен.")) return;
        await runAction("reboot", {confirm: "REBOOT"}, "adminMessage");
    });

    byId("enableAutoUpdatesButton")?.addEventListener("click", () =>
        runAction("auto-updates-enable", {}, "updateMessage")
    );
    byId("disableAutoUpdatesButton")?.addEventListener("click", () =>
        runAction("auto-updates-disable", {}, "updateMessage")
    );
    byId("manualUpdateButton")?.addEventListener("click", async () => {
        if (!window.confirm("Запустить обновление индексов и установленных пакетов ОС сейчас?")) return;
        await runAction("os-update", {}, "updateMessage");
    });

    refresh();
    window.setInterval(refresh, 5000);
})();
