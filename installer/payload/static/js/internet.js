(() => {
    "use strict";

    const byId = (id) => document.getElementById(id);

    const liveDot = byId("networkLiveDot");
    const liveText = byId("networkLiveText");

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


    async function refresh() {
        try {
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
                    || route.metric === null
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
            updateLive(true);

        } catch (error) {
            updateLive(false);
        }
    }


    refresh();

    window.setInterval(
        refresh,
        5000
    );
})();
