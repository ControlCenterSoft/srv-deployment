(() => {
    "use strict";

    const BASE = "/api/v1/minecraft/legacy";
    const POLL_MS = 5000;
    let currentCommand = 0;
    let lastStatus = null;

    const $ = (id) => document.getElementById(id);
    const text = (value, fallback = "—") => value === undefined || value === null || value === "" ? fallback : String(value);

    function installStyle() {
        if ($("mc212StatusStyle")) return;
        const style = document.createElement("style");
        style.id = "mc212StatusStyle";
        style.textContent = `
            .mc212-runtime{margin:0 0 16px;padding:16px 18px}
            .mc212-runtime-head{display:flex;align-items:center;justify-content:space-between;gap:12px;margin-bottom:12px}
            .mc212-runtime-head h2{margin:0;font-size:1rem}
            .mc212-state-badge{display:inline-flex;align-items:center;gap:7px;padding:6px 10px;border-radius:999px;border:1px solid var(--border,#24435d);font-weight:800;font-size:.78rem}
            .mc212-state-badge::before{content:"";width:8px;height:8px;border-radius:50%;background:#8aa0b5}
            .mc212-state-badge.ok{color:#7cf7b4;border-color:rgba(83,222,148,.35);background:rgba(47,180,111,.08)}
            .mc212-state-badge.ok::before{background:#4ee69a;box-shadow:0 0 10px rgba(78,230,154,.55)}
            .mc212-state-badge.off{color:#ffc36a;border-color:rgba(255,181,71,.35);background:rgba(255,181,71,.07)}
            .mc212-state-badge.off::before{background:#ffb547}
            .mc212-state-badge.bad{color:#ff8f9a;border-color:rgba(255,95,110,.35);background:rgba(255,95,110,.07)}
            .mc212-state-badge.bad::before{background:#ff5f6e}
            .mc212-status-grid{display:grid;grid-template-columns:repeat(7,minmax(105px,1fr));gap:10px}
            .mc212-item{padding:10px 12px;border:1px solid rgba(120,164,200,.16);border-radius:10px;background:rgba(8,22,34,.5)}
            .mc212-item span{display:block;color:#8297aa;font-size:.7rem;text-transform:uppercase;letter-spacing:.06em;margin-bottom:4px}
            .mc212-item strong{display:block;font-size:.88rem;overflow-wrap:anywhere}
            .mc212-command{margin-top:12px;padding:11px 13px;border-radius:10px;border:1px solid rgba(120,164,200,.18);background:rgba(8,22,34,.6);font-size:.86rem}
            .mc212-command.pending{border-color:rgba(68,184,255,.35)}
            .mc212-command.ok{border-color:rgba(83,222,148,.35);color:#baf7d3}
            .mc212-command.error{border-color:rgba(255,95,110,.35);color:#ffc0c6}
            .mc212-status-error{margin-top:8px;color:#ff9da6;font-size:.8rem}
            @media(max-width:1180px){.mc212-status-grid{grid-template-columns:repeat(4,minmax(120px,1fr))}}
            @media(max-width:760px){.mc212-runtime-head{align-items:flex-start;flex-direction:column}.mc212-status-grid{grid-template-columns:repeat(2,minmax(0,1fr))}}
        `;
        document.head.appendChild(style);
    }

    function ensurePanel() {
        if ($("mc212RuntimeStatus")) return;
        installStyle();
        const panel = document.createElement("section");
        panel.className = "panel mc212-runtime";
        panel.id = "mc212RuntimeStatus";
        panel.setAttribute("aria-live", "polite");
        panel.innerHTML = `
            <div class="mc212-runtime-head">
                <div><span class="section-kicker">Проверка в реальном времени</span><h2>Состояние Minecraft Bedrock</h2></div>
                <span class="mc212-state-badge" id="mc212StateBadge">Проверка…</span>
            </div>
            <div class="mc212-status-grid">
                <div class="mc212-item"><span>Состояние</span><strong id="mc212State">—</strong></div>
                <div class="mc212-item"><span>Здоровье</span><strong id="mc212Health">—</strong></div>
                <div class="mc212-item"><span>PID</span><strong id="mc212Pid">—</strong></div>
                <div class="mc212-item"><span>UDP порт</span><strong id="mc212Port">—</strong></div>
                <div class="mc212-item"><span>Мир</span><strong id="mc212World">—</strong></div>
                <div class="mc212-item"><span>Версия</span><strong id="mc212Version">—</strong></div>
                <div class="mc212-item"><span>Проверено</span><strong id="mc212Checked">—</strong></div>
            </div>
            <div class="mc212-status-error" id="mc212StatusError" hidden></div>
            <div class="mc212-command" id="mc212CommandResult">Последняя команда: нет данных.</div>
        `;
        const anchor = $("minecraftMessage");
        if (anchor) anchor.insertAdjacentElement("afterend", panel);
        else document.querySelector(".mc132-header")?.insertAdjacentElement("afterend", panel);
    }

    async function apiStatus() {
        const response = await fetch(`${BASE}/status`, {cache: "no-store"});
        if (response.status === 401) {
            window.top.location.replace("/login");
            throw new Error("Требуется вход в систему");
        }
        let payload = null;
        try { payload = await response.json(); } catch (_) {}
        if (!response.ok || !payload || payload.ok === false) {
            throw new Error(String(payload?.detail || payload?.error || `HTTP ${response.status}`));
        }
        return payload.data ?? payload;
    }

    function setStatusDisabled(button, disabled) {
        if (!button) return;
        if (disabled) {
            if (!button.disabled) {
                button.disabled = true;
                button.dataset.mc212DisabledByStatus = "1";
            }
        } else if (button.dataset.mc212DisabledByStatus === "1" && document.body.getAttribute("aria-busy") !== "true") {
            button.disabled = false;
            delete button.dataset.mc212DisabledByStatus;
        }
    }

    function render(status) {
        ensurePanel();
        lastStatus = status;
        const active = Boolean(status.active);
        const healthy = Boolean(status.healthy);
        const state = status.status_label || (active ? (healthy ? "Работает" : "Запущен с ошибкой") : "Остановлен");
        const badge = $("mc212StateBadge");
        badge.textContent = active ? (healthy ? "ONLINE" : "DEGRADED") : "OFFLINE";
        badge.className = `mc212-state-badge ${active ? (healthy ? "ok" : "bad") : "off"}`;
        $("mc212State").textContent = state;
        $("mc212Health").textContent = healthy ? "Норма" : (active ? "Требует внимания" : "Не запущен");
        $("mc212Pid").textContent = text(status.main_pid);
        $("mc212Port").textContent = status.port ? `${status.port} · ${status.port_listening ? "слушается" : "не слушается"}` : "—";
        $("mc212World").textContent = `${text(status.level_name)}${status.world_exists === false ? " · недоступен" : ""}`;
        $("mc212Version").textContent = text(status.version);
        $("mc212Checked").textContent = new Date().toLocaleTimeString("ru-RU");

        const error = $("mc212StatusError");
        if (status.status_error) {
            error.hidden = false;
            error.textContent = `Диагностика: ${status.status_error}`;
        } else {
            error.hidden = true;
            error.textContent = "";
        }

        const serviceBadge = $("serviceBadge");
        if (serviceBadge) {
            serviceBadge.textContent = active ? (healthy ? "Сервер работает" : "Сервер запущен с ошибкой") : "Сервер остановлен";
            serviceBadge.className = `mc-badge ${active ? (healthy ? "ok" : "warn") : "warn"}`;
        }
        if ($("summaryState")) $("summaryState").textContent = active ? (healthy ? "ONLINE" : "DEGRADED") : "OFFLINE";

        if (document.body.getAttribute("aria-busy") !== "true") {
            setStatusDisabled($("serverStart"), active);
            setStatusDisabled($("serverRestart"), !active);
            setStatusDisabled($("serverStop"), !active);
        }
    }

    function commandResult(message, kind = "") {
        ensurePanel();
        const box = $("mc212CommandResult");
        box.textContent = message;
        box.className = `mc212-command ${kind}`.trim();
    }

    async function refresh() {
        if (document.hidden) return;
        try {
            render(await apiStatus());
        } catch (error) {
            ensurePanel();
            $("mc212StateBadge").textContent = "СТАТУС НЕДОСТУПЕН";
            $("mc212StateBadge").className = "mc212-state-badge bad";
            const diagnostics = $("mc212StatusError");
            diagnostics.hidden = false;
            diagnostics.textContent = `Не удалось получить состояние сервера: ${error.message}`;
        }
    }

    function expected(action, status) {
        if (action === "stop") return status.active === false;
        return status.active === true && status.healthy === true;
    }

    function successText(action, status) {
        if (action === "stop") {
            return `Последняя команда: остановка выполнена. Сервер OFFLINE. Мир: ${text(status.level_name)}.`;
        }
        const label = action === "start" ? "запуск" : "перезапуск";
        return `Последняя команда: ${label} выполнен. Сервер ONLINE · UDP ${text(status.port)} · PID ${text(status.main_pid)} · мир ${text(status.level_name)}.`;
    }

    async function observeCommand(action, label, token) {
        const messageBox = $("minecraftMessage");
        let started = false;
        for (let i = 0; i < 150 && token === currentCommand; i += 1) {
            const msg = messageBox?.textContent || "";
            if (document.body.getAttribute("aria-busy") === "true" || msg.includes("Выполняется команда")) {
                started = true;
                break;
            }
            if (messageBox?.classList.contains("error") && msg) {
                commandResult(`Последняя команда: ${label} — ошибка: ${msg}`, "error");
                return;
            }
            await new Promise((resolve) => setTimeout(resolve, 100));
        }
        if (!started || token !== currentCommand) {
            commandResult(`Последняя команда: ${label} не была запущена или отменена.`, "");
            return;
        }

        commandResult(`Последняя команда: ${label} выполняется… Проверяю фактическое состояние сервера.`, "pending");
        for (let i = 0; i < 90 && token === currentCommand; i += 1) {
            try {
                const status = await apiStatus();
                render(status);
                if (expected(action, status)) {
                    commandResult(successText(action, status), "ok");
                    return;
                }
            } catch (_) {}

            const msg = messageBox?.textContent || "";
            if (messageBox?.classList.contains("error") && msg) {
                commandResult(`Последняя команда: ${label} — ошибка: ${msg}`, "error");
                return;
            }
            await new Promise((resolve) => setTimeout(resolve, 1000));
        }
        if (token === currentCommand) {
            commandResult(`Последняя команда: ${label} — результат не подтверждён за 90 секунд. Нажмите «Обновить данные» и проверьте журнал.`, "error");
        }
    }

    function bindCommands() {
        const actions = {
            serverStart: ["start", "запуск"],
            serverRestart: ["restart", "перезапуск"],
            serverStop: ["stop", "остановка"],
        };
        document.addEventListener("click", (event) => {
            const button = event.target.closest?.("button");
            const item = button ? actions[button.id] : null;
            if (!item || button.disabled) return;
            const token = ++currentCommand;
            commandResult(`Последняя команда: ${item[1]} — ожидание выполнения…`, "pending");
            void observeCommand(item[0], item[1], token);
        }, true);
    }

    function init() {
        ensurePanel();
        bindCommands();
        void refresh();
        window.setInterval(() => void refresh(), POLL_MS);
        document.addEventListener("visibilitychange", () => {
            if (!document.hidden) void refresh();
        });
        $("refreshAll")?.addEventListener("click", () => window.setTimeout(() => void refresh(), 250));
    }

    if (document.readyState === "loading") document.addEventListener("DOMContentLoaded", init, {once: true});
    else init();
})();
