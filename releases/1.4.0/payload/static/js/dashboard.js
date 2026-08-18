(() => {
    "use strict";

    const MAX_POINTS = 70;
    const rxHistory = [];
    const txHistory = [];
    let previousNetwork = null;

    const byId = (id) => document.getElementById(id);
    const elements = {
        serviceCount: byId("serviceCount"),
        serviceMeta: byId("serviceMeta"),
        accessMeta: byId("accessMeta"),
        releaseMeta: byId("releaseMeta"),
        uptime: byId("uptime"),
        uptimeDetail: byId("uptimeDetail"),
        serviceGrid: byId("serviceGrid"),
        cpuProcesses: byId("cpuProcesses"),
        ramProcesses: byId("ramProcesses"),
        storageList: byId("storageList"),
        storageSummary: byId("storageSummary"),
        systemOs: byId("systemOs"),
        kernelValue: byId("kernelValue"),
        loadAverage: byId("loadAverage"),
        databaseStatus: byId("databaseStatus"),
        cpuValue: byId("cpuValue"),
        ramValue: byId("ramValue"),
        ramDetail: byId("ramDetail"),
        cpuBar: byId("cpuBar"),
        ramBar: byId("ramBar"),
        networkRx: byId("networkRx"),
        networkTx: byId("networkTx"),
        streamDot: byId("streamDot"),
        streamText: byId("streamText"),
        wanName: byId("wanName"),
        wanAddress: byId("wanAddress"),
        wanState: byId("wanState"),
        lanName: byId("lanName"),
        lanAddress: byId("lanAddress"),
        dnsValue: byId("dnsValue"),
        serverHostname: byId("serverHostname"),
        serverAddress: byId("serverAddress"),
        footerVersion: byId("footerVersion"),
        serverTime: byId("serverTime"),
    };

    const SERVICE_META = {
        "srv-control": ["Control Center", "Основной backend", "C"],
        "PostgreSQL": ["PostgreSQL", "База данных", "DB"],
        "Apache": ["Web Service", "Веб-служба", "WEB"],
        "Samba AD": ["Directory & Access", "Домен и доступы", "AD"],
        "DHCP": ["DHCP Server", "Выдача сетевых адресов", "DH"],
        "TFTP": ["PXE / TFTP", "Сетевая загрузка", "PX"],
        "Docker": ["Container Runtime", "Контейнеры", "CT"],
    };

    function humanBytes(value) {
        let number = Number(value || 0);
        const units = ["Б", "КБ", "МБ", "ГБ", "ТБ", "ПБ"];
        let index = 0;
        while (Math.abs(number) >= 1024 && index < units.length - 1) {
            number /= 1024;
            index += 1;
        }
        const digits = Math.abs(number) >= 100 ? 0 : Math.abs(number) >= 10 ? 1 : 2;
        return `${number.toFixed(digits)} ${units[index]}`;
    }

    function humanBitRate(bytesPerSecond) {
        let value = Math.max(0, Number(bytesPerSecond || 0)) * 8;
        const units = ["бит/с", "Кбит/с", "Мбит/с", "Гбит/с"];
        let index = 0;
        while (value >= 1000 && index < units.length - 1) {
            value /= 1000;
            index += 1;
        }
        const digits = value >= 100 ? 0 : value >= 10 ? 1 : 2;
        return `${value.toFixed(digits)} ${units[index]}`;
    }

    function durationParts(seconds) {
        let value = Math.max(0, Number(seconds || 0));
        const days = Math.floor(value / 86400);
        value %= 86400;
        const hours = Math.floor(value / 3600);
        value %= 3600;
        const minutes = Math.floor(value / 60);
        if (days > 0) return {main: `${days} дн.`, detail: `${hours} ч ${minutes} мин`};
        if (hours > 0) return {main: `${hours} ч`, detail: `${minutes} мин`};
        return {main: `${minutes} мин`, detail: "с момента запуска"};
    }

    function pushPoint(target, value) {
        target.push(Math.max(0, Number(value || 0)));
        while (target.length > MAX_POINTS) target.shift();
    }

    function resizeCanvas(canvas) {
        const ratio = window.devicePixelRatio || 1;
        const bounds = canvas.getBoundingClientRect();
        const width = Math.max(1, Math.round(bounds.width * ratio));
        const height = Math.max(1, Math.round(bounds.height * ratio));
        if (canvas.width !== width || canvas.height !== height) {
            canvas.width = width;
            canvas.height = height;
        }
        return {width, height, ratio};
    }

    function drawTrafficChart(canvas, values, stroke, fill) {
        if (!canvas) return;
        const size = resizeCanvas(canvas);
        const context = canvas.getContext("2d");
        context.clearRect(0, 0, size.width, size.height);
        if (values.length < 2) return;

        const peak = Math.max(1, ...values);
        const points = values.map((value, index) => ({
            x: index / (values.length - 1) * size.width,
            y: size.height - (value / peak) * size.height * .72 - size.height * .08,
        }));

        context.beginPath();
        context.moveTo(points[0].x, size.height);
        for (const point of points) context.lineTo(point.x, point.y);
        context.lineTo(points[points.length - 1].x, size.height);
        context.closePath();
        const gradient = context.createLinearGradient(0, 0, 0, size.height);
        gradient.addColorStop(0, fill);
        gradient.addColorStop(1, "rgba(0,0,0,0)");
        context.fillStyle = gradient;
        context.fill();

        context.beginPath();
        points.forEach((point, index) => {
            if (index === 0) context.moveTo(point.x, point.y);
            else context.lineTo(point.x, point.y);
        });
        context.strokeStyle = stroke;
        context.lineWidth = 1.5 * size.ratio;
        context.lineJoin = "round";
        context.lineCap = "round";
        context.stroke();
    }

    function renderProcesses(container, items, kind) {
        container.replaceChildren();
        if (!Array.isArray(items) || items.length === 0) {
            const empty = document.createElement("div");
            empty.className = "process-empty";
            empty.textContent = "Нет данных";
            container.appendChild(empty);
            return;
        }
        for (const item of items.slice(0, 3)) {
            const row = document.createElement("div");
            row.className = "process-row";
            const name = document.createElement("span");
            name.className = "process-name";
            name.textContent = item.name || `PID ${item.pid || "—"}`;
            name.title = `${item.name || "process"} · PID ${item.pid || "—"}`;
            const value = document.createElement("strong");
            value.className = "process-value";
            value.textContent = kind === "cpu"
                ? `${Number(item.cpu_percent || 0).toFixed(1)}%`
                : `${Number(item.memory_percent || 0).toFixed(1)}%`;
            row.append(name, value);
            container.appendChild(row);
        }
    }

    function renderStorage(items) {
        const values = Array.isArray(items) ? items : [];
        elements.storageList.replaceChildren();
        if (values.length === 0) {
            elements.storageSummary.textContent = "Нет данных о дисках";
            return;
        }
        const primary = values[0];
        elements.storageSummary.textContent = `${humanBytes(primary.used)} / ${humanBytes(primary.total)} · использовано ${primary.percent}%`;
        for (const item of values) {
            const row = document.createElement("div");
            row.className = "storage-row";
            const heading = document.createElement("div");
            heading.className = "storage-heading";
            const label = document.createElement("span");
            label.textContent = item.path === "/" ? "Системный диск" : item.path;
            const detail = document.createElement("strong");
            detail.textContent = `${item.percent}% · свободно ${humanBytes(item.free)}`;
            heading.append(label, detail);
            const track = document.createElement("div");
            track.className = "storage-track";
            const bar = document.createElement("span");
            bar.className = "storage-bar";
            if (item.percent >= 95) bar.classList.add("danger");
            else if (item.percent >= 85) bar.classList.add("warning");
            bar.style.width = `${Math.min(100, Number(item.percent || 0))}%`;
            track.appendChild(bar);
            row.append(heading, track);
            elements.storageList.appendChild(row);
        }
    }

    function serviceMeta(name) {
        return SERVICE_META[name] || [name, "Системная служба", "SV"];
    }

    function normalizeState(value) {
        const state = String(value || "unknown").toLowerCase();
        if (state === "active") return "active";
        if (state === "failed") return "failed";
        if (state === "inactive") return "inactive";
        return "unknown";
    }

    function renderServices(services) {
        const entries = Object.entries(services || {});
        elements.serviceGrid.replaceChildren();
        const active = entries.filter(([, state]) => String(state).toLowerCase() === "active").length;
        elements.serviceCount.textContent = String(active);
        elements.serviceMeta.textContent = `активно из ${entries.length}`;

        for (const [name, state] of entries) {
            const [titleText, description, iconText] = serviceMeta(name);
            const item = document.createElement("div");
            item.className = "service-item";

            const icon = document.createElement("div");
            icon.className = "service-icon";
            icon.textContent = iconText;

            const copy = document.createElement("div");
            copy.className = "service-copy";
            const title = document.createElement("strong");
            title.textContent = titleText;
            const subtitle = document.createElement("span");
            subtitle.textContent = description;
            copy.append(title, subtitle);

            const status = document.createElement("span");
            const normalized = normalizeState(state);
            status.className = `service-state ${normalized}`;
            status.textContent = normalized;

            const chevron = document.createElement("span");
            chevron.className = "service-chevron";
            chevron.textContent = "›";
            item.append(icon, copy, status, chevron);
            elements.serviceGrid.appendChild(item);
        }
    }

    function renderServerTime(value) {
        const date = new Date(value || Date.now());
        if (Number.isNaN(date.getTime())) return;
        elements.serverTime.textContent = `Время сервера: ${date.toLocaleString("ru-RU", {
            day: "2-digit", month: "2-digit", year: "numeric",
            hour: "2-digit", minute: "2-digit", second: "2-digit",
        })}`;
    }

    function render(data) {
        const uptime = durationParts(data.uptime && data.uptime.seconds);
        elements.uptime.textContent = uptime.main;
        elements.uptimeDetail.textContent = uptime.detail;

        const cpuPercent = Number(data.cpu && data.cpu.percent || 0);
        const ramPercent = Number(data.memory && data.memory.percent || 0);
        elements.cpuValue.textContent = `${cpuPercent.toFixed(1)}%`;
        elements.ramValue.textContent = `${ramPercent.toFixed(1)}%`;
        elements.cpuBar.style.width = `${Math.min(100, Math.max(0, cpuPercent))}%`;
        elements.ramBar.style.width = `${Math.min(100, Math.max(0, ramPercent))}%`;
        elements.ramDetail.textContent = `${humanBytes(data.memory && data.memory.used)} / ${humanBytes(data.memory && data.memory.total)}`;
        elements.loadAverage.textContent = `${data.cpu.load1} / ${data.cpu.load5} / ${data.cpu.load15}`;
        elements.databaseStatus.textContent = data.database && data.database.state || "unknown";
        elements.systemOs.textContent = data.system && data.system.os || "—";
        elements.kernelValue.textContent = data.system && data.system.kernel || "—";
        elements.serverHostname.textContent = data.system && data.system.hostname || "—";

        renderProcesses(elements.cpuProcesses, data.processes && data.processes.cpu_top, "cpu");
        renderProcesses(elements.ramProcesses, data.processes && data.processes.memory_top, "ram");
        renderStorage(data.storage);
        renderServices(data.services);
        renderServerTime(data.timestamp);

        if (previousNetwork) {
            const currentTime = Date.now();
            const seconds = Math.max(.001, (currentTime - previousNetwork.time) / 1000);
            const rx = Math.max(0, Number(data.network.bytes_recv || 0) - previousNetwork.rx) / seconds;
            const tx = Math.max(0, Number(data.network.bytes_sent || 0) - previousNetwork.tx) / seconds;
            elements.networkRx.textContent = humanBitRate(rx);
            elements.networkTx.textContent = humanBitRate(tx);
            pushPoint(rxHistory, rx);
            pushPoint(txHistory, tx);
            drawTrafficChart(byId("networkRxChart"), rxHistory, "#2f9cff", "rgba(47,156,255,.22)");
            drawTrafficChart(byId("networkTxChart"), txHistory, "#16df89", "rgba(22,223,137,.22)");
        }
        previousNetwork = {
            time: Date.now(),
            rx: Number(data.network.bytes_recv || 0),
            tx: Number(data.network.bytes_sent || 0),
        };
    }

    function interfaceAddress(item) {
        if (!item) return "—";
        const details = Array.isArray(item.ipv4_details) ? item.ipv4_details : [];
        if (details.length > 0) {
            const address = details[0].address || "—";
            const prefix = details[0].prefix;
            return Number.isInteger(prefix) ? `${address}/${prefix}` : address;
        }
        return Array.isArray(item.ipv4) && item.ipv4[0] ? item.ipv4[0] : "—";
    }

    function chooseLan(data) {
        const interfaces = Array.isArray(data.interfaces) ? data.interfaces : [];
        const candidates = interfaces.filter((item) => (data.lan_candidates || []).includes(item.name));
        const score = (item) => {
            const name = String(item.name || "").toLowerCase();
            let value = item.is_up ? 20 : 0;
            if (/^(en|eth|bond|br-lan)/.test(name)) value += 20;
            if (/^(docker|br-|veth|virbr|tun|tap|wg)/.test(name) && name !== "br-lan") value -= 30;
            if (Array.isArray(item.ipv4) && item.ipv4.length) value += 10;
            return value;
        };
        return candidates.sort((a, b) => score(b) - score(a))[0] || null;
    }

    async function loadNetworkOverview() {
        try {
            const response = await fetch("/api/v1/network/overview", {cache: "no-store"});
            if (response.status === 403) {
                elements.wanState.textContent = "Нет доступа";
                return;
            }
            if (!response.ok) throw new Error("network overview failed");
            const payload = await response.json();
            const data = payload.data || {};
            const interfaces = Array.isArray(data.interfaces) ? data.interfaces : [];
            const wan = interfaces.find((item) => item.name === data.wan_candidate) || null;
            const lan = chooseLan(data);

            elements.wanName.textContent = wan && wan.name || data.wan_candidate || "—";
            elements.wanAddress.textContent = interfaceAddress(wan);
            elements.wanState.textContent = wan ? (wan.is_up ? "Online" : "Offline") : "Не определён";
            elements.lanName.textContent = lan && lan.name || "—";
            elements.lanAddress.textContent = interfaceAddress(lan);
            elements.serverAddress.textContent = lan && Array.isArray(lan.ipv4) && lan.ipv4[0]
                ? lan.ipv4[0]
                : (wan && Array.isArray(wan.ipv4) && wan.ipv4[0] ? wan.ipv4[0] : "—");
            const dns = Array.isArray(data.dns_servers) ? data.dns_servers.slice(0, 2).join(", ") : "";
            elements.dnsValue.textContent = dns ? `DNS: ${dns}` : "DNS: —";
        } catch (_) {
            elements.wanState.textContent = "Ошибка";
        }
    }

    async function loadIdentityAndRelease() {
        try {
            const [identityResponse, healthResponse] = await Promise.all([
                fetch("/api/v1/auth/status", {cache: "no-store"}),
                fetch("/api/v1/health", {cache: "no-store"}),
            ]);
            if (identityResponse.ok) {
                const payload = await identityResponse.json();
                const identity = payload.data && payload.data.identity || {};
                elements.accessMeta.textContent = identity.is_admin ? "администратор · полные права" : "единые права доступа";
            }
            if (healthResponse.ok) {
                const payload = await healthResponse.json();
                const release = payload.data && payload.data.release || {};
                if (release.version) {
                    elements.releaseMeta.textContent = `Control Center ${release.version}`;
                    elements.footerVersion.textContent = `Версия ${release.version} (Stable)`;
                }
            }
        } catch (_) {
            // Dashboard metrics remain useful even if supplemental metadata is unavailable.
        }
    }

    function setStreamState(state, text) {
        elements.streamDot.classList.remove("ok", "error");
        if (state) elements.streamDot.classList.add(state);
        elements.streamText.textContent = text;
    }

    function connect() {
        const source = new EventSource("/api/v1/dashboard/stream");
        source.addEventListener("open", () => setStreamState("ok", "Система работает"));
        source.addEventListener("metrics", (event) => {
            try {
                const payload = JSON.parse(event.data);
                if (!payload.ok || !payload.data) throw new Error("invalid metrics");
                render(payload.data);
                setStreamState("ok", "Система работает");
            } catch (_) {
                setStreamState("error", "Ошибка данных");
            }
        });
        source.onerror = () => setStreamState("error", "Переподключение");
    }

    window.addEventListener("resize", () => {
        drawTrafficChart(byId("networkRxChart"), rxHistory, "#2f9cff", "rgba(47,156,255,.22)");
        drawTrafficChart(byId("networkTxChart"), txHistory, "#16df89", "rgba(22,223,137,.22)");
    });

    loadIdentityAndRelease();
    loadNetworkOverview();
    window.setInterval(loadNetworkOverview, 15000);
    connect();
})();
