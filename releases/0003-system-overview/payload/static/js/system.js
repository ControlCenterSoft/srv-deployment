(() => {
    "use strict";

    const byId = (id) => document.getElementById(id);

    const liveDot = byId("systemLiveDot");
    const liveText = byId("systemLiveText");

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


    function formatUptime(seconds) {
        let value = Math.max(
            0,
            Number(seconds || 0)
        );

        const days = Math.floor(value / 86400);
        value %= 86400;

        const hours = Math.floor(value / 3600);
        value %= 3600;

        const minutes = Math.floor(value / 60);

        const parts = [];

        if (days) {
            parts.push(`${days} д`);
        }

        if (hours || days) {
            parts.push(`${hours} ч`);
        }

        parts.push(`${minutes} мин`);

        return parts.join(" ");
    }


    function formatSyncTime(value) {
        if (!value) {
            return "—";
        }

        const date = new Date(value);

        if (Number.isNaN(date.getTime())) {
            return value;
        }

        return date.toLocaleString(
            "ru-RU",
            {
                day: "2-digit",
                month: "2-digit",
                year: "numeric",
                hour: "2-digit",
                minute: "2-digit",
            }
        );
    }


    function updateStorage(storage) {
        const container = byId("systemStorage");

        if (!container) {
            return;
        }

        container.replaceChildren();

        for (const item of storage || []) {
            const row = document.createElement("div");
            row.className = "storage-row";

            const heading = document.createElement("div");
            heading.className = "storage-heading";

            const label = document.createElement("span");
            label.textContent = item.path || "—";

            const value = document.createElement("strong");
            value.textContent = (
                `${formatBytes(item.used)} / ${formatBytes(item.total)}`
            );

            heading.append(
                label,
                value
            );

            const track = document.createElement("div");
            track.className = "storage-track";

            const bar = document.createElement("div");
            bar.className = "storage-bar";

            const percent = Math.max(
                0,
                Math.min(
                    100,
                    Number(item.percent || 0)
                )
            );

            if (percent >= 90) {
                bar.classList.add("danger");
            } else if (percent >= 80) {
                bar.classList.add("warning");
            }

            bar.style.width = `${percent}%`;

            track.append(bar);
            row.append(
                heading,
                track
            );
            container.append(row);
        }
    }


    function updateServices(services) {
        const container = byId("systemServices");

        if (!container) {
            return;
        }

        container.replaceChildren();

        for (
            const [name, state]
            of Object.entries(services || {})
        ) {
            const item = document.createElement("div");
            item.className = "service-item";

            const dot = document.createElement("span");
            dot.className = "service-dot";

            if (state === "active") {
                dot.classList.add("active");
            } else {
                dot.classList.add("inactive");
            }

            const nameBox = document.createElement("div");
            nameBox.className = "service-name";

            const strong = document.createElement("strong");
            strong.textContent = name;

            const status = document.createElement("span");
            status.textContent = state || "unknown";

            nameBox.append(
                strong,
                status
            );

            item.append(
                dot,
                nameBox
            );
            container.append(item);
        }
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


    async function refresh() {
        try {
            const [
                metricsResponse,
                healthResponse,
            ] = await Promise.all([
                fetch(
                    "/api/v1/dashboard/metrics",
                    {cache: "no-store"}
                ),
                fetch(
                    "/api/v1/health",
                    {cache: "no-store"}
                ),
            ]);

            const metricsPayload = await metricsResponse.json();
            const healthPayload = await healthResponse.json();

            if (
                !metricsResponse.ok
                ||
                !healthResponse.ok
                ||
                !metricsPayload.ok
                ||
                !healthPayload.ok
            ) {
                throw new Error("system status request failed");
            }

            const data = metricsPayload.data || {};
            const system = data.system || {};
            const cpu = data.cpu || {};
            const memory = data.memory || {};
            const uptime = data.uptime || {};
            const release = (
                healthPayload.data
                &&
                healthPayload.data.release
            )
                ? healthPayload.data.release
                : {};

            setText(
                "systemHostname",
                system.hostname || "—"
            );
            setText(
                "systemOs",
                system.os || "—"
            );
            setText(
                "systemKernel",
                system.kernel || "—"
            );
            setText(
                "systemArchitecture",
                system.architecture || "—"
            );
            setText(
                "systemUptime",
                formatUptime(uptime.seconds)
            );
            setText(
                "systemCpu",
                (
                    `${Number(cpu.percent || 0).toFixed(1)}%`
                    +
                    ` · ${cpu.logical_count || 0} потоков`
                )
            );
            setText(
                "systemLoad",
                [
                    cpu.load1 ?? 0,
                    cpu.load5 ?? 0,
                    cpu.load15 ?? 0,
                ].join(" / ")
            );
            setText(
                "systemMemory",
                (
                    `${Number(memory.percent || 0).toFixed(1)}%`
                    +
                    ` · ${formatBytes(memory.used)}`
                    +
                    ` / ${formatBytes(memory.total)}`
                )
            );
            setText(
                "systemRelease",
                release.version
                    ? `v${release.version}`
                    : "—"
            );
            setText(
                "systemGitHubSync",
                formatSyncTime(release.synced_at)
            );

            updateStorage(data.storage);
            updateServices(data.services);
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
