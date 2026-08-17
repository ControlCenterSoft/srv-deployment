(() => {
    "use strict";

    const byId = (id) => document.getElementById(id);
    const liveDot = byId("networkLiveDot");
    const liveText = byId("networkLiveText");
    const planForm = byId("networkPlanForm");
    let interfaceOptionsInitialized = false;
    let lastOverviewOk = false;
    let lastDiagnosticsOk = false;
    let lastOverviewError = "";
    let lastDiagnosticsError = "";

    function setText(id, value) {
        const element = byId(id);
        if (element) element.textContent = value;
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

    function roleLabel(role) {
        const labels = {
            "default-route": "маршрут по умолчанию",
            "lan-candidate": "LAN-кандидат",
            "loopback": "loopback",
            "unclassified": "не классифицирован",
        };
        return labels[role] || role || "—";
    }

    function errorMessage(error) {
        if (!error) return "неизвестная ошибка";
        return String(error.message || error);
    }

    async function requestJson(path, options = {}) {
        const response = await fetch(path, {
            cache: "no-store",
            credentials: "same-origin",
            headers: {"Accept": "application/json", ...(options.headers || {})},
            ...options,
        });

        let payload = null;
        const contentType = response.headers.get("content-type") || "";
        try {
            if (contentType.includes("application/json")) {
                payload = await response.json();
            } else {
                const text = await response.text();
                payload = {ok: false, error: text.trim().slice(0, 240)};
            }
        } catch (_) {
            payload = {ok: false, error: "некорректный ответ сервера"};
        }

        if (response.status === 401) {
            window.top.location.replace("/login");
            throw new Error("сеанс завершён — требуется повторный вход");
        }

        if (!response.ok || !payload || payload.ok !== true) {
            const detail = payload && (payload.detail || payload.error);
            throw new Error(`HTTP ${response.status}${detail ? `: ${detail}` : ""}`);
        }

        return payload.data || {};
    }

    function updateLive() {
        if (!liveDot || !liveText) return;
        liveDot.classList.remove("ok", "error");

        if (lastOverviewOk && lastDiagnosticsOk) {
            liveDot.classList.add("ok");
            liveText.textContent = "Данные актуальны";
            liveText.title = "Обзор сети и диагностика загружены успешно";
            return;
        }

        if (lastOverviewOk) {
            liveDot.classList.add("ok");
            liveText.textContent = "Сеть загружена, диагностика недоступна";
            liveText.title = lastDiagnosticsError || "Диагностика недоступна";
            return;
        }

        liveDot.classList.add("error");
        const message = lastOverviewError || "данные сети недоступны";
        liveText.textContent = message.includes("HTTP 403")
            ? "Нет прав на модуль «Сеть»"
            : "Ошибка получения данных";
        liveText.title = [lastOverviewError, lastDiagnosticsError].filter(Boolean).join(" | ");
    }

    function renderInterfaces(interfaces) {
        const container = byId("networkInterfaces");
        if (!container) return;
        container.replaceChildren();

        const values = Array.isArray(interfaces) ? interfaces : [];
        if (!values.length) {
            const empty = document.createElement("div");
            empty.className = "plan-message warning";
            empty.textContent = "Сетевые интерфейсы не обнаружены.";
            container.append(empty);
            return;
        }

        for (const item of values) {
            const box = document.createElement("div");
            box.className = "service-item";
            const dot = document.createElement("span");
            dot.className = "service-dot";
            dot.classList.add(item.is_up ? "active" : "inactive");
            const content = document.createElement("div");
            content.className = "service-name";
            const title = document.createElement("strong");
            title.textContent = item.name || "—";
            const lines = [`${roleLabel(item.role)} · ${item.is_up ? "UP" : "DOWN"}`];
            if (Array.isArray(item.ipv4) && item.ipv4.length) lines.push(`IPv4: ${item.ipv4.join(", ")}`);
            if (item.mac) lines.push(`MAC: ${item.mac}`);
            if (item.speed_mbps) lines.push(`Скорость: ${item.speed_mbps} Мбит/с`);
            if (item.mtu) lines.push(`MTU: ${item.mtu}`);
            const traffic = item.traffic || {};
            lines.push(`RX ${formatBytes(traffic.bytes_recv)} · TX ${formatBytes(traffic.bytes_sent)}`);
            const detail = document.createElement("span");
            detail.textContent = lines.join(" · ");
            content.append(title, detail);
            box.append(dot, content);
            container.append(box);
        }
    }

    function diagnosticsLabel(name) {
        const labels = {route: "Маршрут", dns: "DNS", https: "GitHub HTTPS"};
        return labels[name] || name;
    }

    function renderDiagnostics(data) {
        const summary = data.summary || {};
        setText("diagnosticsSummary", `${summary.passed || 0} / ${summary.total || 0} успешно`);

        let checkedAt = "—";
        if (data.checked_at) {
            const date = new Date(data.checked_at);
            if (!Number.isNaN(date.getTime())) checkedAt = date.toLocaleString("ru-RU");
        }
        setText("diagnosticsCheckedAt", checkedAt);

        const container = byId("diagnosticsGrid");
        if (!container) return;
        container.replaceChildren();

        for (const [name, check] of Object.entries(data.checks || {})) {
            const box = document.createElement("div");
            box.className = "service-item";
            const dot = document.createElement("span");
            dot.className = "service-dot";
            dot.classList.add(check.ok ? "active" : "inactive");
            const content = document.createElement("div");
            content.className = "service-name";
            const title = document.createElement("strong");
            title.textContent = diagnosticsLabel(name);
            const detail = document.createElement("span");
            const parts = [check.ok ? "OK" : "Ошибка"];
            if (check.latency_ms !== undefined && check.latency_ms !== null) parts.push(`${check.latency_ms} мс`);
            if (check.detail) parts.push(check.detail);
            else if (check.error) parts.push(check.error);
            detail.textContent = parts.join(" · ");
            content.append(title, detail);
            box.append(dot, content);
            container.append(box);
        }
    }

    function setSelectOptions(select, interfaces, preferred) {
        if (!select) return;
        select.replaceChildren();
        for (const item of interfaces || []) {
            if (!item || item.name === "lo") continue;
            const option = document.createElement("option");
            option.value = item.name;
            option.textContent = `${item.name} · ${roleLabel(item.role)}`;
            if (item.name === preferred) option.selected = true;
            select.append(option);
        }
    }

    function initializePlanner(data) {
        if (interfaceOptionsInitialized) return;
        const interfaces = Array.isArray(data.interfaces) ? data.interfaces : [];
        const wan = data.wan_candidate || "";
        const lan = (Array.isArray(data.lan_candidates) ? data.lan_candidates : [])[0]
            || interfaces.find((item) => item.name !== "lo" && item.name !== wan)?.name
            || "";
        setSelectOptions(byId("planWanInterface"), interfaces, wan);
        setSelectOptions(byId("planLanInterface"), interfaces, lan);
        const lanItem = interfaces.find((item) => item.name === lan);
        const ipv4 = lanItem && Array.isArray(lanItem.ipv4_details) ? lanItem.ipv4_details[0] : null;
        if (ipv4 && ipv4.address && ipv4.prefix !== null && ipv4.prefix !== undefined) {
            byId("planLanAddress").value = `${ipv4.address}/${ipv4.prefix}`;
        }
        interfaceOptionsInitialized = true;
    }

    function renderOverview(data) {
        const route = data.default_route || {};
        setText("networkWan", data.wan_candidate || "не определён");
        setText("networkGateway", route.gateway || "—");
        setText("networkMetric", route.metric === undefined || route.metric === null ? "—" : String(route.metric));
        setText("networkLan", (data.lan_candidates || []).join(", ") || "не определены");
        setText("networkDns", (data.dns_servers || []).join(", ") || "не определены");
        setText("networkVpn", (data.vpn_interfaces || []).join(", ") || "нет");
        renderInterfaces(data.interfaces);
        initializePlanner(data);
    }

    async function refreshOverview() {
        try {
            const data = await requestJson("/api/v1/network/overview");
            renderOverview(data);
            lastOverviewOk = true;
            lastOverviewError = "";
        } catch (error) {
            lastOverviewOk = false;
            lastOverviewError = errorMessage(error);
        }
        updateLive();
    }

    async function refreshDiagnostics() {
        try {
            const data = await requestJson("/api/v1/network/diagnostics");
            renderDiagnostics(data);
            lastDiagnosticsOk = true;
            lastDiagnosticsError = "";
        } catch (error) {
            lastDiagnosticsOk = false;
            lastDiagnosticsError = errorMessage(error);
            setText("diagnosticsSummary", "Недоступно");
        }
        updateLive();
    }

    async function refreshAll() {
        await Promise.allSettled([refreshOverview(), refreshDiagnostics()]);
        updateLive();
    }

    function formPayload() {
        const dnsValues = byId("planDnsServers").value
            .split(",")
            .map((value) => value.trim())
            .filter(Boolean);
        return {
            wan_mode: byId("planWanMode").value,
            wan_interface: byId("planWanInterface").value,
            lan_interface: byId("planLanInterface").value,
            lan_address: byId("planLanAddress").value.trim(),
            dhcp_enabled: byId("planDhcpEnabled").value === "true",
            dhcp_start: byId("planDhcpStart").value.trim(),
            dhcp_end: byId("planDhcpEnd").value.trim(),
            dns_mode: byId("planDnsMode").value,
            dns_servers: dnsValues,
        };
    }

    function appendMessages(container, values, className) {
        for (const value of values || []) {
            const item = document.createElement("div");
            item.className = `plan-message ${className}`;
            item.textContent = value;
            container.append(item);
        }
    }

    function renderPlan(payload) {
        const panel = byId("networkPlanResultPanel");
        const status = byId("networkPlanStatus");
        const messages = byId("networkPlanMessages");
        const steps = byId("networkPlanSteps");
        const plan = payload.plan || {};
        panel.hidden = false;
        status.className = "plan-status";
        if (plan.valid) {
            status.classList.add("ok");
            status.textContent = "Параметры прошли проверку. Сетевая конфигурация не изменялась.";
        } else {
            status.classList.add("error");
            status.textContent = "Параметры не прошли проверку. Сетевая конфигурация не изменялась.";
        }
        messages.replaceChildren();
        appendMessages(messages, plan.errors, "error");
        appendMessages(messages, plan.warnings, "warning");
        if (!(plan.errors || []).length && !(plan.warnings || []).length) {
            const item = document.createElement("div");
            item.className = "plan-message ok";
            item.textContent = "Ошибок и предупреждений нет.";
            messages.append(item);
        }
        steps.replaceChildren();
        for (const step of plan.steps || []) {
            const item = document.createElement("li");
            item.textContent = step.description || step.action || "—";
            steps.append(item);
        }
        panel.scrollIntoView({behavior: "smooth", block: "start"});
    }

    async function submitPlan(event) {
        event.preventDefault();
        const button = planForm.querySelector("button[type='submit']");
        if (button) {
            button.disabled = true;
            button.textContent = "Проверка...";
        }
        try {
            const data = await requestJson("/api/v1/network/plan", {
                method: "POST",
                headers: {"Content-Type": "application/json"},
                body: JSON.stringify(formPayload()),
            });
            renderPlan(data);
        } catch (error) {
            const panel = byId("networkPlanResultPanel");
            const status = byId("networkPlanStatus");
            const messages = byId("networkPlanMessages");
            panel.hidden = false;
            status.className = "plan-status error";
            status.textContent = "Ошибка проверки конфигурации.";
            messages.replaceChildren();
            const item = document.createElement("div");
            item.className = "plan-message error";
            item.textContent = errorMessage(error);
            messages.append(item);
        } finally {
            if (button) {
                button.disabled = false;
                button.textContent = "Проверить параметры";
            }
        }
    }

    if (planForm) planForm.addEventListener("submit", submitPlan);
    refreshAll();
    window.setInterval(refreshOverview, 5000);
    window.setInterval(refreshDiagnostics, 30000);
})();
