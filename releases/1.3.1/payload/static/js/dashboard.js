(() => {
    "use strict";

    const MAX_POINTS = 120;
    const cpuHistory = [];
    const ramHistory = [];
    let previousNetwork = null;

    const byId = (id) => document.getElementById(id);
    const elements = {
        cpuValue: byId("cpuValue"),
        cpuDetail: byId("cpuDetail"),
        ramValue: byId("ramValue"),
        ramDetail: byId("ramDetail"),
        cpuProcesses: byId("cpuProcesses"),
        ramProcesses: byId("ramProcesses"),
        networkRx: byId("networkRx"),
        networkTx: byId("networkTx"),
        networkRxTotal: byId("networkRxTotal"),
        networkTxTotal: byId("networkTxTotal"),
        uptime: byId("uptime"),
        loadAverage: byId("loadAverage"),
        databaseStatus: byId("databaseStatus"),
        storageList: byId("storageList"),
        serviceGrid: byId("serviceGrid"),
        streamDot: byId("streamDot"),
        streamText: byId("streamText"),
    };

    function humanBytes(value, perSecond = false) {
        let number = Number(value || 0);
        const units = ["B", "KB", "MB", "GB", "TB"];
        let index = 0;
        while (Math.abs(number) >= 1024 && index < units.length - 1) {
            number /= 1024;
            index += 1;
        }
        const digits = Math.abs(number) >= 100 ? 0 : Math.abs(number) >= 10 ? 1 : 2;
        return `${number.toFixed(digits)} ${units[index]}${perSecond ? "/с" : ""}`;
    }

    function humanDuration(seconds) {
        let value = Math.max(0, Number(seconds || 0));
        const days = Math.floor(value / 86400);
        value %= 86400;
        const hours = Math.floor(value / 3600);
        value %= 3600;
        const minutes = Math.floor(value / 60);
        if (days > 0) return `${days} д ${hours} ч ${minutes} мин`;
        if (hours > 0) return `${hours} ч ${minutes} мин`;
        return `${minutes} мин`;
    }

    function pushPoint(target, value) {
        target.push(Number(value) || 0);
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

    function drawChart(canvas, values) {
        if (!canvas) return;
        const size = resizeCanvas(canvas);
        const context = canvas.getContext("2d");
        context.clearRect(0, 0, size.width, size.height);
        const style = getComputedStyle(document.documentElement);
        const accent = style.getPropertyValue("--accent").trim() || "#4195d9";
        const border = style.getPropertyValue("--border").trim() || "#24364b";

        context.lineWidth = size.ratio;
        context.strokeStyle = border;
        for (let row = 1; row < 4; row += 1) {
            const y = size.height * row / 4;
            context.beginPath();
            context.moveTo(0, y);
            context.lineTo(size.width, y);
            context.stroke();
        }
        if (values.length < 2) return;

        context.strokeStyle = accent;
        context.lineWidth = 2 * size.ratio;
        context.lineJoin = "round";
        context.lineCap = "round";
        context.beginPath();
        values.forEach((value, index) => {
            const x = index / (values.length - 1) * size.width;
            const normalized = Math.min(100, Math.max(0, Number(value) || 0));
            const y = size.height - normalized / 100 * size.height;
            if (index === 0) context.moveTo(x, y);
            else context.lineTo(x, y);
        });
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
            name.textContent = `${item.name || "process"} · PID ${item.pid || "—"}`;
            name.title = item.user ? `${item.name || "process"} · ${item.user}` : (item.name || "process");
            const value = document.createElement("strong");
            value.className = "process-value";
            value.textContent = kind === "cpu"
                ? `${Number(item.cpu_percent || 0).toFixed(1)}%`
                : `${Number(item.memory_percent || 0).toFixed(1)}% · ${humanBytes(item.memory_rss || 0)}`;
            row.append(name, value);
            container.appendChild(row);
        }
    }

    function renderStorage(items) {
        elements.storageList.replaceChildren();
        for (const item of items || []) {
            const row = document.createElement("div");
            row.className = "storage-row";
            const heading = document.createElement("div");
            heading.className = "storage-heading";
            const label = document.createElement("span");
            label.textContent = item.path;
            const detail = document.createElement("strong");
            detail.textContent = `${item.percent}% · ${humanBytes(item.free)} свободно`;
            heading.append(label, detail);
            const track = document.createElement("div");
            track.className = "storage-track";
            const bar = document.createElement("div");
            bar.className = "storage-bar";
            if (item.percent >= 95) bar.classList.add("danger");
            else if (item.percent >= 85) bar.classList.add("warning");
            bar.style.width = `${Math.min(100, Number(item.percent || 0))}%`;
            track.appendChild(bar);
            row.append(heading, track);
            elements.storageList.appendChild(row);
        }
    }

    function renderServices(services) {
        elements.serviceGrid.replaceChildren();
        for (const [name, state] of Object.entries(services || {})) {
            const item = document.createElement("div");
            item.className = "service-item";
            const dot = document.createElement("span");
            dot.className = `service-dot ${String(state || "unknown")}`;
            const box = document.createElement("div");
            box.className = "service-name";
            const title = document.createElement("strong");
            title.textContent = name;
            const status = document.createElement("span");
            status.textContent = state || "unknown";
            box.append(title, status);
            item.append(dot, box);
            elements.serviceGrid.appendChild(item);
        }
    }

    function render(data) {
        pushPoint(cpuHistory, data.cpu.percent);
        pushPoint(ramHistory, data.memory.percent);
        elements.cpuValue.textContent = `${Number(data.cpu.percent || 0).toFixed(1)}%`;
        elements.cpuDetail.textContent = `${data.cpu.physical_count || 0} ядер / ${data.cpu.logical_count || 0} потоков`;
        elements.ramValue.textContent = `${Number(data.memory.percent || 0).toFixed(1)}%`;
        elements.ramDetail.textContent = `${humanBytes(data.memory.used)} / ${humanBytes(data.memory.total)}`;

        renderProcesses(elements.cpuProcesses, data.processes && data.processes.cpu_top, "cpu");
        renderProcesses(elements.ramProcesses, data.processes && data.processes.memory_top, "ram");

        elements.uptime.textContent = humanDuration(data.uptime.seconds);
        elements.loadAverage.textContent = `${data.cpu.load1} / ${data.cpu.load5} / ${data.cpu.load15}`;
        elements.databaseStatus.textContent = data.database.state;

        if (previousNetwork) {
            const currentTime = Date.now();
            const seconds = Math.max(0.001, (currentTime - previousNetwork.time) / 1000);
            const rx = Math.max(0, data.network.bytes_recv - previousNetwork.rx) / seconds;
            const tx = Math.max(0, data.network.bytes_sent - previousNetwork.tx) / seconds;
            elements.networkRx.textContent = humanBytes(rx, true);
            elements.networkTx.textContent = humanBytes(tx, true);
        }
        previousNetwork = {time: Date.now(), rx: data.network.bytes_recv, tx: data.network.bytes_sent};
        elements.networkRxTotal.textContent = humanBytes(data.network.bytes_recv);
        elements.networkTxTotal.textContent = humanBytes(data.network.bytes_sent);

        renderStorage(data.storage);
        renderServices(data.services);
        drawChart(byId("cpuChart"), cpuHistory);
        drawChart(byId("ramChart"), ramHistory);
    }

    function setStreamState(state, text) {
        elements.streamDot.classList.remove("ok", "error");
        if (state) elements.streamDot.classList.add(state);
        elements.streamText.textContent = text;
    }

    function connect() {
        const source = new EventSource("/api/v1/dashboard/stream");
        source.addEventListener("open", () => setStreamState("ok", "Онлайн"));
        source.addEventListener("metrics", (event) => {
            try {
                const payload = JSON.parse(event.data);
                if (!payload.ok || !payload.data) throw new Error("invalid metrics");
                render(payload.data);
                setStreamState("ok", "Онлайн");
            } catch (_) {
                setStreamState("error", "Ошибка данных");
            }
        });
        source.onerror = () => setStreamState("error", "Переподключение");
    }

    window.addEventListener("resize", () => {
        drawChart(byId("cpuChart"), cpuHistory);
        drawChart(byId("ramChart"), ramHistory);
    });

    connect();
})();
