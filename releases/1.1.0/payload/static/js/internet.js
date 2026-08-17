(() => {
    "use strict";

    const byId = (id) => document.getElementById(id);
    const liveDot = byId("networkLiveDot");
    const liveText = byId("networkLiveText");
    const planForm = byId("networkPlanForm");

    let interfaceOptionsInitialized = false;


    function setText(id, value) {
        const element = byId(id);

        if (element) {
            element.textContent = value;
        }
    }


    function formatBytes(value) {
        const amount = Number(value || 0);

        if (!Number.isFinite(amount) || amount <= 0) {
            return "0 Б";
        }

        const units = [
            "Б",
            "КБ",
            "МБ",
            "ГБ",
            "ТБ",
        ];

        let number = amount;
        let index = 0;

        while (
            number >= 1024
            &&
            index < units.length - 1
        ) {
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


    function updateLive(ok) {
        if (!liveDot || !liveText) {
            return;
        }

        liveDot.classList.remove(
            "ok",
            "error"
        );

        if (ok) {
            liveDot.classList.add("ok");
            liveText.textContent = "Данные актуальны";
        } else {
            liveDot.classList.add("error");
            liveText.textContent = "Ошибка обновления";
        }
    }


    function renderInterfaces(interfaces) {
        const container = byId("networkInterfaces");

        if (!container) {
            return;
        }

        container.replaceChildren();

        for (const item of interfaces || []) {
            const box = document.createElement("div");
            box.className = "service-item";

            const dot = document.createElement("span");
            dot.className = "service-dot";
            dot.classList.add(
                item.is_up
                    ? "active"
                    : "inactive"
            );

            const content = document.createElement("div");
            content.className = "service-name";

            const title = document.createElement("strong");
            title.textContent = item.name || "—";

            const lines = [];

            lines.push(
                `${roleLabel(item.role)} · ${item.is_up ? "UP" : "DOWN"}`
            );

            if (item.ipv4 && item.ipv4.length) {
                lines.push(
                    `IPv4: ${item.ipv4.join(", ")}`
                );
            }

            if (item.mac) {
                lines.push(
                    `MAC: ${item.mac}`
                );
            }

            if (item.speed_mbps) {
                lines.push(
                    `Скорость: ${item.speed_mbps} Мбит/с`
                );
            }

            if (item.mtu) {
                lines.push(
                    `MTU: ${item.mtu}`
                );
            }

            const traffic = item.traffic || {};

            lines.push(
                `RX ${formatBytes(traffic.bytes_recv)} · TX ${formatBytes(traffic.bytes_sent)}`
            );

            const detail = document.createElement("span");
            detail.textContent = lines.join(" · ");

            content.append(
                title,
                detail
            );

            box.append(
                dot,
                content
            );

            container.append(box);
        }
    }


    function diagnosticsLabel(name) {
        const labels = {
            route: "Маршрут",
            dns: "DNS",
            https: "GitHub HTTPS",
        };

        return labels[name] || name;
    }


    function renderDiagnostics(data) {
        const summary = data.summary || {};

        setText(
            "diagnosticsSummary",
            `${summary.passed || 0} / ${summary.total || 0} успешно`
        );

        let checkedAt = "—";

        if (data.checked_at) {
            const date = new Date(data.checked_at);

            if (!Number.isNaN(date.getTime())) {
                checkedAt = date.toLocaleString("ru-RU");
            }
        }

        setText(
            "diagnosticsCheckedAt",
            checkedAt
        );

        const container = byId("diagnosticsGrid");

        if (!container) {
            return;
        }

        container.replaceChildren();

        for (
            const [name, check]
            of Object.entries(data.checks || {})
        ) {
            const box = document.createElement("div");
            box.className = "service-item";

            const dot = document.createElement("span");
            dot.className = "service-dot";
            dot.classList.add(
                check.ok
                    ? "active"
                    : "inactive"
            );

            const content = document.createElement("div");
            content.className = "service-name";

            const title = document.createElement("strong");
            title.textContent = diagnosticsLabel(name);

            const detail = document.createElement("span");
            const parts = [
                check.ok
                    ? "OK"
                    : "Ошибка",
            ];

            if (
                check.latency_ms !== undefined
                &&
                check.latency_ms !== null
            ) {
                parts.push(
                    `${check.latency_ms} мс`
                );
            }

            if (check.detail) {
                parts.push(check.detail);
            } else if (check.error) {
                parts.push(check.error);
            }

            detail.textContent = parts.join(" · ");

            content.append(
                title,
                detail
            );

            box.append(
                dot,
                content
            );

            container.append(box);
        }
    }


    function setSelectOptions(
        select,
        interfaces,
        preferred
    ) {
        if (!select) {
            return;
        }

        select.replaceChildren();

        for (const item of interfaces || []) {
            if (item.name === "lo") {
                continue;
            }

            const option = document.createElement("option");
            option.value = item.name;
            option.textContent = `${item.name} · ${roleLabel(item.role)}`;

            if (item.name === preferred) {
                option.selected = true;
            }

            select.append(option);
        }
    }


    function initializePlanner(data) {
        if (interfaceOptionsInitialized) {
            return;
        }

        const interfaces = data.interfaces || [];
        const wan = data.wan_candidate || "";
        const lan = (
            (data.lan_candidates || [])[0]
            ||
            interfaces.find(
                (item) => (
                    item.name !== "lo"
                    &&
                    item.name !== wan
                )
            )?.name
            ||
            ""
        );

        setSelectOptions(
            byId("planWanInterface"),
            interfaces,
            wan
        );
        setSelectOptions(
            byId("planLanInterface"),
            interfaces,
            lan
        );

        const lanItem = interfaces.find(
            (item) => item.name === lan
        );

        const ipv4 = (
            lanItem
            &&
            Array.isArray(lanItem.ipv4_details)
        )
            ? lanItem.ipv4_details[0]
            : null;

        if (
            ipv4
            &&
            ipv4.address
            &&
            ipv4.prefix
        ) {
            byId("planLanAddress").value = (
                `${ipv4.address}/${ipv4.prefix}`
            );
        }

        interfaceOptionsInitialized = true;
    }


    async function refreshOverview() {
        const response = await fetch(
            "/api/v1/network/overview",
            {cache: "no-store"}
        );

        const payload = await response.json();

        if (
            !response.ok
            ||
            payload.ok !== true
        ) {
            throw new Error(
                "network overview request failed"
            );
        }

        const data = payload.data || {};
        const route = data.default_route || {};

        setText(
            "networkWan",
            data.wan_candidate || "не определён"
        );
        setText(
            "networkGateway",
            route.gateway || "—"
        );
        setText(
            "networkMetric",
            (
                route.metric === undefined
                ||
                route.metric === null
            )
                ? "—"
                : String(route.metric)
        );
        setText(
            "networkLan",
            (data.lan_candidates || []).join(", ")
                || "не определены"
        );
        setText(
            "networkDns",
            (data.dns_servers || []).join(", ")
                || "не определены"
        );
        setText(
            "networkVpn",
            (data.vpn_interfaces || []).join(", ")
                || "нет"
        );

        renderInterfaces(
            data.interfaces
        );
        initializePlanner(data);
    }


    async function refreshDiagnostics() {
        const response = await fetch(
            "/api/v1/network/diagnostics",
            {cache: "no-store"}
        );

        const payload = await response.json();

        if (
            !response.ok
            ||
            payload.ok !== true
        ) {
            throw new Error(
                "network diagnostics request failed"
            );
        }

        renderDiagnostics(
            payload.data || {}
        );
    }


    async function refreshAll() {
        try {
            await Promise.all([
                refreshOverview(),
                refreshDiagnostics(),
            ]);

            updateLive(true);

        } catch (error) {
            updateLive(false);
        }
    }


    function formPayload() {
        const dnsValues = byId(
            "planDnsServers"
        ).value
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


    function appendMessages(
        container,
        values,
        className
    ) {
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
        const rollback = byId("networkRollbackSteps");

        const data = payload.data || {};
        const plan = data.plan || {};

        panel.hidden = false;

        status.className = "plan-status";

        if (plan.valid) {
            status.classList.add("ok");
            status.textContent = (
                "План валиден. Применение намеренно заблокировано: dry-run only."
            );
        } else {
            status.classList.add("error");
            status.textContent = (
                "План не прошёл проверку. Сеть не изменялась."
            );
        }

        messages.replaceChildren();

        appendMessages(
            messages,
            plan.errors,
            "error"
        );
        appendMessages(
            messages,
            plan.warnings,
            "warning"
        );

        if (
            !(plan.errors || []).length
            &&
            !(plan.warnings || []).length
        ) {
            const item = document.createElement("div");
            item.className = "plan-message ok";
            item.textContent = "Ошибок и предупреждений нет.";
            messages.append(item);
        }

        steps.replaceChildren();

        for (const step of plan.steps || []) {
            const item = document.createElement("li");
            item.textContent = (
                step.description
                ||
                step.action
                ||
                "—"
            );
            steps.append(item);
        }

        rollback.replaceChildren();

        for (const value of plan.rollback || []) {
            const item = document.createElement("li");
            item.textContent = value;
            rollback.append(item);
        }

        panel.scrollIntoView({
            behavior: "smooth",
            block: "start",
        });
    }


    async function submitPlan(event) {
        event.preventDefault();

        const button = planForm.querySelector(
            "button[type='submit']"
        );

        if (button) {
            button.disabled = true;
            button.textContent = "Проверка...";
        }

        try {
            const response = await fetch(
                "/api/v1/network/plan",
                {
                    method: "POST",
                    cache: "no-store",
                    headers: {
                        "Content-Type": "application/json",
                    },
                    body: JSON.stringify(
                        formPayload()
                    ),
                }
            );

            const payload = await response.json();

            if (!response.ok) {
                throw new Error(
                    payload.error
                    ||
                    "network plan request failed"
                );
            }

            renderPlan(payload);

        } catch (error) {
            const panel = byId("networkPlanResultPanel");
            const status = byId("networkPlanStatus");
            const messages = byId("networkPlanMessages");

            panel.hidden = false;
            status.className = "plan-status error";
            status.textContent = "Ошибка запроса dry-run.";
            messages.replaceChildren();

            const item = document.createElement("div");
            item.className = "plan-message error";
            item.textContent = String(error);
            messages.append(item);

        } finally {
            if (button) {
                button.disabled = false;
                button.textContent = "Проверить и построить план";
            }
        }
    }


    if (planForm) {
        planForm.addEventListener(
            "submit",
            submitPlan
        );
    }

    refreshAll();

    window.setInterval(
        refreshOverview,
        5000
    );
    window.setInterval(
        refreshDiagnostics,
        30000
    );
})();
