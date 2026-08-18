(() => {
    "use strict";

    const checkNode = document.getElementById("githubLastUpdateCheck");
    const successNode = document.getElementById("githubLastSuccessfulUpdate");
    if (!checkNode || !successNode) return;

    let timer = null;

    function formatDate(value) {
        if (!value) return "—";
        const date = new Date(value);
        return Number.isNaN(date.getTime()) ? String(value) : date.toLocaleString("ru-RU");
    }

    async function fetchJson(url) {
        const response = await fetch(url, {
            cache: "no-store",
            credentials: "same-origin",
        });
        if (response.status === 401) {
            window.top.location.replace("/login");
            throw new Error("authentication required");
        }
        if (!response.ok) throw new Error(`HTTP ${response.status}`);
        return response.json();
    }

    async function refresh() {
        try {
            const [configurationPayload, healthPayload] = await Promise.all([
                fetchJson("/api/v1/system/configuration"),
                fetchJson("/api/v1/health"),
            ]);
            const configuration = configurationPayload.data || {};
            const github = configuration.github_updates || {};
            const status = github.status || {};
            const release = (healthPayload.data && healthPayload.data.release) || {};

            // 2.0 separates discovery/check time from update-attempt time.
            // checked_at remains a migration fallback for schema-2/early-schema-3 hosts.
            const lastCheck = status.last_check_at || status.checked_at || null;
            const legacyUpdatedAt = status.result === "updated" ? status.checked_at : null;
            // Preserve a proven historical success if the old updater recorded one.
            // release.synced_at is only the final migration fallback; the 2.0 updater
            // writes last_successful_update_at after an accepted transaction.
            const lastSuccess = status.last_successful_update_at || legacyUpdatedAt || release.synced_at || null;

            checkNode.textContent = formatDate(lastCheck);
            successNode.textContent = formatDate(lastSuccess);
        } catch (_) {
            // The main system page owns global error reporting. Keep the last
            // successfully rendered timestamps if this supplemental refresh fails.
        }
    }

    refresh();
    timer = window.setInterval(refresh, 5000);
    window.addEventListener("beforeunload", () => {
        if (timer !== null) window.clearInterval(timer);
    }, {once: true});
})();
