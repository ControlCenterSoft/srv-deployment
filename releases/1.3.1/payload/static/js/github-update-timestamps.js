(() => {
    "use strict";

    const attemptNode = document.getElementById("githubLastUpdateAttempt");
    const successNode = document.getElementById("githubLastSuccessfulUpdate");
    if (!attemptNode || !successNode) return;

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

            const legacyUpdatedAt = status.result === "updated" ? status.checked_at : null;
            // A pre-schema-3 successful installation was necessarily also an
            // update attempt. release.synced_at therefore provides a stable
            // migration fallback after later ordinary checks overwrite result.
            const lastAttempt = status.last_update_attempt_at || legacyUpdatedAt || release.synced_at || null;
            const lastSuccess = status.last_successful_update_at || legacyUpdatedAt || release.synced_at || null;

            attemptNode.textContent = formatDate(lastAttempt);
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
